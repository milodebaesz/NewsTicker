import Foundation
import Observation

// Centrale staat + ophaal/scoor-pijplijn (de iOS-tegenhanger van background.ts).
@MainActor @Observable
final class AppStore {
    private static let maxItems = 500
    private static let maxAgeDays = 7.0

    private(set) var items: [FeedItem] = Persist.load([FeedItem].self, "items") ?? []
    private(set) var lastRefresh: Date? = Persist.load(Date.self, "lastRefresh")
    private(set) var lastError = ""
    private(set) var isRefreshing = false
    private(set) var scoringRemaining = 0 // nog te scoren artikelen in deze ronde

    var sources: [Source] = Persist.load([Source].self, "sources") ?? Source.defaults {
        didSet { Persist.save(sources, "sources") }
    }
    var settings: AppSettings = Persist.load(AppSettings.self, "settings") ?? AppSettings() {
        didSet { Persist.save(settings, "settings") }
    }
    var profile: InterestProfile = Persist.load(InterestProfile.self, "profile") ?? InterestProfile() {
        didSet { Persist.save(profile, "profile") }
    }
    // RSS-bronnen die de gebruiker in het filter heeft uitgevinkt.
    var hiddenSources: Set<String> = Persist.load(Set<String>.self, "hiddenSources") ?? [] {
        didSet { Persist.save(hiddenSources, "hiddenSources") }
    }
    var openAIKey: String = Keychain.get("openaiKey") {
        didSet { Keychain.set(openAIKey, for: "openaiKey") }
    }

    /// Wordt er op dit moment met AI gescoord/gesorteerd?
    var scoringActive: Bool {
        switch settings.engine {
        case .apple: AppleScoring.isAvailable
        case .openAI: !openAIKey.isEmpty
        case .off: false
        }
    }

    var isStale: Bool {
        guard let lastRefresh, !items.isEmpty else { return true }
        return Date.now.timeIntervalSince(lastRefresh) > Double(max(5, settings.refreshMinutes)) * 60
    }

    // MARK: - Pijplijn

    /// Haalt alle bronnen op. Het scoren loopt daarna los op de achtergrond
    /// verder (zie `scoringTask`), zodat verversen snel klaar is.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        let (collected, errors) = await Self.fetchAll(sources.filter(\.enabled))

        upsert(collected)
        await backfillImages()
        pruneOld()

        lastRefresh = .now
        lastError = errors.joined(separator: " · ")
        Persist.save(lastRefresh, "lastRefresh")
        isRefreshing = false
        feedVersion += 1
        startScoring()
    }

    /// Verhoogd zodra er nieuwe items of nieuwe scores zijn; de feed gebruikt
    /// dit om een nieuwe volgorde aan te bieden.
    private(set) var feedVersion = 0
    private var scoringTask: Task<Void, Never>?

    func startScoring() {
        guard scoringTask == nil else { return }
        scoringTask = Task {
            if let error = await rescore() {
                lastError = [lastError, error].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            scoringTask = nil
            feedVersion += 1
        }
    }

    /// Voor de achtergrondtaak: wacht tot ook het scoren klaar is.
    func waitForScoring() async {
        await scoringTask?.value
    }

    // Voegt nieuwe items toe en behoudt de lees-/verberg-/score-status van
    // items die we al kenden (gematcht op id).
    private func upsert(_ incoming: [FeedItem]) {
        var byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for var it in incoming {
            if let prev = byId[it.id] {
                it.read = prev.read
                it.dismissed = prev.dismissed
                it.relevance = prev.relevance
                it.reason = prev.reason
                // bewaar het AI-onderwerp als dat er al is, anders de feed-categorie
                if prev.relevance != nil { it.topic = prev.topic }
                if it.image.isEmpty { it.image = prev.image }
            }
            byId[it.id] = it
        }
        setItems(Array(byId.values))
    }

    // Vult ontbrekende afbeeldingen aan (max 14 per ronde om het licht te houden).
    private func backfillImages() async {
        let missing = items.filter { $0.image.isEmpty && !$0.dismissed }.prefix(14).map { ($0.id, $0.url) }
        patch(await Self.fetchImages(missing)) { $0.image = $1 }
    }

    // Parallel werk via losse Tasks i.p.v. withTaskGroup: de task group
    // crashte in geoptimaliseerde (Release) builds met Xcode 27
    // (TaskGroup::offer / __cxa_pure_virtual), met -Onone niet.

    // Alle bronnen tegelijk ophalen.
    nonisolated private static func fetchAll(_ sources: [Source]) async -> ([FeedItem], [String]) {
        let tasks = sources.map { src in
            Task { () -> Result<[FeedItem], Error> in
                do { return .success(try await RSS.fetch(src)) } catch { return .failure(error) }
            }
        }
        var collected: [FeedItem] = []
        var errors: [String] = []
        for (src, task) in zip(sources, tasks) {
            switch await task.value {
            case .success(let fetched): collected += fetched
            case .failure(let error): errors.append("\(src.label): \(error.localizedDescription)")
            }
        }
        return (collected, errors)
    }

    nonisolated private static func fetchImages(_ items: [(String, String)]) async -> [String: String] {
        let tasks = items.map { id, url in Task { (id, await OGImage.fetch(url)) } }
        var found: [String: String] = [:]
        for task in tasks {
            let (id, img) = await task.value
            if !img.isEmpty { found[id] = img }
        }
        return found
    }

    // Scoort items die nog geen relevantie hebben.
    private func rescore() async -> String? {
        switch settings.engine {
        case .off: return nil
        case .apple: return await rescoreOnDevice()
        case .openAI: return await rescoreOpenAI()
        }
    }

    // Apple Intelligence: per artikel, een paar tegelijk, nieuwste eerst. Het
    // scherm werkt na elk groepje bij, zodat de volgorde zichtbaar ‘inloopt’.
    private func rescoreOnDevice() async -> String? {
        guard AppleScoring.isAvailable else { return nil }
        let unscored = items
            .filter { $0.relevance == nil && !$0.dismissed }
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(60)
        scoringRemaining = unscored.count
        defer { scoringRemaining = 0 }
        let profile = profile
        for chunk in stride(from: 0, to: unscored.count, by: 3).map({ Array(unscored.dropFirst($0).prefix(3)) }) {
            let tasks = chunk.map { item in Task { (item, await AppleScoring.score(item, profile: profile)) } }
            var scores: [String: Score] = [:]
            var failure: String? // details staan in het logboek
            for task in tasks {
                let (item, outcome) = await task.value
                switch outcome {
                case .scored(let score):
                    scores[item.id] = score
                case .refused:
                    // Neutraal tonen, en niet elke ronde opnieuw proberen.
                    scores[item.id] = Score(relevance: 40, reason: "", topic: item.topic.isEmpty ? "Overig" : item.topic)
                case .failed(let message):
                    failure = message
                }
            }
            patch(scores) { item, s in
                item.relevance = s.relevance
                item.reason = s.reason
                item.topic = s.topic
            }
            scoringRemaining -= chunk.count
            // Werkt het model helemaal niet (en scoorde dit groepje niets), dan
            // stoppen en de rest ongescoord laten voor een volgende ronde.
            if failure != nil, scores.isEmpty {
                return "Apple Intelligence kon de artikelen nu niet beoordelen; bij de volgende verversing wordt het opnieuw geprobeerd."
            }
        }
        return nil
    }

    // OpenAI: max 3 batches van 25 per ronde.
    private func rescoreOpenAI() async -> String? {
        guard !openAIKey.isEmpty else { return nil }
        var unscored = items.filter { $0.relevance == nil && !$0.dismissed }
        for _ in 0..<3 where !unscored.isEmpty {
            let batch = Array(unscored.prefix(25))
            unscored.removeFirst(batch.count)
            do {
                let scores = try await Scoring.scoreBatch(batch, key: openAIKey, model: settings.model, profile: profile)
                patch(scores) { item, s in
                    item.relevance = s.relevance
                    item.reason = s.reason
                    item.topic = s.topic
                }
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    private func pruneOld() {
        let cutoff = Date.now.addingTimeInterval(-Self.maxAgeDays * 86_400)
        let kept = items
            .filter { !$0.dismissed && $0.publishedAt > cutoff }
            .sorted { $0.publishedAt > $1.publishedAt }
        setItems(Array(kept.prefix(Self.maxItems)))
    }

    // Opnieuw scoren na een profielwijziging.
    func resetScores() {
        setItems(items.map { var i = $0; i.relevance = nil; i.reason = ""; return i })
    }

    // MARK: - Item-acties

    func markRead(_ item: FeedItem) { patch([item.id: ()]) { i, _ in i.read = true } }
    func dismiss(_ item: FeedItem) { patch([item.id: ()]) { i, _ in i.dismissed = true } }

    private func patch<V>(_ values: [String: V], _ apply: (inout FeedItem, V) -> Void) {
        guard !values.isEmpty else { return }
        setItems(items.map { item in
            guard let v = values[item.id] else { return item }
            var copy = item
            apply(&copy, v)
            return copy
        })
    }

    private func setItems(_ next: [FeedItem]) {
        items = next
        Persist.save(items, "items")
    }
}

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

    var isStale: Bool {
        guard let lastRefresh else { return true }
        return Date.now.timeIntervalSince(lastRefresh) > Double(max(5, settings.refreshMinutes)) * 60
    }

    // MARK: - Pijplijn

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var (collected, errors) = await Self.fetchAll(sources.filter(\.enabled))

        upsert(collected)
        await backfillImages()
        if let scoreError = await rescore() { errors.append(scoreError) }
        pruneOld()

        lastRefresh = .now
        lastError = errors.joined(separator: " · ")
        Persist.save(lastRefresh, "lastRefresh")
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

    // Scoort items die nog geen relevantie hebben (max 3 batches per ronde).
    private func rescore() async -> String? {
        guard settings.scoringEnabled, !openAIKey.isEmpty else { return nil }
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

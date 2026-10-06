import Foundation
import Observation

// Centrale staat + ophaal/scoor-pijplijn (de iOS-tegenhanger van background.ts).
@MainActor @Observable
final class AppStore {
    // Eén gedeelde instantie, ook voor de achtergrondtaken.
    static let shared = AppStore()

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
    private(set) var sourceStatus: [String: SourceStatus] = Persist.load([String: SourceStatus].self, "sourceStatus") ?? [:]

    // RSS-bronnen die de gebruiker in het filter heeft uitgevinkt.
    var hiddenSources: Set<String> = Persist.load(Set<String>.self, "hiddenSources") ?? [] {
        didSet { Persist.save(hiddenSources, "hiddenSources") }
    }
    var openAIKey: String = Keychain.get("openaiKey") {
        didSet { Keychain.set(openAIKey, for: "openaiKey") }
    }

    // MARK: - Eerste start

    private static let onboardingKey = "onboardingDone"

    /// Moet de introductie nog getoond worden?
    var needsOnboarding = false

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.onboardingKey) == nil {
            if items.isEmpty {
                needsOnboarding = true
            } else {
                // Bestaande gebruiker van vóór de introductie: niets opnieuw
                // vragen, en het oude standaardprofiel bewaren.
                defaults.set(true, forKey: Self.onboardingKey)
                if Persist.load(InterestProfile.self, "profile") == nil { profile = .legacy }
            }
        }
    }

    func completeOnboarding(sources chosen: [Source], profile newProfile: InterestProfile) {
        sources = chosen
        profile = newProfile
        items = []
        Persist.save(items, "items")
        preferences.reset()
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        needsOnboarding = false
        Task { await refresh() }
    }

    func restartOnboarding() {
        UserDefaults.standard.removeObject(forKey: Self.onboardingKey)
        needsOnboarding = true
    }

    /// Wordt er op dit moment met AI gescoord/gesorteerd?
    var scoringActive: Bool {
        switch settings.engine {
        case .apple: AppleScoring.isAvailable
        case .openAI: !openAIKey.isEmpty
        case .off: false
        }
    }

    // MARK: - Ochtendbriefing

    private(set) var briefing: Briefing? = Persist.load(Briefing.self, "briefing")
    private(set) var isBuildingBriefing = false

    /// Stelt de briefing opnieuw samen uit de huidige artikelen.
    func buildBriefing() async {
        guard !isBuildingBriefing else { return }
        isBuildingBriefing = true
        defer { isBuildingBriefing = false }
        let stories = BriefingBuilder.pickStories(from: items, hiddenSources: hiddenSources, rank: rank)
        let built = await BriefingBuilder.build(stories: stories)
        briefing = built
        Persist.save(built, "briefing")
    }

    /// Voor de achtergrondtaak: is het (bijna) tijd voor de briefing en is die
    /// vandaag nog niet gemaakt, stel hem dan samen en zet hem in de melding.
    func prepareBriefingIfDue() async {
        guard settings.briefingEnabled else { return }
        let dueSoon = BriefingNotifications.nextDate(minutes: settings.briefingMinutes).timeIntervalSinceNow < 3 * 3600
        guard dueSoon, !briefingIsForNextSlot else { return }
        await buildBriefing()
        await scheduleBriefingNotification()
    }

    /// Is de bewaarde briefing gemaakt in de 3 uur vóór het volgende moment?
    private var briefingIsForNextSlot: Bool {
        guard let briefing else { return false }
        let gap = BriefingNotifications.nextDate(minutes: settings.briefingMinutes).timeIntervalSince(briefing.createdAt)
        return gap > 0 && gap < 3 * 3600
    }

    /// Zet de melding voor het volgende moment: met koppen als de briefing al
    /// klaar is, anders met een algemene tekst.
    func scheduleBriefingNotification() async {
        await BriefingNotifications.shared.schedule(settings: settings, briefing: briefingIsForNextSlot ? briefing : nil)
    }

    var isStale: Bool {
        guard let lastRefresh, !items.isEmpty else { return true }
        return Date.now.timeIntervalSince(lastRefresh) > Double(max(5, settings.refreshMinutes)) * 60
    }

    // MARK: - Pijplijn

    /// Haalt alle bronnen op. Het scoren loopt daarna los op de achtergrond
    /// verder (zie `scoringTask`), zodat verversen snel klaar is.
    func refresh() async {
        guard !needsOnboarding else { return } // eerst bronnen kiezen
        // Loopt er al een verversing (bv. gestart door de app bij openen), wacht
        // daar dan op i.p.v. meteen terug te keren met nog oud nieuws.
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private var refreshTask: Task<Void, Never>?

    private func performRefresh() async {
        isRefreshing = true

        let results = await Self.fetchAll(sources.filter(\.enabled))
        var collected: [FeedItem] = []
        for (source, result) in results {
            var status = sourceStatus[source.id] ?? SourceStatus()
            switch result {
            case .success(let items):
                collected += items
                status.lastSuccess = .now
                status.lastCount = items.count
                status.failures = 0
                status.failingSince = nil
                status.lastError = ""
            case .failure(let error):
                status.failures += 1
                if status.failingSince == nil { status.failingSince = .now }
                status.lastError = error.localizedDescription
            }
            sourceStatus[source.id] = status
        }
        Persist.save(sourceStatus, "sourceStatus")
        let broken = sources.filter { $0.enabled && sourceStatus[$0.id]?.isBroken == true }.map(\.label)

        upsert(collected)
        pruneOld()

        lastRefresh = .now
        lastError = broken.isEmpty ? "" :
            "\(broken.formatted(.list(type: .and))) \(broken.count == 1 ? "werkt" : "werken") al een tijdje niet. Kijk bij Instellingen › Bronnen."
        Persist.save(lastRefresh, "lastRefresh")
        isRefreshing = false
        feedVersion += 1
        Task { await updateWidget() }
        startScoring()
    }

    /// Verhoogd zodra er nieuwe items of nieuwe scores zijn; de feed gebruikt
    /// dit om een nieuwe volgorde aan te bieden.
    private(set) var feedVersion = 0
    private var scoringTask: Task<Void, Never>?

    func startScoring() {
        guard scoringTask == nil else { return }
        scoringTask = Task {
            let error = await rescore()
            // Haperingen van Apple Intelligence lossen zich vanzelf op bij een
            // volgende ronde; alleen OpenAI-fouten (bv. een ongeldige key) zijn
            // iets waar de gebruiker zelf iets mee kan.
            if let error, settings.engine == .openAI {
                lastError = [lastError, error].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            scoringTask = nil
            feedVersion += 1
            await updateWidget()
        }
    }

    /// Zet de bovenste verhalen (volgens de gekozen volgorde) in de widget.
    func updateWidget() async {
        let candidates = items.filter { !$0.read && !$0.dismissed && !hiddenSources.contains($0.sourceLabel) }
        let sorted: [FeedItem]
        if settings.sort == .forYou {
            sorted = candidates.map { ($0, rankForYou($0)) }.sorted { $0.1 > $1.1 }.map(\.0)
        } else {
            sorted = candidates.sorted { $0.publishedAt > $1.publishedAt }
        }
        await WidgetUpdater.update(stories: StoryClusters.group(Array(sorted.prefix(60))))
    }

    /// Bij naar de achtergrond gaan: stoppen i.p.v. laten mislukken. De rest
    /// komt bij de volgende ronde of in de achtergrondtaak.
    func pauseScoring() {
        scoringTask?.cancel()
    }

    func clearError() { lastError = "" }

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
            }
            byId[it.id] = it
        }
        setItems(Array(byId.values))
    }

    // Parallel werk via losse Tasks i.p.v. withTaskGroup: de task group
    // crashte in geoptimaliseerde (Release) builds met Xcode 27
    // (TaskGroup::offer / __cxa_pure_virtual), met -Onone niet.

    // Alle bronnen tegelijk ophalen.
    nonisolated private static func fetchAll(_ sources: [Source]) async -> [(Source, Result<[FeedItem], Error>)] {
        let tasks = sources.map { src in
            Task { () -> Result<[FeedItem], Error> in
                do { return .success(try await RSS.fetch(src)) } catch { return .failure(error) }
            }
        }
        var results: [(Source, Result<[FeedItem], Error>)] = []
        for (src, task) in zip(sources, tasks) { results.append((src, await task.value)) }
        return results
    }

    // Scoort items die nog geen relevantie hebben.
    private func rescore() async -> String? {
        switch settings.engine {
        case .off: return nil
        case .apple: return await rescoreOnDevice()
        case .openAI: return await rescoreOpenAI()
        }
    }

    // Apple Intelligence is zwaar voor de telefoon. In de app scoren we daarom
    // alleen de nieuwste paar artikelen, één tegelijk en met lage prioriteit;
    // de rest gebeurt in de achtergrondtaak (`scoreBacklog`) als iOS de
    // telefoon rustig vindt.
    static let foregroundScoreLimit = 12

    private func rescoreOnDevice(limit: Int = AppStore.foregroundScoreLimit, maxAge: TimeInterval? = 48 * 3600) async -> String? {
        guard AppleScoring.isAvailable else { return nil }
        prescoreMuted()
        let cutoff = maxAge.map { Date.now.addingTimeInterval(-$0) } ?? .distantPast
        let unscored = items
            .filter { $0.relevance == nil && !$0.dismissed && $0.publishedAt > cutoff }
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(limit)
        guard !unscored.isEmpty else { return nil }
        scoringRemaining = unscored.count
        defer {
            scoringRemaining = 0
            Persist.save(items, "items")
        }
        let profile = profile
        var pending: [String: Score] = [:]
        var failures = 0
        for item in unscored {
            if Task.isCancelled { break }
            let outcome = await Task(priority: .utility) { await AppleScoring.score(item, profile: profile) }.value
            switch outcome {
            case .scored(let score):
                pending[item.id] = score
                failures = 0
            case .refused:
                // Neutraal tonen, en niet elke ronde opnieuw proberen.
                pending[item.id] = Score(relevance: 40, reason: "", topic: item.topic.isEmpty ? "Overig" : item.topic)
            case .failed:
                failures += 1
            }
            scoringRemaining -= 1
            // Per 4 artikelen bijwerken i.p.v. na elk artikel: minder herberekenen.
            if pending.count >= 4 { applyScores(&pending) }
            // Werkt het model niet (3× achter elkaar mis), dan stoppen en later opnieuw.
            if failures >= 3 {
                applyScores(&pending)
                return "Apple Intelligence kon de artikelen nu niet beoordelen; bij de volgende verversing wordt het opnieuw geprobeerd."
            }
        }
        applyScores(&pending)
        return nil
    }

    private func applyScores(_ pending: inout [String: Score]) {
        patch(pending, save: false) { item, s in
            item.relevance = s.relevance
            item.reason = s.reason
            item.topic = s.topic
        }
        pending = [:]
    }

    /// Artikelen met een woord van de negeerlijst krijgen meteen een lage
    /// score, zonder het model te belasten.
    private func prescoreMuted() {
        let muted = profile.mute.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !muted.isEmpty else { return }
        var scores: [String: Score] = [:]
        for item in items where item.relevance == nil && !item.dismissed {
            let words = Set("\(item.title) \(item.topic)".lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            if muted.contains(where: { words.contains($0) }) {
                scores[item.id] = Score(relevance: 10, reason: "Op je negeerlijst", topic: item.topic.isEmpty ? "Overig" : item.topic)
            }
        }
        patch(scores, save: false) { item, s in
            item.relevance = s.relevance
            item.reason = s.reason
            item.topic = s.topic
        }
    }

    /// Achtergrondtaak: de achterstand wegwerken terwijl je de telefoon niet gebruikt.
    func scoreBacklog() async {
        guard settings.engine == .apple else { return }
        await scoringTask?.value // niet tegelijk met een lopende ronde
        _ = await rescoreOnDevice(limit: 150, maxAge: nil)
        feedVersion += 1
    }

    /// Zijn er nog ongescoorde artikelen voor de achtergrondtaak?
    var hasScoringBacklog: Bool {
        settings.engine == .apple && items.contains { $0.relevance == nil && !$0.dismissed }
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

    // MARK: - Leren van wat je leest

    var preferences: LearnedPreferences = Persist.load(LearnedPreferences.self, "preferences") ?? LearnedPreferences() {
        didSet { Persist.save(preferences, "preferences") }
    }

    /// Een signaal over een heel verhaal; telt één keer (het hoofdartikel),
    /// zodat een verhaal met drie bronnen niet driedubbel weegt.
    func learn(_ signal: LearnedPreferences.Signal, from story: StoryClusters.Story) {
        preferences.learn(signal, from: story.lead)
        switch signal {
        case .opened: story.all.forEach(markRead)
        case .dismissed, .less: story.all.forEach(dismiss)
        case .more: break
        }
    }

    /// Rangscore voor feed en briefing: AI-relevantie (of neutraal 55) plus
    /// wat de app van je geleerd heeft.
    func rank(_ item: FeedItem) -> Double {
        let base = scoringActive ? Double(item.relevance ?? 55) : 55
        return base + preferences.boost(for: item)
    }

    /// Rangscore voor "Voor jou": zakt 2 punten per uur, zodat een topper van
    /// gisteren (90, 18 uur oud → 54) niet boven vers nieuws blijft hangen.
    func rankForYou(_ item: FeedItem) -> Double {
        let hours = max(0, Date.now.timeIntervalSince(item.publishedAt) / 3600)
        return rank(item) - 2 * min(hours, 48)
    }

    private func patch<V>(_ values: [String: V], save: Bool = true, _ apply: (inout FeedItem, V) -> Void) {
        guard !values.isEmpty else { return }
        setItems(items.map { item in
            guard let v = values[item.id] else { return item }
            var copy = item
            apply(&copy, v)
            return copy
        }, save: save)
    }

    private func setItems(_ next: [FeedItem], save: Bool = true) {
        items = next
        if save { Persist.save(items, "items") }
    }
}

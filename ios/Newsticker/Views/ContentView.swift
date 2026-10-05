import SwiftUI
import WidgetKit

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var topic = ""
    @State private var showSettings = false
    @State private var showAddSource = false
    @State private var showBriefing = false
    #if DEBUG
    @State private var showAlgorithm = false
    @State private var showSourcesDebug = false
    @State private var showWidgetDebug = false
    #endif
    private let notifications = BriefingNotifications.shared
    @State private var reading: StoryClusters.Story?
    // De volgorde van de feed ligt vast tot je hem zelf ververst, zodat kaarten
    // niet verspringen terwijl je leest of terwijl de AI nog aan het scoren is.
    @State private var order: [String] = []
    @State private var newArticles = 0 // nieuw binnengekomen sinds de volgorde vastgezet werd
    @State private var orderAppliedAt = Date.distantPast
    @State private var applyAfterRefresh = false // terug in de app: verversing direct tonen
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Environment(\.scenePhase) private var scenePhase
    // Verhaalindeling (zelfde nieuws, meerdere bronnen) bij de vaste volgorde;
    // alleen opnieuw berekend als de volgorde verandert.
    @State private var groups: [[String]] = []

    private var scoring: Bool { store.scoringActive }

    // Gewenste volgorde op dit moment: drempel + sortering, zonder gelezen items.
    private var liveOrder: [String] {
        let minimum = Double(store.settings.minRelevance)
        var candidates: [(item: FeedItem, rank: Double)] = []
        for item in store.items where !item.dismissed && !item.read {
            // Drempel alleen op gescoorde artikelen; een geleerde voorkeur
            // kan een artikel er alsnog overheen tillen.
            if scoring && item.relevance != nil && store.rank(item) < minimum { continue }
            candidates.append((item, store.settings.sort == .forYou ? store.rankForYou(item) : 0))
        }
        if store.settings.sort == .newest {
            return candidates.sorted { $0.item.publishedAt > $1.item.publishedAt }.map { $0.item.id }
        }
        return Self.diversified(candidates)
    }

    /// "Voor jou": steeds het hoogst gerangschikte artikel kiezen, met een
    /// kleine straf voor elke eerdere keuze uit dezelfde bron, zodat één bron
    /// (bv. Hacker News) niet de hele top vult.
    private static func diversified(_ candidates: [(item: FeedItem, rank: Double)]) -> [String] {
        var pool = candidates.sorted { $0.rank > $1.rank }
        var perSource: [String: Int] = [:]
        var result: [String] = []
        result.reserveCapacity(pool.count)
        while !pool.isEmpty {
            // Alleen de eerste ~20 kandidaten bekijken: genoeg voor afwisseling, snel bij 500 artikelen.
            var best = 0
            var bestScore = -Double.infinity
            for i in pool.indices.prefix(20) {
                let score = pool[i].rank - 6 * Double(perSource[pool[i].item.sourceLabel, default: 0])
                if score > bestScore { best = i; bestScore = score }
            }
            let chosen = pool.remove(at: best)
            perSource[chosen.item.sourceLabel, default: 0] += 1
            result.append(chosen.item.id)
        }
        return result
    }

    /// Nieuwe volgorde én terug naar boven: na verversen of terugkomen.
    private func applyOrderFromTop() {
        applyOrder()
        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .top) }
    }

    private func applyOrder() {
        let next = liveOrder
        let byId = Dictionary(store.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let nextGroups = StoryClusters.group(next.compactMap { byId[$0] }).map { $0.all.map(\.id) }
        withAnimation(.snappy) {
            order = next
            groups = nextGroups
            newArticles = 0
            orderAppliedAt = .now
        }
    }

    // Items in de vastgezette volgorde die door bron-filter en zoekterm komen
    // (nog vóór het onderwerp-filter, zodat de chips de juiste opties tonen).
    // Gelezen items blijven (gedimd) staan tot de volgende verversing.
    private var preTopic: [FeedItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let byId = Dictionary(store.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byId[$0] }.filter { i in
            if i.dismissed || store.hiddenSources.contains(i.sourceLabel) { return false }
            if !q.isEmpty {
                return "\(i.title) \(i.summary) \(i.sourceLabel) \(i.topic)".lowercased().contains(q)
            }
            return true
        }
    }

    private var topics: [(String, Int)] {
        var counts: [String: Int] = [:]
        for i in preTopic where !i.topic.isEmpty { counts[i.topic, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(12).map { ($0.key, $0.value) }
    }

    private var visible: [FeedItem] {
        preTopic.filter { topic.isEmpty || $0.topic == topic }
    }

    // Verhalen in de vaste indeling, beperkt tot wat door de filters komt.
    private var visibleStories: [StoryClusters.Story] {
        let shown = visible
        let allowed = Set(shown.map(\.id))
        let byId = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return groups.compactMap { ids in
            let members = ids.filter(allowed.contains).compactMap { byId[$0] }
            guard let lead = members.first else { return nil }
            return StoryClusters.Story(lead: lead, others: Array(members.dropFirst()))
        }
    }

    // Volgt de vaste volgorde, zodat de band niet steeds opnieuw begint.
    private var tickerItems: [FeedItem] {
        let byId = Dictionary(store.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.lazy
            .compactMap { byId[$0] }
            .filter { !$0.dismissed && !$0.read && !store.hiddenSources.contains($0.sourceLabel) }
            .prefix(20).map { $0 }
    }

    private var sourceLabels: [String] {
        Set(store.items.filter { !$0.dismissed && !$0.read }.map(\.sourceLabel))
            .union(store.sources.filter(\.enabled).map(\.label))
            .sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        sortPicker
                        if !topics.isEmpty { topicChips }
                        if store.scoringRemaining > 0 { scoringBanner }
                        if !store.lastError.isEmpty { errorBanner }
                        Color.clear.frame(height: 12)
                        BentoFeed(stories: visibleStories, open: open)
                        if visible.isEmpty { emptyState }
                    } header: {
                        if store.settings.showTicker && !tickerItems.isEmpty {
                            TickerView(items: tickerItems, onTap: { open(StoryClusters.Story(lead: $0, others: [])) },
                                       paused: reading != nil || showBriefing || showSettings || showAddSource)
                        }
                    }
                }
            }
            .background(Theme.canvas)
            .scrollPosition($scrollPosition)
            .refreshable {
                await store.refresh()
                applyOrder()
            }
            .overlay(alignment: .top) {
                if newArticles > 0 {
                    Button { applyOrderFromTop() } label: {
                        Label(newArticles == 1 ? "1 nieuw artikel" : "\(newArticles) nieuwe artikelen", systemImage: "arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.button)
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: store.feedVersion) {
                // Eerste keer meteen tonen. Daarna alleen een knop bij écht nieuwe
                // artikelen; betere scores en geleerde voorkeuren worden stil
                // verwerkt bij de volgende verversing of als je terugkomt.
                if order.isEmpty || applyAfterRefresh {
                    applyAfterRefresh = false
                    applyOrderFromTop()
                } else {
                    let shown = Set(order)
                    let count = liveOrder.filter { !shown.contains($0) }.count
                    if count != newArticles { withAnimation(.snappy) { newArticles = count } }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Terug na een tijdje weg: meteen de beste volgorde.
                if phase == .active, Date.now.timeIntervalSince(orderAppliedAt) > 10 * 60 {
                    applyAfterRefresh = store.isStale || store.isRefreshing
                    applyOrderFromTop()
                }
            }
            .onChange(of: store.settings.minRelevance) { applyOrder() }
            .onChange(of: store.settings.sort) { applyOrder() }
            .onChange(of: store.preferences.influence) { applyOrder() }
            .onChange(of: store.settings.engine) { applyOrder() }
            .searchable(text: $query, prompt: "Zoeken…")
            .navigationTitle("Newsticker")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { statusLabel }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Briefing", systemImage: "sun.horizon") { showBriefing = true }
                    sourceMenu
                    Button("Instellingen", systemImage: "gearshape") { showSettings = true }
                }
            }
            .overlay(alignment: .top) {
                if store.isRefreshing && store.items.isEmpty { ProgressView().padding(.top, 80) }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAddSource) { AddSourceView() }
        .sheet(isPresented: $showBriefing) { BriefingView() }
        // Getikt op een kop in de widget: newsticker://story/<id>
        .onOpenURL { url in
            guard url.scheme == WidgetSnapshot.urlScheme, url.host() == "story" else { return }
            openStory(id: url.lastPathComponent)
        }
        #if DEBUG
        .sheet(isPresented: $showAlgorithm) { NavigationStack { AlgorithmView() } }
        .sheet(isPresented: $showSourcesDebug) { NavigationStack { SourcesView() } }
        .sheet(isPresented: $showWidgetDebug) { WidgetPreviewScreen() }
        .task { await openScreenForScreenshot() }
        #endif
        .fullScreenCover(isPresented: Binding(get: { store.needsOnboarding }, set: { _ in })) {
            OnboardingView()
        }
        .onChange(of: store.needsOnboarding) { _, needs in
            // Na de introductie: nieuwe bronnen, dus een verse volgorde.
            if !needs {
                order = []
                groups = []
            }
        }
        // Getikt op de briefingmelding.
        .onChange(of: notifications.openRequested, initial: true) {
            guard notifications.openRequested else { return }
            notifications.openRequested = false
            reading = nil
            showSettings = false
            showAddSource = false
            showBriefing = true
        }
        .sheet(item: $reading) { ReaderView(story: $0) }
        .task {
            applyOrder()
            if store.settings.briefingEnabled {
                _ = await notifications.requestPermission() // vraagt alleen de eerste keer
                await store.scheduleBriefingNotification()
            }
            // Verversen bij het openen: nieuwe artikelen meteen tonen, zonder knop.
            if store.isStale { await store.refresh(); applyOrder() } else { store.startScoring() }
        }
    }

    private func openStory(id: String) {
        let byId = Dictionary(store.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard let lead = byId[id] else { return }
        // Zelfde verhaal bij andere bronnen meenemen, als dat al bekend is.
        let others = (groups.first { $0.contains(id) } ?? [id]).filter { $0 != id }.compactMap { byId[$0] }
        showBriefing = false
        showSettings = false
        showAddSource = false
        open(StoryClusters.Story(lead: lead, others: others))
    }

    private func open(_ story: StoryClusters.Story) {
        reading = story
        store.learn(.opened, from: story)
    }

    private var statusLabel: some View {
        Group {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button("Verversen", systemImage: "arrow.clockwise") {
                    Task {
                        await store.refresh()
                        applyOrder()
                    }
                }
            }
        }
    }

    private var scoringBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(store.settings.engine == .apple
                 ? "Apple Intelligence beoordeelt \(store.scoringRemaining) nieuwe artikelen…"
                 : "\(store.scoringRemaining) nieuwe artikelen worden beoordeeld…")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var subtitle: String {
        guard let last = store.lastRefresh else { return "nog niet bijgewerkt" }
        let ago = last.timeAgo
        return ago == "zojuist" ? "zojuist bijgewerkt" : "bijgewerkt \(ago) geleden"
    }

    private var sourceMenu: some View {
        Menu {
            Button("Bron toevoegen…", systemImage: "plus") { showAddSource = true }
            Section("Toon bronnen") {
                Button("Alles") { store.hiddenSources = [] }
                Button("Geen") { store.hiddenSources = Set(sourceLabels) }
            }
            ForEach(sourceLabels, id: \.self) { label in
                Toggle(label, isOn: Binding(
                    get: { !store.hiddenSources.contains(label) },
                    set: { on in
                        if on { store.hiddenSources.remove(label) } else { store.hiddenSources.insert(label) }
                    }
                ))
            }
        } label: {
            Label("Bronnen", systemImage: store.hiddenSources.isEmpty
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var sortPicker: some View {
        Picker("Volgorde", selection: Binding(
            get: { store.settings.sort },
            set: { store.settings.sort = $0 }
        )) {
            ForEach(FeedSort.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "Alle onderwerpen", selected: topic.isEmpty) { topic = "" }
                ForEach(topics, id: \.0) { t, n in
                    Chip(title: t, count: n, selected: topic == t) { topic = topic == t ? "" : t }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(store.lastError)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Sluiten", systemImage: "xmark") { withAnimation { store.clearError() } }
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red.opacity(0.7))
        }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: .rect(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Geen items.").foregroundStyle(Theme.muted)
            if !query.isEmpty || !topic.isEmpty {
                Button("Filters wissen") { query = ""; topic = "" }
            } else {
                Text("Trek omlaag om te verversen, of voeg een bron toe.")
                    .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                Button("Bron toevoegen", systemImage: "plus") { showAddSource = true }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
    }
}

private struct Chip: View {
    let title: String
    var count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count { Text("\(count)").opacity(0.6) }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Theme.muted)
            .background(selected ? Theme.ink : Color.clear, in: .capsule)
            .overlay { if !selected { Capsule().strokeBorder(Theme.line) } }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
// Alleen voor screenshots en controle: `-NTScreenshot feed|reader|briefing|algorithm|sources|widget|onboarding`
// bij het opstarten opent direct dat scherm. Niet in de App Store-versie.
extension ContentView {
    fileprivate func openScreenForScreenshot() async {
        guard let i = CommandLine.arguments.firstIndex(of: "-NTScreenshot"),
              CommandLine.arguments.indices.contains(i + 1) else { return }
        let screen = CommandLine.arguments[i + 1]
        if screen == "onboarding" { store.restartOnboarding(); return }
        // Wachten tot de feed gevuld is.
        for _ in 0..<60 where visibleStories.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
        switch screen {
        case "reader":
            reading = visibleStories.first { !$0.others.isEmpty } ?? visibleStories.first
        case "briefing":
            showBriefing = true
        case "sources":
            showSourcesDebug = true
        case "widget":
            await store.updateWidget()
            showWidgetDebug = true
        case "algorithm":
            // Voorbeeldprofiel voor de screenshot.
            if store.preferences.isEmpty {
                store.preferences.weights = [
                    "onderwerp:Tech & AI": 7, "onderwerp:Wetenschap": 4.5, "bron:Tweakers": 3,
                    "woord:Apple": 3.5, "woord:Verstappen": 2.5, "woord:kunstmatige": 3.2,
                    "onderwerp:Voetbal": -6, "onderwerp:Showbizz": -3.5, "woord:Champions League": -2,
                ]
            }
            showAlgorithm = true
        default:
            break
        }
    }
}

/// De widget in zijn echte maten (iPhone Pro Max), om de weergave te controleren.
private struct WidgetPreviewScreen: View {
    private let snapshot = WidgetSnapshot.load() ?? .placeholder

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    tile(.systemSmall, 170, 170)
                    VStack(alignment: .leading) {
                        NewstickerWidgetView(family: .accessoryRectangular, snapshot: snapshot)
                            .frame(width: 160, height: 72, alignment: .leading)
                            .padding(8)
                            .background(.black.opacity(0.75), in: .rect(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                }
                tile(.systemMedium, 364, 170)
                tile(.systemLarge, 364, 382)
            }
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [.teal, .blue], startPoint: .top, endPoint: .bottom))
    }

    private func tile(_ family: WidgetFamily, _ width: CGFloat, _ height: CGFloat) -> some View {
        NewstickerWidgetView(family: family, snapshot: snapshot)
            .frame(width: width, height: height)
            .background(WTheme.canvas)
            .clipShape(.rect(cornerRadius: 22))
    }
}
#endif

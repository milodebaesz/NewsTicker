import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var topic = ""
    @State private var showSettings = false
    @State private var showAddSource = false
    @State private var showBriefing = false
    private let notifications = BriefingNotifications.shared
    @State private var reading: StoryClusters.Story?
    // De volgorde van de feed ligt vast tot je hem zelf ververst, zodat kaarten
    // niet verspringen terwijl je leest of terwijl de AI nog aan het scoren is.
    @State private var order: [String] = []
    @State private var newOrderReady = false

    private var scoring: Bool { store.scoringActive }

    // Gewenste volgorde op dit moment: drempel + sortering, zonder gelezen items.
    private var liveOrder: [String] {
        store.items
            .filter { i in
                if i.dismissed || i.read { return false }
                if scoring, let r = i.relevance, r < store.settings.minRelevance { return false }
                return true
            }
            .sorted { a, b in
                // op relevantie als scoring aan staat (nog niet gescoord telt als
                // middelmatig), anders nieuwste eerst
                let ra = a.relevance ?? 55, rb = b.relevance ?? 55
                if scoring && ra != rb { return ra > rb }
                return a.publishedAt > b.publishedAt
            }
            .map(\.id)
    }

    // De getoonde volgorde zonder intussen gelezen of verborgen items.
    private var unreadOrder: [String] {
        let unread = Set(store.items.filter { !$0.read && !$0.dismissed }.map(\.id))
        return order.filter(unread.contains)
    }

    private func applyOrder() {
        withAnimation(.snappy) {
            order = liveOrder
            newOrderReady = false
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

    private var tickerItems: [FeedItem] {
        store.items
            .filter { !$0.dismissed && !$0.read && !store.hiddenSources.contains($0.sourceLabel) }
            .sorted { ($0.relevance ?? 0) > ($1.relevance ?? 0) }
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
                        if !topics.isEmpty { topicChips }
                        if store.scoringRemaining > 0 { scoringBanner }
                        if !store.lastError.isEmpty { errorBanner }
                        BentoFeed(stories: StoryClusters.group(visible), open: open)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        if visible.isEmpty { emptyState }
                    } header: {
                        if !tickerItems.isEmpty {
                            TickerView(items: tickerItems) { open(StoryClusters.Story(lead: $0, others: [])) }
                        }
                    }
                }
            }
            .background(Theme.canvas)
            .refreshable {
                await store.refresh()
                applyOrder()
            }
            .overlay(alignment: .top) {
                if newOrderReady {
                    Button { applyOrder() } label: {
                        Label("Nieuwe volgorde — tik om bij te werken", systemImage: "arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.brand)
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: store.feedVersion) {
                // Eerste keer meteen tonen; daarna alleen aanbieden.
                if order.isEmpty {
                    applyOrder()
                } else if liveOrder != unreadOrder {
                    withAnimation(.snappy) { newOrderReady = true }
                }
            }
            .onChange(of: store.settings.minRelevance) { applyOrder() }
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
            if store.isStale { await store.refresh() } else { store.startScoring() }
        }
    }

    private func open(_ story: StoryClusters.Story) {
        reading = story
        story.all.forEach(store.markRead)
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
        Text(store.lastError)
            .font(.footnote)
            .foregroundStyle(.red)
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

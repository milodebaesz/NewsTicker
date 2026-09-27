import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var topic = ""
    @State private var showSettings = false
    @State private var reading: FeedItem?

    private var scoring: Bool { store.settings.scoringEnabled && !store.openAIKey.isEmpty }

    // Items die door bron-filter, zoekterm en relevantiedrempel komen
    // (nog vóór het onderwerp-filter, zodat de chips de juiste opties tonen).
    private var preTopic: [FeedItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.items.filter { i in
            if i.dismissed || i.read || store.hiddenSources.contains(i.sourceLabel) { return false }
            if scoring, let r = i.relevance, r < store.settings.minRelevance { return false }
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
        preTopic
            .filter { topic.isEmpty || $0.topic == topic }
            .sorted { a, b in
                // op relevantie als scoring aan staat, anders nieuwste eerst
                let ra = a.relevance ?? -1, rb = b.relevance ?? -1
                if scoring && ra != rb { return ra > rb }
                return a.publishedAt > b.publishedAt
            }
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
                        if !store.lastError.isEmpty { errorBanner }
                        BentoFeed(items: visible, open: open)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        if visible.isEmpty { emptyState }
                    } header: {
                        if !tickerItems.isEmpty { TickerView(items: tickerItems, onTap: open) }
                    }
                }
            }
            .background(Theme.canvas)
            .refreshable { await store.refresh() }
            .searchable(text: $query, prompt: "Zoeken…")
            .navigationTitle("Newsticker")
            .modifier(Subtitle(text: subtitle))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { statusLabel }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    sourceMenu
                    Button("Instellingen", systemImage: "gearshape") { showSettings = true }
                }
            }
            .overlay(alignment: .top) {
                if store.isRefreshing && store.items.isEmpty { ProgressView().padding(.top, 80) }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $reading) { SafariView(url: URL(string: $0.url)!).ignoresSafeArea() }
        .task { if store.isStale { await store.refresh() } }
    }

    private func open(_ item: FeedItem) {
        guard URL(string: item.url) != nil else { return }
        reading = item
        store.markRead(item)
    }

    private var statusLabel: some View {
        Group {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button("Verversen", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
            }
        }
    }

    private var subtitle: String {
        guard let last = store.lastRefresh else { return "nog niet bijgewerkt" }
        let ago = last.timeAgo
        return ago == "zojuist" ? "zojuist bijgewerkt" : "bijgewerkt \(ago) geleden"
    }

    private var sourceMenu: some View {
        Menu {
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
                Text("Trek omlaag om te verversen, of voeg bronnen toe via instellingen.")
                    .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
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

private struct Subtitle: ViewModifier {
    let text: String
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.navigationSubtitle(text) } else { content }
    }
}

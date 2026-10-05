import SwiftUI

// Bron toevoegen: zoeken in de eigen bronnenlijst, een website-URL
// doorzoeken op feeds, of kiezen uit populaire bronnen. Per feed kun je
// eerst de laatste koppen bekijken.
struct AddSourceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var searching = false
    @State private var results: [FeedCandidate] = []
    @State private var siteFeeds: [FeedCandidate] = []
    @State private var error = ""
    @State private var addedCount = 0

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    catalog
                } else {
                    searchResults
                }
            }
            .navigationTitle("Bron toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Naam, onderwerp of website")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
            // Zoekt automatisch zodra je even stopt met typen.
            .task(id: trimmed) {
                guard !trimmed.isEmpty else { reset(); return }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await search(trimmed)
            }
        }
        .onDisappear {
            if addedCount > 0 { Task { await store.refresh() } }
        }
    }

    // MARK: - Secties

    private var catalog: some View {
        Group {
            Section {
                Label("Zoek op naam (\"Tweakers\"), onderwerp (\"apple\", \"f1\", \"klimaat\") of typ een website-adres.",
                      systemImage: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(FeedCatalog.categories) { cat in
                Section {
                    ForEach(cat.feeds) { FeedRow(candidate: $0, onAdd: add) }
                } header: {
                    Label(cat.name, systemImage: cat.symbol)
                }
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if searching && results.isEmpty && siteFeeds.isEmpty {
            HStack {
                Spacer()
                ProgressView("Zoeken…")
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
        if !siteFeeds.isEmpty {
            Section("Op deze website") {
                ForEach(siteFeeds) { FeedRow(candidate: $0, onAdd: add) }
            }
        }
        if !results.isEmpty {
            Section("Uit de lijst") {
                ForEach(results) { FeedRow(candidate: $0, onAdd: add) }
            }
        }
        if !searching && results.isEmpty && siteFeeds.isEmpty {
            ContentUnavailableView {
                Label("Niets gevonden", systemImage: "dot.radiowaves.up.forward")
            } description: {
                Text(error.isEmpty ? "Probeer een andere zoekterm, of de naam van de website." : error)
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Acties

    private func reset() {
        results = []
        siteFeeds = []
        error = ""
        searching = false
    }

    private func search(_ q: String) async {
        searching = true
        error = ""
        // Eerst de eigen lijst: direct, zonder internet.
        results = FeedCatalog.search(q)

        // Een website-adres: de feeds die de site zelf publiceert. Eén los woord
        // zonder treffer in de lijst ("bright"): probeer bright.nl en bright.com.
        var sites: [String] = []
        if FeedSearch.looksLikeURL(q) {
            sites = [q]
        } else if results.isEmpty, !q.contains(" "), q.count >= 3 {
            sites = ["\(q).nl", "\(q).com"]
        }
        var found: [FeedCandidate] = []
        for site in sites {
            found += (try? await Discover.feeds(for: site)) ?? []
            guard q == trimmed else { return } // intussen verder getypt
        }
        let known = Set(results.map { Discover.key($0.url) })
        var seen = Set<String>()
        siteFeeds = found.filter { !known.contains(Discover.key($0.url)) && seen.insert(Discover.key($0.url)).inserted }
        if results.isEmpty && siteFeeds.isEmpty {
            error = "Niet gevonden in de lijst. Typ het adres van de website, bijvoorbeeld \"nos.nl\", dan zoekt de app daar naar feeds."
        }
        searching = false
    }

    private func add(_ c: FeedCandidate) {
        let host = URL(string: c.url)?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? c.url
        let label = c.title.isEmpty || c.title == c.url ? host : c.title
        store.sources.append(Source(id: UUID().uuidString, url: c.url, label: label, enabled: true))
        addedCount += 1
    }
}

// Eén gevonden feed: icoon, naam, omschrijving; uitklappen toont de laatste koppen.
private struct FeedRow: View {
    let candidate: FeedCandidate
    let onAdd: (FeedCandidate) -> Void

    @Environment(AppStore.self) private var store
    @State private var expanded = false
    @State private var preview: [FeedItem]?
    @State private var previewFailed = false

    private var added: Bool { store.sources.contains { Discover.key($0.url) == Discover.key(candidate.url) } }

    private var iconURL: URL? {
        if !candidate.icon.isEmpty { return URL(string: candidate.icon) }
        let host = candidate.site.isEmpty ? URL(string: candidate.url)?.host(percentEncoded: false) ?? "" : candidate.site
        return host.isEmpty ? nil : URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        icon
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(candidate.title).font(.body.weight(.medium)).lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(expanded ? 180 : 0))
                            }
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .multilineTextAlignment(.leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .accessibilityHint(expanded ? "Verberg voorbeeld" : "Toon de laatste koppen")
                Button {
                    onAdd(candidate)
                } label: {
                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(added ? Color.green : Theme.brand)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .disabled(added)
                .accessibilityLabel(added ? "Toegevoegd" : "Toevoegen")
            }

            if expanded { previewList }
        }
        .task(id: expanded) {
            guard expanded, preview == nil else { return }
            let src = Source(id: "preview", url: candidate.url, label: candidate.title, enabled: true)
            do {
                preview = Array(try await RSS.fetch(src).sorted { $0.publishedAt > $1.publishedAt }.prefix(3))
            } catch {
                previewFailed = true
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !candidate.site.isEmpty { parts.append(candidate.site) }
        let head = parts.joined(separator: " · ")
        if candidate.detail.isEmpty { return head.isEmpty ? candidate.url : head }
        return head.isEmpty ? candidate.detail : "\(head) — \(candidate.detail)"
    }

    private var icon: some View {
        AsyncImage(url: iconURL) { phase in
            if case .success(let img) = phase {
                img.resizable().scaledToFit()
            } else {
                Image(systemName: "dot.radiowaves.up.forward").foregroundStyle(Theme.brand)
            }
        }
        .frame(width: 28, height: 28)
        .background(Theme.subtle, in: .rect(cornerRadius: 7))
        .clipShape(.rect(cornerRadius: 7))
    }

    @ViewBuilder private var previewList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview {
                if preview.isEmpty {
                    Text("Deze feed bevat nu geen artikelen.")
                } else {
                    ForEach(preview) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("▸").foregroundStyle(Theme.accent)
                            Text(item.title).foregroundStyle(.primary).lineLimit(2)
                            Spacer(minLength: 4)
                            Text(item.publishedAt.timeAgo)
                        }
                    }
                }
            } else if previewFailed {
                Label("Deze feed kon niet worden geladen.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 40)
    }
}

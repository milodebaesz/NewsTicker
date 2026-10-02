import SwiftUI

// Leesweergave in de app: AI-samenvatting van het verhaal (over alle bronnen),
// de artikeltekst zonder cookiemuren, en de andere bronnen om naar te wisselen.
struct ReaderView: View {
    let story: StoryClusters.Story

    @Environment(\.dismiss) private var dismiss
    @State private var selected: FeedItem
    @State private var articles: [String: ArticleReader.Article] = [:]
    @State private var failed: Set<String> = []
    @State private var summary: String?
    @State private var summaryFailed = false
    @State private var webPage: FeedItem?

    init(story: StoryClusters.Story) {
        self.story = story
        _selected = State(initialValue: story.lead)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(alignment: .leading, spacing: 18) {
                        meta
                        Text(selected.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if Summarizer.isAvailable && !summaryFailed { summaryCard }
                        if !story.others.isEmpty { sourcesSection }
                        articleBody
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Theme.canvas)
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten", systemImage: "xmark") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url = URL(string: selected.url) { ShareLink(item: url) }
                    Button("Open website", systemImage: "safari") { webPage = selected }
                }
            }
        }
        .sheet(item: $webPage) { SafariView(url: URL(string: $0.url)!).ignoresSafeArea() }
        .task { await loadAll() }
    }

    // MARK: - Onderdelen

    @ViewBuilder private var hero: some View {
        if let url = URL(string: selected.image), !selected.image.isEmpty {
            Theme.subtle
                .overlay {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() } else { Theme.subtle }
                    }
                }
                .frame(height: 260)
                .clipped()
        } else {
            Color.clear.frame(height: 90)
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            Text(selected.sourceLabel).fontWeight(.semibold).foregroundStyle(Theme.brand)
            Text("· \(selected.publishedAt.timeAgo)")
            if !selected.topic.isEmpty {
                Text(selected.topic)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay { Capsule().strokeBorder(Theme.line) }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(story.others.isEmpty ? "Samenvatting" : "Samenvatting van \(story.all.count) bronnen", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.brand)
            if let summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Apple Intelligence vat samen…").font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brand.opacity(0.07), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.brand.opacity(0.18)) }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ook bij").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            ForEach(story.all) { item in
                Button {
                    withAnimation(.snappy) { selected = item }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.sourceLabel)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                            .frame(width: 92, alignment: .leading)
                        Text(item.title)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if item.id == selected.id {
                            Image(systemName: "checkmark").font(.caption).foregroundStyle(Theme.brand)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line) }
    }

    @ViewBuilder private var articleBody: some View {
        if let article = articles[selected.id] {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, p in
                    Text(p)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            websiteButton
        } else if failed.contains(selected.id) {
            if !selected.summary.isEmpty {
                Text(selected.summary).font(.body).lineSpacing(4).foregroundStyle(Theme.ink)
            }
            Text("De volledige tekst kon niet in de app worden geladen.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            websiteButton
        } else {
            HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 30)
        }
    }

    private var websiteButton: some View {
        Button {
            webPage = selected
        } label: {
            Label("Lees op \(URL(string: selected.url)?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? "de website")",
                  systemImage: "safari")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.top, 6)
    }

    // MARK: - Laden

    private func loadAll() async {
        // Alle bronnen van het verhaal tegelijk ophalen.
        let tasks = story.all.map { item in Task { (item.id, await ArticleReader.fetch(item.url)) } }
        for task in tasks {
            let (id, article) = await task.value
            if let article { articles[id] = article } else { failed.insert(id) }
        }
        guard Summarizer.isAvailable else { return }
        let texts = story.all.map { item in
            (source: item.sourceLabel, text: "\(item.title)\n\(articles[item.id]?.text ?? item.summary)")
        }
        do {
            summary = try await Summarizer.summarize(texts)
        } catch {
            summaryFailed = true
        }
    }
}

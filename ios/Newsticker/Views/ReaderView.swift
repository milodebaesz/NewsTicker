import SwiftUI

// Leesweergave in de app: AI-samenvatting van het verhaal (over alle bronnen),
// de artikeltekst zonder cookiemuren, en de andere bronnen om naar te wisselen.
struct ReaderView: View {
    let story: StoryClusters.Story

    @Environment(\.dismiss) private var dismiss
    @State private var selected: FeedItem
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
                    // Prettige regellengte, ook op de iPad.
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
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
        // Op de iPad een groot leesvenster in plaats van een klein formulier.
        .presentationSizing(.page)
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

    private var host: String {
        URL(string: selected.url)?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? ""
    }

    // "vandaag 10:27", "gisteren 18:05" of "3 okt 10:27"
    private var publishedText: String {
        let date = selected.publishedAt
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "vandaag \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "gisteren \(time)" }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }

    // Duidelijke bronvermelding bovenaan; tik om het origineel te openen.
    private var meta: some View {
        Button { webPage = selected } label: {
            HStack(spacing: 10) {
                SourceIcon(host: host)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selected.sourceLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(host) · \(publishedText)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                if !selected.topic.isEmpty {
                    Text(selected.topic)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .overlay { Capsule().strokeBorder(Theme.line) }
                }
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Theme.brand)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bron: \(selected.sourceLabel), \(publishedText). Open het origineel.")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Samenvatting door Apple Intelligence", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.brand)
            if let summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("Op basis van \(story.all.map(\.sourceLabel).formatted(.list(type: .and))) · kan fouten bevatten, controleer het origineel")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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

    // Alleen wat de uitgever zelf in de feed meelevert: de volledige tekst als
    // die erin zit, anders de korte inleiding met een duidelijke link.
    @ViewBuilder private var articleBody: some View {
        if let body = selected.body, !body.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(body.enumerated()), id: \.offset) { _, p in
                    Text(p)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        } else if !selected.summary.isEmpty {
            Text(selected.summary)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        websiteButton
    }

    // Altijd onder de tekst: van wie het artikel is, en een weg naar het origineel.
    private var websiteButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SourceIcon(host: host)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dit artikel is van \(selected.sourceLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Oorspronkelijk gepubliceerd op \(host), \(publishedText). Alle rechten bij de uitgever.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                webPage = selected
            } label: {
                Label("\(selected.body == nil ? "Lees het hele artikel" : "Lees het origineel") op \(host.isEmpty ? "de website" : host)",
                      systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.button)
            .controlSize(.large)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line) }
        .padding(.top, 10)
    }

    // MARK: - Laden

    private func loadAll() async {
        guard Summarizer.isAvailable else { return }
        // Samenvatten op basis van wat de feeds zelf geven (geen websitetekst).
        let texts = story.all.map { item in
            (source: item.sourceLabel, text: "\(item.title)\n\((item.body ?? []).joined(separator: "\n").nonEmpty ?? item.summary)")
        }
        do {
            summary = try await Summarizer.summarize(texts)
        } catch {
            summaryFailed = true
        }
    }
}

// Logo van de bron (favicon), met een neutraal icoon als terugval.
private struct SourceIcon: View {
    let host: String

    var body: some View {
        AsyncImage(url: Favicon.url(host: host)) { phase in
            if case .success(let img) = phase {
                img.resizable().scaledToFit()
            } else {
                Image(systemName: "newspaper").foregroundStyle(Theme.brand)
            }
        }
        .frame(width: 28, height: 28)
        .background(Theme.subtle, in: .rect(cornerRadius: 7))
        .clipShape(.rect(cornerRadius: 7))
        .accessibilityHidden(true)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

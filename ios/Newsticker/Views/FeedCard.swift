import SwiftUI

// Bento-ritme voor de telefoon: groot, twee naast elkaar, breed, twee naast elkaar, …
struct BentoFeed: View {
    typealias Story = StoryClusters.Story
    let stories: [Story]
    let open: (Story) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    private enum Row: Identifiable {
        case big(Story), wide(Story), pair([Story])
        var id: String {
            switch self {
            case .big(let i), .wide(let i): i.id
            case .pair(let p): p.map(\.id).joined(separator: "+")
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        var rest = stories[...]
        var step = 0
        while let first = rest.first {
            switch step % 4 {
            case 0: out.append(.big(first)); rest = rest.dropFirst()
            case 2: out.append(.wide(first)); rest = rest.dropFirst()
            default:
                let n = sizeClass == .regular ? 3 : 2
                out.append(.pair(Array(rest.prefix(n)))); rest = rest.dropFirst(n)
            }
            step += 1
        }
        return out
    }

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(rows) { row in
                switch row {
                case .big(let story):
                    FeedCard(story: story, style: .big, open: open).frame(height: sizeClass == .regular ? 360 : 280)
                case .wide(let story):
                    FeedCard(story: story, style: .wide, open: open).frame(height: 130)
                case .pair(let pair):
                    HStack(spacing: 12) {
                        ForEach(pair) { FeedCard(story: $0, style: .small, open: open) }
                        if pair.count < (sizeClass == .regular ? 3 : 2) { Color.clear }
                    }
                    .frame(height: 200)
                }
            }
        }
    }
}

struct FeedCard: View {
    enum Style { case big, small, wide }

    let story: StoryClusters.Story
    let style: Style
    let open: (StoryClusters.Story) -> Void
    private var item: FeedItem { story.lead }
    @Environment(AppStore.self) private var store
    @State private var imageFailed = false

    private var imageURL: URL? {
        imageFailed || item.image.isEmpty ? nil : URL(string: item.image)
    }

    var body: some View {
        Button { open(story) } label: {
            Group {
                if style == .wide {
                    wideLayout
                } else if let imageURL {
                    overlayLayout(imageURL)
                } else {
                    textLayout.background(Theme.card)
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line.opacity(0.7)) }
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            .contentShape(.rect(cornerRadius: 18))
            // Gelezen: blijft staan tot de volgende verversing, maar gedimd.
            .opacity(item.read ? 0.45 : 1)
            .overlay(alignment: .topTrailing) {
                if item.read {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.brand)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Gelezen", systemImage: "checkmark") { story.all.forEach(store.markRead) }
            Button("Verbergen", systemImage: "eye.slash") { story.all.forEach(store.dismiss) }
            if let url = URL(string: item.url) { ShareLink(item: url) }
        } preview: {
            preview
        }
    }

    // Afbeelding vult de tegel, tekst onderin op een verloop.
    private func overlayLayout(_ url: URL) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.overlay { image(url) }.clipped()
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.4), .black.opacity(0.05)],
                           startPoint: .bottom, endPoint: .top)
            VStack(alignment: .leading, spacing: 6) {
                meta(onImage: true)
                Text(item.title)
                    .font(style == .big ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(style == .big ? 4 : 3)
                if style == .big && !item.summary.isEmpty {
                    Text(item.summary).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                }
            }
            .padding(14)
        }
    }

    // In een overlay, zodat scaledToFill de tegel niet oprekt.
    private func image(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            case .failure: Color.clear.onAppear { imageFailed = true }
            default: Theme.subtle
            }
        }
    }

    private var textLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            meta(onImage: false)
            Text(item.title)
                .font(style == .big ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(style == .big ? 4 : 3)
            if !item.summary.isEmpty {
                Text(item.summary).font(.footnote).foregroundStyle(Theme.muted).lineLimit(style == .big ? 4 : 3)
            }
            Spacer(minLength: 0)
            if !item.reason.isEmpty {
                Text(item.reason).font(.caption2.italic()).foregroundStyle(Theme.muted.opacity(0.8)).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            if let imageURL {
                Theme.subtle.overlay { image(imageURL) }.frame(width: 120).clipped()
            }
            VStack(alignment: .leading, spacing: 6) {
                meta(onImage: false)
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.card)
    }

    private func meta(onImage: Bool) -> some View {
        HStack(spacing: 6) {
            Text(item.sourceLabel).fontWeight(.semibold).foregroundStyle(onImage ? .white : Theme.brand)
            if !story.others.isEmpty {
                // Zelfde verhaal bij meer bronnen.
                Label("+\(story.others.count)", systemImage: "rectangle.stack.fill")
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(onImage ? .white : Theme.brand)
                    .background(onImage ? .white.opacity(0.2) : Theme.brand.opacity(0.1), in: .capsule)
                    .accessibilityLabel("Ook bij \(story.others.map(\.sourceLabel).formatted(.list(type: .and)))")
            }
            if style != .small || story.others.isEmpty {
                Text("· \(item.publishedAt.timeAgo)")
            }
            if !item.topic.isEmpty && style != .small {
                Text(item.topic)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(onImage ? .white.opacity(0.15) : .clear, in: .capsule)
                    .overlay { if !onImage { Capsule().strokeBorder(Theme.line) } }
            }
            Spacer(minLength: 0)
            if let r = item.relevance {
                Text("\(r)")
                    .fontWeight(.medium)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .foregroundStyle(r >= 70 ? .black : (onImage ? .white : Theme.ink))
                    .background(r >= 70 ? Theme.accent : (onImage ? .white.opacity(0.2) : Theme.subtle), in: .capsule)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .foregroundStyle(onImage ? .white.opacity(0.8) : Theme.muted)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL {
                Theme.subtle.overlay { image(imageURL) }.frame(height: 180).clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(item.sourceLabel) · \(item.publishedAt.timeAgo)").font(.caption).foregroundStyle(Theme.brand)
                Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !item.reason.isEmpty { Text(item.reason).font(.caption.italic()).foregroundStyle(.secondary) }
            }
            .padding(14)
        }
        .frame(width: 340)
    }
}

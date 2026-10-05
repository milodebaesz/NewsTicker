import SwiftUI

// Bento-ritme voor de telefoon: groot, twee naast elkaar, breed, twee naast elkaar, …
struct BentoFeed: View {
    typealias Story = StoryClusters.Story
    let stories: [Story]
    let open: (Story) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    // Hoogtes groeien mee met de tekstgrootte uit iOS-instellingen.
    @ScaledMetric(relativeTo: .body) private var bigHeight: CGFloat = 280
    @ScaledMetric(relativeTo: .body) private var pairHeight: CGFloat = 200
    @ScaledMetric(relativeTo: .body) private var wideHeight: CGFloat = 130

    private enum Row: Identifiable {
        case big(Story), wide(Story), pair([Story]), list(Story)
        var id: String {
            switch self {
            case .big(let i), .wide(let i), .list(let i): i.id
            case .pair(let p): p.map(\.id).joined(separator: "+")
            }
        }
    }

    private var rows: [Row] {
        // Heel grote tekst: één kaart per rij, zo hoog als de tekst nodig heeft.
        if typeSize.isAccessibilitySize { return stories.map(Row.list) }
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

    // Bewust geen eigen LazyVStack: de rijen worden direct onderdeel van de
    // lazy lijst in ContentView. Een lazy lijst in een lazy lijst schat de
    // hoogte verkeerd en liet de feed bij terugkeren naar onderen springen.
    var body: some View {
        ForEach(rows) { row in
            Group {
                switch row {
                case .big(let story):
                    FeedCard(story: story, style: .big, open: open)
                        .frame(height: sizeClass == .regular ? bigHeight * 360 / 280 : bigHeight)
                case .wide(let story):
                    FeedCard(story: story, style: .wide, open: open).frame(height: wideHeight)
                case .list(let story):
                    FeedCard(story: story, style: .list, open: open)
                case .pair(let pair):
                    HStack(spacing: 12) {
                        ForEach(pair) { FeedCard(story: $0, style: .small, open: open) }
                        if pair.count < (sizeClass == .regular ? 3 : 2) { Color.clear }
                    }
                    .frame(height: pairHeight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

struct FeedCard: View {
    enum Style { case big, small, wide, list }

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
                } else if style == .list {
                    listLayout
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
            Section {
                Button("Meer hiervan", systemImage: "hand.thumbsup") { store.learn(.more, from: story) }
                Button("Minder hiervan", systemImage: "hand.thumbsdown") { store.learn(.less, from: story) }
            }
            Button("Gelezen", systemImage: "checkmark") { story.all.forEach(store.markRead) }
            Button("Verbergen", systemImage: "eye.slash") { store.learn(.dismissed, from: story) }
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

    // Voor heel grote tekst: afbeelding boven, tekst eronder, geen vaste hoogte.
    private var listLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL {
                Theme.subtle.overlay { image(imageURL) }.frame(height: 160).clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                meta(onImage: false)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.card)
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
        }
        .font(.caption2)
        .lineLimit(style == .list ? 2 : 1)
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

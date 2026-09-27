import SafariServices
import SwiftUI

// Doorlopende headline-band. De rij wordt verdubbeld zodat hij naadloos loopt;
// bij "Verminder beweging" wordt het een gewone horizontale scroller.
struct TickerView: View {
    let items: [FeedItem]
    let onTap: (FeedItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowWidth: CGFloat = 0
    @State private var start = Date.now

    private let speed: CGFloat = 35 // punten per seconde

    var body: some View {
        Group {
            if reduceMotion {
                ScrollView(.horizontal, showsIndicators: false) { row }
            } else {
                TimelineView(.animation) { ctx in
                    let t = CGFloat(ctx.date.timeIntervalSince(start))
                    let offset = rowWidth > 0 ? -(t * speed).truncatingRemainder(dividingBy: rowWidth) : 0
                    HStack(spacing: 0) {
                        row.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
                        row
                    }
                    .fixedSize()
                    .offset(x: offset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipped()
            }
        }
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 0.5) }
    }

    private var row: some View {
        HStack(spacing: 28) {
            ForEach(items) { it in
                Button { onTap(it) } label: {
                    HStack(spacing: 6) {
                        Text("▸").foregroundStyle(Theme.accent)
                        Text(it.sourceLabel).fontWeight(.semibold).foregroundStyle(Theme.brand)
                        Text(it.title).foregroundStyle(Theme.ink)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

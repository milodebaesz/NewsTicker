import SwiftUI
import WidgetKit

// Weergave van de widget; gedeeld met de app voor een voorbeeld (alleen Debug).

// MARK: - Weergave

enum WTheme {
    static let brand = dynamic(light: 0x2C4F87, dark: 0x8CA7CC)
    static let accent = Color(uiColor: UIColor(widgetHex: 0xF59E0B))
    static let ink = dynamic(light: 0x1B2A44, dark: 0xF1F4FA)
    static let muted = dynamic(light: 0x3B63A0, dark: 0x8CA7CC)
    static let canvas = dynamic(light: 0xFFFFFF, dark: 0x1B2A44)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(widgetHex: dark) : UIColor(widgetHex: light) })
    }
}

private extension UIColor {
    convenience init(widgetHex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private func image(_ story: WidgetSnapshot.Story) -> UIImage? {
    guard let file = story.imageFile, let dir = WidgetSnapshot.directory else { return nil }
    return UIImage(contentsOfFile: dir.appending(path: file).path)
}

private func ago(_ date: Date) -> String {
    let min = Int(max(0, Date.now.timeIntervalSince(date)) / 60)
    if min < 1 { return "zojuist" }
    if min < 60 { return "\(min) min" }
    if min < 24 * 60 { return "\(min / 60) u" }
    return "\(min / 1440) d"
}

private struct SourceLine: View {
    let story: WidgetSnapshot.Story
    var onImage = false

    var body: some View {
        HStack(spacing: 4) {
            Text(story.source).fontWeight(.semibold)
                .foregroundStyle(onImage ? .white : WTheme.brand)
            if story.otherSources > 0 {
                Text("+\(story.otherSources)").fontWeight(.semibold)
                    .foregroundStyle(onImage ? .white.opacity(0.85) : WTheme.brand.opacity(0.8))
            }
            Text("· \(ago(story.publishedAt))")
                .foregroundStyle(onImage ? .white.opacity(0.8) : WTheme.muted)
        }
        .font(.caption2)
        .lineLimit(1)
    }
}

/// Topverhaal met de foto als achtergrond (klein formaat en bovenaan groot).
private struct HeroView: View {
    let story: WidgetSnapshot.Story
    var titleFont: Font = .subheadline.weight(.semibold)
    var titleLines = 4

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let uiImage = image(story) {
                Color.black.overlay { Image(uiImage: uiImage).resizable().scaledToFill() }.clipped()
                LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                               startPoint: .bottom, endPoint: .top)
            }
            VStack(alignment: .leading, spacing: 4) {
                SourceLine(story: story, onImage: image(story) != nil)
                Text(story.title)
                    .font(titleFont)
                    .foregroundStyle(image(story) != nil ? .white : WTheme.ink)
                    .lineLimit(titleLines)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
        }
    }
}

private struct HeadlineRow: View {
    let story: WidgetSnapshot.Story
    var titleLines = 2

    var body: some View {
        Link(destination: WidgetSnapshot.link(for: story.id)) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("▸").font(.caption).foregroundStyle(WTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(story.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WTheme.ink)
                        .lineLimit(titleLines)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    SourceLine(story: story)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct Header: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "newspaper.fill").foregroundStyle(WTheme.brand)
            Text("Newsticker").fontWeight(.bold).foregroundStyle(WTheme.ink)
            Spacer()
            Text(date, style: .time).foregroundStyle(WTheme.muted)
        }
        .font(.caption)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "newspaper").font(.title2).foregroundStyle(WTheme.brand)
            Text("Open Newsticker om je nieuws op te halen.")
                .font(.footnote)
                .foregroundStyle(WTheme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct NewstickerWidgetView: View {
    let family: WidgetFamily
    let snapshot: WidgetSnapshot

    private var stories: [WidgetSnapshot.Story] { snapshot.stories }

    var body: some View {
        content
            .containerBackground(for: .widget) { WTheme.canvas }
    }

    @ViewBuilder private var content: some View {
        if let top = stories.first {
            switch family {
            case .systemSmall:
                HeroView(story: top)
                    .widgetURL(WidgetSnapshot.link(for: top.id))
            case .systemMedium:
                VStack(alignment: .leading, spacing: 7) {
                    Header(date: snapshot.updatedAt)
                    ForEach(stories.prefix(3)) { HeadlineRow(story: $0, titleLines: 1) }
                    Spacer(minLength: 0)
                }
                .padding(14)
            case .systemLarge, .systemExtraLarge:
                VStack(alignment: .leading, spacing: 0) {
                    Link(destination: WidgetSnapshot.link(for: top.id)) {
                        HeroView(story: top, titleFont: .headline, titleLines: 3)
                            .frame(height: 130)
                            .clipped()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(stories.dropFirst().prefix(4)) { HeadlineRow(story: $0) }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(top.source).font(.caption2.weight(.semibold)).widgetAccentable()
                    Text(top.title).font(.caption).lineLimit(2)
                }
                .widgetURL(WidgetSnapshot.link(for: top.id))
            case .accessoryInline:
                Text("\(top.source): \(top.title)")
                    .widgetURL(WidgetSnapshot.link(for: top.id))
            default:
                HeroView(story: top)
            }
        } else {
            EmptyStateView().padding(family == .systemSmall ? 0 : 14)
        }
    }
}

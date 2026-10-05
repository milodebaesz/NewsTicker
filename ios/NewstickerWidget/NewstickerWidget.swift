import SwiftUI
import WidgetKit

// MARK: - Gegevens

struct NewsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NewsProvider: TimelineProvider {
    func placeholder(in context: Context) -> NewsEntry {
        NewsEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NewsEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)
        completion(NewsEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NewsEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot(updatedAt: .now, stories: [])
        // De app ververst de inhoud; dit herberekent alleen de "x min geleden".
        completion(Timeline(entries: [NewsEntry(date: .now, snapshot: snapshot)],
                            policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Widget

private struct EntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NewsEntry
    var body: some View { NewstickerWidgetView(family: family, snapshot: entry.snapshot) }
}

struct NewstickerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NewstickerWidget", provider: NewsProvider()) { entry in
            EntryView(entry: entry)
        }
        .configurationDisplayName("Newsticker")
        .description("De belangrijkste koppen uit je bronnen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct NewstickerWidgetBundle: WidgetBundle {
    var body: some Widget {
        NewstickerWidget()
    }
}

import Foundation
import UIKit
import WidgetKit

// Schrijft de bovenste verhalen naar de gedeelde map voor de widget, met
// verkleinde afbeeldingen (widgets mogen zelf geen afbeeldingen downloaden).
enum WidgetUpdater {
    private static let maxStories = 6
    private static let maxImages = 3 // alleen de verhalen die met foto getoond worden

    static func update(stories: [StoryClusters.Story]) async {
        guard let dir = WidgetSnapshot.directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let top = Array(stories.prefix(maxStories))
        // Oude afbeeldingen opruimen, nieuwe tegelijk ophalen.
        let keep = Set(top.prefix(maxImages).map { "\($0.id).jpg" })
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where file.hasSuffix(".jpg") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: dir.appending(path: file))
        }
        let tasks = top.prefix(maxImages).map { story in
            Task { (story.id, await thumbnail(for: story, in: dir)) }
        }
        var files: [String: String] = [:]
        for task in tasks {
            let (id, file) = await task.value
            if let file { files[id] = file }
        }

        WidgetSnapshot(updatedAt: .now, stories: top.map { story in
            WidgetSnapshot.Story(
                id: story.lead.id,
                title: story.lead.title,
                source: story.lead.sourceLabel,
                otherSources: story.others.count,
                publishedAt: story.lead.publishedAt,
                imageFile: files[story.id]
            )
        }).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func thumbnail(for story: StoryClusters.Story, in dir: URL) async -> String? {
        let file = "\(story.id).jpg"
        let target = dir.appending(path: file)
        if FileManager.default.fileExists(atPath: target.path) { return file }
        guard let urlString = story.all.first(where: { !$0.image.isEmpty })?.image,
              let url = URL(string: urlString),
              let data = try? await HTTP.get(url),
              let image = UIImage(data: data),
              // Klein houden: widgets hebben een strikte geheugenlimiet.
              let small = await image.byPreparingThumbnail(ofSize: fitted(image.size, maxSide: 600)),
              let jpeg = small.jpegData(compressionQuality: 0.75) else { return nil }
        try? jpeg.write(to: target, options: .atomic)
        return file
    }

    private static func fitted(_ size: CGSize, maxSide: CGFloat) -> CGSize {
        let scale = min(1, maxSide / max(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

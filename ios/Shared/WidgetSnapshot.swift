import Foundation

// Wat de widget toont. De app schrijft dit na elke verversing naar de gedeelde
// map van de App Group; de widget leest het alleen (geen eigen netwerkverkeer).
struct WidgetSnapshot: Codable, Sendable {
    struct Story: Codable, Identifiable, Sendable {
        var id: String // id van het hoofdartikel
        var title: String
        var source: String
        var otherSources: Int // aantal extra bronnen voor hetzelfde verhaal
        var publishedAt: Date
        var imageFile: String? // bestandsnaam in de gedeelde map
    }

    var updatedAt: Date
    var stories: [Story]

    static let appGroup = "group.com.mkdebie.newsticker"
    static let urlScheme = "newsticker"

    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Widget", directoryHint: .isDirectory)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = directory?.appending(path: "snapshot.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let dir = Self.directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(self).write(to: dir.appending(path: "snapshot.json"), options: .atomic)
    }

    /// Link die de app opent op dit verhaal.
    static func link(for storyID: String) -> URL {
        URL(string: "\(urlScheme)://story/\(storyID)")!
    }

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(updatedAt: .now, stories: [
            Story(id: "1", title: "Kabinet presenteert plannen voor woningbouw", source: "NOS", otherSources: 2, publishedAt: .now.addingTimeInterval(-1800), imageFile: nil),
            Story(id: "2", title: "Nieuwe generatie zonnepanelen haalt recordrendement", source: "Tweakers", otherSources: 0, publishedAt: .now.addingTimeInterval(-3600), imageFile: nil),
            Story(id: "3", title: "Regionale treinen rijden weer na storing", source: "RTV Utrecht", otherSources: 0, publishedAt: .now.addingTimeInterval(-5400), imageFile: nil),
            Story(id: "4", title: "Onderzoekers ontdekken nieuwe soort kikker", source: "Scientias", otherSources: 0, publishedAt: .now.addingTimeInterval(-7200), imageFile: nil),
            Story(id: "5", title: "Beurzen openen hoger na sterke cijfers", source: "NU.nl", otherSources: 1, publishedAt: .now.addingTimeInterval(-9000), imageFile: nil),
        ])
    }
}

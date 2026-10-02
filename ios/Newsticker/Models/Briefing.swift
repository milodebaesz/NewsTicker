import Foundation

// De ochtendbriefing: de vijf belangrijkste verhalen voor jou, elk met één zin
// uitleg. Wordt bewaard zodat de melding en het scherm dezelfde inhoud tonen.
struct Briefing: Codable, Sendable {
    struct Entry: Codable, Identifiable, Sendable {
        var id: String // id van het hoofdartikel
        var itemIds: [String] // alle artikelen van het verhaal
        var title: String
        var sources: [String]
        var line: String // één zin: waarom dit ertoe doet
        var image: String
    }

    var createdAt: Date
    var entries: [Entry]

    /// Hoort bij vandaag (lokale tijd)?
    var isFromToday: Bool { Calendar.current.isDateInToday(createdAt) }
}

enum BriefingBuilder {
    static let size = 5

    /// Kiest de verhalen: ongelezen, van de afgelopen 24 uur, op relevantie,
    /// met een kleine voorkeur voor nieuws dat meerdere bronnen brengen.
    static func pickStories(from items: [FeedItem], hiddenSources: Set<String>) -> [StoryClusters.Story] {
        let since = Date.now.addingTimeInterval(-24 * 3600)
        let candidates = items
            .filter { !$0.dismissed && !$0.read && $0.publishedAt > since && !hiddenSources.contains($0.sourceLabel) }
            .sorted { a, b in
                let ra = a.relevance ?? 55, rb = b.relevance ?? 55
                return ra != rb ? ra > rb : a.publishedAt > b.publishedAt
            }
        func weight(_ s: StoryClusters.Story) -> Int { (s.lead.relevance ?? 55) + 8 * min(s.others.count, 3) }
        return Array(StoryClusters.group(candidates)
            .filter { (weight($0)) >= 40 } // niet-relevant overslaan
            .sorted { weight($0) > weight($1) }
            .prefix(size))
    }

    static func build(stories: [StoryClusters.Story]) async -> Briefing {
        // Per verhaal één zin; een paar tegelijk. Zonder Apple Intelligence (of als
        // het model weigert) de eerste zin uit de feed.
        let tasks = stories.map { story in
            Task { (story, await Summarizer.oneLine(story)) }
        }
        var entries: [Briefing.Entry] = []
        for task in tasks {
            let (story, line) = await task.value
            entries.append(Briefing.Entry(
                id: story.lead.id,
                itemIds: story.all.map(\.id),
                title: story.lead.title,
                sources: story.all.map(\.sourceLabel),
                line: line ?? firstSentence(of: story.lead.summary),
                image: story.all.first { !$0.image.isEmpty }?.image ?? ""
            ))
        }
        return Briefing(createdAt: .now, entries: entries)
    }

    private static func firstSentence(of text: String) -> String {
        guard let end = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression) else { return text }
        return String(text[..<end.upperBound]).trimmingCharacters(in: .whitespaces)
    }
}

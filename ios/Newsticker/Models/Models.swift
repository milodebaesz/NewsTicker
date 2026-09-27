import Foundation

struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    var id: String // stabiele hash van de url
    var sourceLabel: String
    var title: String
    var summary: String
    var image: String // thumbnail-URL uit de feed, "" als geen
    var topic: String // onderwerp — uit feed-categorie, verfijnd door AI
    var url: String
    var publishedAt: Date
    var relevance: Int? // 0-100, nil = nog niet gescoord
    var reason: String
    var read: Bool
    var dismissed: Bool
    var fetchedAt: Date
}

struct Source: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var url: String
    var label: String
    var enabled: Bool

    // Nederlandse + tech-bronnen als startpunt; pas ze aan in de instellingen.
    static let defaults: [Source] = [
        Source(id: "nos", url: "https://feeds.nos.nl/nosnieuwsalgemeen", label: "NOS", enabled: true),
        Source(id: "nu", url: "https://www.nu.nl/rss/Algemeen", label: "NU.nl", enabled: true),
        Source(id: "tweakers", url: "https://feeds.feedburner.com/tweakers/mixed", label: "Tweakers", enabled: true),
        Source(id: "verge", url: "https://www.theverge.com/rss/index.xml", label: "The Verge", enabled: true),
        Source(id: "hn", url: "https://hnrss.org/frontpage", label: "Hacker News", enabled: true),
    ]
}

struct AppSettings: Codable, Equatable, Sendable {
    var model = "gpt-4o-mini"
    var refreshMinutes = 15
    var minRelevance = 40 // 0-100, items hieronder worden verborgen (alleen als scoring aan staat)
    var scoringEnabled = true
}

struct InterestProfile: Codable, Equatable, Sendable {
    var description =
        "Ik ben softwareontwikkelaar en bouw web-apps met React, Next.js, Supabase en AI/OpenAI. Ik volg tech, startups, AI-ontwikkelingen en de aandelenmarkt. Nederlandse en internationale actualiteit interesseert me ook."
    var keywords = ["AI", "OpenAI", "React", "Next.js", "Supabase", "startups", "beurs", "tech"]
    var mute = ["sport", "showbizz"]
}

extension Date {
    // "zojuist", "12 min", "3 u", "2 d" — zelfde notatie als de extensie.
    var timeAgo: String {
        let min = Int(max(0, Date.now.timeIntervalSince(self)) / 60)
        if min < 1 { return "zojuist" }
        if min < 60 { return "\(min) min" }
        let uur = min / 60
        if uur < 24 { return "\(uur) u" }
        return "\(uur / 24) d"
    }
}

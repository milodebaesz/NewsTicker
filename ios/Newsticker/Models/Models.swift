import Foundation

struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    var id: String // stabiele hash van de url
    var sourceLabel: String
    var title: String
    var summary: String
    /// Volledige tekst als alinea's, alléén als de uitgever die zelf in de
    /// feed meelevert (content:encoded / Atom content). We halen nooit tekst
    /// van de website zelf.
    var body: [String]? = nil
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

/// Hoe het met een bron gaat, voor de lijst bij Bronnen.
struct SourceStatus: Codable, Sendable {
    var lastSuccess: Date?
    var lastCount = 0 // artikelen bij de laatste geslaagde keer
    var failures = 0 // mislukte keren op rij
    var failingSince: Date?
    var lastError = ""

    /// Pas na een paar keer op rij melden: één haperende server is normaal.
    var isBroken: Bool { failures >= 3 }
}

enum AIEngine: String, Codable, CaseIterable, Sendable {
    case apple // Apple Intelligence, op het toestel
    case openAI
    case off

    var label: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .openAI: "OpenAI"
        case .off: "Uit"
        }
    }
}

enum FeedSort: String, Codable, CaseIterable, Sendable {
    case newest // chronologisch
    case forYou // relevantie + wat de app geleerd heeft, met leeftijd meegewogen

    var label: String {
        switch self {
        case .newest: "Nieuwste"
        case .forYou: "Voor jou"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var engine = AIEngine.apple
    var sort = FeedSort.newest
    var model = "gpt-4o-mini"
    var refreshMinutes = 15
    var minRelevance = 40 // 0-100, items hieronder worden verborgen (alleen als scoring aan staat)
    var showTicker = true
    var briefingEnabled = false
    var briefingMinutes = 7 * 60 + 30 // tijd van de ochtendbriefing, minuten na middernacht

    init() {}

    // Ontbrekende velden (oudere versie van de app) vallen terug op de standaard,
    // zodat een update de instellingen niet wist.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        engine = try c.decodeIfPresent(AIEngine.self, forKey: .engine) ?? d.engine
        sort = try c.decodeIfPresent(FeedSort.self, forKey: .sort) ?? d.sort
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
        // De oude schuifregelaar kon elke waarde geven; afronden naar de vaste niveaus.
        let min = try c.decodeIfPresent(Int.self, forKey: .minRelevance) ?? d.minRelevance
        minRelevance = [90, 70, 40, 0].first { min >= $0 } ?? 0
        showTicker = try c.decodeIfPresent(Bool.self, forKey: .showTicker) ?? d.showTicker
        briefingEnabled = try c.decodeIfPresent(Bool.self, forKey: .briefingEnabled) ?? d.briefingEnabled
        briefingMinutes = try c.decodeIfPresent(Int.self, forKey: .briefingMinutes) ?? d.briefingMinutes
    }
}

struct InterestProfile: Codable, Equatable, Sendable {
    // Nieuwe gebruikers beginnen leeg en kiezen bij de eerste start.
    var description = ""
    var keywords: [String] = []
    var mute: [String] = []

    /// Het vroegere standaardprofiel; blijft staan voor wie de app al gebruikte.
    static let legacy = InterestProfile(
        description: "Ik ben softwareontwikkelaar en bouw web-apps met React, Next.js, Supabase en AI/OpenAI. Ik volg tech, startups, AI-ontwikkelingen en de aandelenmarkt. Nederlandse en internationale actualiteit interesseert me ook.",
        keywords: ["AI", "OpenAI", "React", "Next.js", "Supabase", "startups", "beurs", "tech"],
        mute: ["sport", "showbizz"]
    )
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

import Foundation

// Zoekt feeds op naam of onderwerp via de openbare zoek-API van Feedly
// (geen account of key nodig).
enum FeedSearch {
    static func search(_ query: String) async throws -> [FeedCandidate] {
        var comps = URLComponents(string: "https://cloud.feedly.com/v3/search/feeds")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "count", value: "25"),
            URLQueryItem(name: "locale", value: Locale.current.language.languageCode?.identifier ?? "nl"),
        ]
        let data = try await HTTP.get(comps.url!)

        struct Response: Decodable {
            struct Result: Decodable {
                let feedId: String?
                let title: String?
                let website: String?
                let description: String?
                let subscribers: Int?
                let iconUrl: String?
                let visualUrl: String?
                let language: String?
            }
            let results: [Result]?
        }

        // Feeds in de talen van de gebruiker (bv. nl, en) eerst; verder Feedly's volgorde.
        let preferred = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier } + ["nl", "en"]
        func rank(_ r: Response.Result) -> Int {
            guard let lang = r.language?.prefix(2).lowercased() else { return preferred.count }
            return preferred.firstIndex(of: String(lang)) ?? preferred.count + 1
        }
        let results = (try JSONDecoder().decode(Response.self, from: data).results ?? [])
            .enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)

        var seen = Set<String>()
        return results.compactMap { r in
            guard let id = r.feedId, id.hasPrefix("feed/") else { return nil }
            // iOS blokkeert gewone http; vrijwel alle sites ondersteunen https.
            let url = String(id.dropFirst(5)).replacingOccurrences(of: "http://", with: "https://")
            guard URL(string: url) != nil, seen.insert(url).inserted else { return nil }
            let site = r.website.flatMap { URL(string: $0)?.host(percentEncoded: false) } ?? URL(string: url)?.host(percentEncoded: false) ?? ""
            return FeedCandidate(
                url: url,
                title: HTMLText.strip(r.title ?? site),
                detail: HTMLText.strip(r.description ?? ""),
                site: site.replacingOccurrences(of: "www.", with: ""),
                followers: r.subscribers ?? 0,
                icon: (r.iconUrl ?? r.visualUrl ?? "").replacingOccurrences(of: "http://", with: "https://")
            )
        }
    }

    /// Ziet de invoer eruit als een website of URL (i.p.v. een zoekterm)?
    static func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.contains(" ") && (t.contains("://") || t.range(of: #"^[\w-]+(\.[\w-]+)+(/.*)?$"#, options: .regularExpression) != nil)
    }
}

// Een greep populaire, betrouwbare feeds om met één tik toe te voegen.
enum FeedCatalog {
    struct Category: Identifiable {
        let name: String
        let symbol: String
        let feeds: [FeedCandidate]
        var id: String { name }
    }

    private static func f(_ title: String, _ url: String, _ detail: String) -> FeedCandidate {
        let host = URL(string: url)?.host(percentEncoded: false) ?? ""
        let site = host.replacingOccurrences(of: #"^(www|feeds?|rss)\."#, with: "", options: .regularExpression)
        return FeedCandidate(url: url, title: title, detail: detail, site: site)
    }

    static let categories: [Category] = [
        Category(name: "Nederlands nieuws", symbol: "newspaper", feeds: [
            f("NOS Algemeen", "https://feeds.nos.nl/nosnieuwsalgemeen", "Belangrijkste nieuws van de NOS"),
            f("NOS Binnenland", "https://feeds.nos.nl/nosnieuwsbinnenland", "Nieuws uit Nederland"),
            f("NOS Buitenland", "https://feeds.nos.nl/nosnieuwsbuitenland", "Internationaal nieuws"),
            f("NU.nl", "https://www.nu.nl/rss/Algemeen", "Het laatste nieuws"),
            f("de Volkskrant", "https://www.volkskrant.nl/voorpagina/rss.xml", "Voorpagina"),
            f("Trouw", "https://www.trouw.nl/voorpagina/rss.xml", "Voorpagina"),
            f("NRC", "https://www.nrc.nl/rss/", "Alle artikelen"),
            f("Het Parool", "https://www.parool.nl/voorpagina/rss.xml", "Amsterdams nieuws"),
            f("AD", "https://www.ad.nl/home/rss.xml", "Algemeen Dagblad"),
        ]),
        Category(name: "Tech", symbol: "desktopcomputer", feeds: [
            f("Tweakers", "https://feeds.feedburner.com/tweakers/mixed", "Nieuws, reviews en meer"),
            f("NU.nl Tech", "https://www.nu.nl/rss/Tech", "Technologie bij NU.nl"),
            f("The Verge", "https://www.theverge.com/rss/index.xml", "Tech, wetenschap en cultuur"),
            f("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "Diepgaande technologie"),
            f("TechCrunch", "https://techcrunch.com/feed/", "Startups en tech-bedrijven"),
            f("Wired", "https://www.wired.com/feed/rss", "Technologie en samenleving"),
            f("Engadget", "https://www.engadget.com/rss.xml", "Gadgets en consumententech"),
            f("9to5Mac", "https://9to5mac.com/feed/", "Apple-nieuws"),
            f("Hacker News", "https://hnrss.org/frontpage", "Voorpagina van Hacker News"),
        ]),
        Category(name: "AI", symbol: "sparkles", feeds: [
            f("OpenAI", "https://openai.com/news/rss.xml", "Nieuws van OpenAI"),
            f("Simon Willison", "https://simonwillison.net/atom/everything/", "Blog over LLM's en tooling"),
            f("MIT Technology Review", "https://www.technologyreview.com/feed/", "AI en opkomende technologie"),
        ]),
        Category(name: "Wetenschap", symbol: "atom", feeds: [
            f("Scientias", "https://www.scientias.nl/feed/", "Nederlandstalig wetenschapsnieuws"),
            f("Quanta Magazine", "https://www.quantamagazine.org/feed/", "Wiskunde, natuurkunde, biologie"),
            f("New Scientist", "https://www.newscientist.com/feed/home/", "Wetenschap en technologie"),
            f("NASA", "https://www.nasa.gov/news-release/feed/", "Persberichten van NASA"),
        ]),
        Category(name: "Economie", symbol: "chart.line.uptrend.xyaxis", feeds: [
            f("NOS Economie", "https://feeds.nos.nl/nosnieuwseconomie", "Economisch nieuws"),
            f("CNBC", "https://www.cnbc.com/id/100003114/device/rss/rss.html", "Markten en bedrijven"),
        ]),
        Category(name: "Internationaal", symbol: "globe.europe.africa", feeds: [
            f("BBC News", "https://feeds.bbci.co.uk/news/rss.xml", "Topverhalen"),
            f("BBC World", "https://feeds.bbci.co.uk/news/world/rss.xml", "Wereldnieuws"),
            f("The Guardian", "https://www.theguardian.com/world/rss", "Wereldnieuws"),
            f("Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml", "Alle artikelen"),
            f("The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", "Voorpagina"),
        ]),
        Category(name: "Sport", symbol: "sportscourt", feeds: [
            f("NOS Sport", "https://feeds.nos.nl/nossportalgemeen", "Sportnieuws"),
            f("BBC Sport", "https://feeds.bbci.co.uk/sport/rss.xml", "Internationaal sportnieuws"),
        ]),
    ]
}

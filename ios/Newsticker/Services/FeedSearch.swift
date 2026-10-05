import Foundation

// Bronnen zoeken zonder externe dienst: in de eigen catalogus hieronder, of
// (bij een website-adres) via de feeds die de site zelf publiceert (Discover).
enum FeedSearch {
    /// Ziet de invoer eruit als een website of URL (i.p.v. een zoekterm)?
    static func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.contains(" ") && (t.contains("://") || t.range(of: #"^[\w-]+(\.[\w-]+)+(/.*)?$"#, options: .regularExpression) != nil)
    }
}

// Populaire, betrouwbare feeds om met één tik toe te voegen, per categorie.
// Doorzoekbaar op naam, omschrijving, site, categorie en trefwoorden.
enum FeedCatalog {
    struct Category: Identifiable {
        let name: String
        let symbol: String
        let feeds: [FeedCandidate]
        var id: String { name }
    }

    private static func f(_ title: String, _ url: String, _ detail: String, _ keywords: String = "") -> FeedCandidate {
        let host = URL(string: url)?.host(percentEncoded: false) ?? ""
        let site = host.replacingOccurrences(of: #"^(www|feeds?|rss|newsfeed)\."#, with: "", options: .regularExpression)
        // Extra zoekwoorden: "f1" vindt Formule 1, "apple" vindt 9to5Mac.
        let tags = keywords.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return FeedCandidate(url: url, title: title, detail: detail, site: site, keywords: tags)
    }

    static let categories: [Category] = [
        Category(name: "Nederlands nieuws", symbol: "newspaper", feeds: [
            f("NOS", "https://feeds.nos.nl/nosnieuwsalgemeen", "Belangrijkste nieuws van de NOS", "algemeen, journaal"),
            f("NOS Binnenland", "https://feeds.nos.nl/nosnieuwsbinnenland", "Nieuws uit Nederland"),
            f("NOS Buitenland", "https://feeds.nos.nl/nosnieuwsbuitenland", "Internationaal nieuws", "wereld"),
            f("NOS Politiek", "https://feeds.nos.nl/nosnieuwspolitiek", "Den Haag en verkiezingen", "politiek, kabinet, tweede kamer"),
            f("NU.nl", "https://www.nu.nl/rss/Algemeen", "Het laatste nieuws", "algemeen"),
            f("RTL Nieuws", "https://www.rtlnieuws.nl/rss.xml", "Nieuws van RTL"),
            f("de Volkskrant", "https://www.volkskrant.nl/voorpagina/rss.xml", "Voorpagina", "krant"),
            f("NRC", "https://www.nrc.nl/rss/", "Alle artikelen", "krant"),
            f("Trouw", "https://www.trouw.nl/voorpagina/rss.xml", "Voorpagina", "krant"),
            f("AD", "https://www.ad.nl/home/rss.xml", "Algemeen Dagblad", "krant"),
            f("Het Parool", "https://www.parool.nl/voorpagina/rss.xml", "Amsterdams nieuws", "amsterdam, krant"),
            f("De Telegraaf", "https://www.telegraaf.nl/rss", "Nieuws van De Telegraaf", "krant"),
            f("Follow the Money", "https://www.ftm.nl/feed", "Onderzoeksjournalistiek", "onderzoek, journalistiek"),
        ]),
        Category(name: "Vlaams nieuws", symbol: "newspaper.fill", feeds: [
            f("VRT NWS", "https://www.vrt.be/vrtnws/nl.rss.articles.xml", "Nieuws van de VRT", "belgië, vlaanderen"),
            f("De Morgen", "https://www.demorgen.be/rss.xml", "Nieuws", "belgië, krant"),
        ]),
        Category(name: "Tech", symbol: "desktopcomputer", feeds: [
            f("Tweakers", "https://feeds.feedburner.com/tweakers/mixed", "Nieuws, reviews en meer", "hardware, gadgets"),
            f("NOS Tech", "https://feeds.nos.nl/nosnieuwstech", "Technologie bij de NOS"),
            f("NU.nl Tech", "https://www.nu.nl/rss/Tech", "Technologie bij NU.nl"),
            f("iCulture", "https://www.iculture.nl/feed/", "Apple-nieuws in het Nederlands", "apple, iphone, mac"),
            f("Androidplanet", "https://www.androidplanet.nl/feed/", "Android-nieuws in het Nederlands", "android, google, samsung"),
            f("The Verge", "https://www.theverge.com/rss/index.xml", "Tech, wetenschap en cultuur"),
            f("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "Diepgaande technologie"),
            f("TechCrunch", "https://techcrunch.com/feed/", "Startups en tech-bedrijven", "startups, venture capital"),
            f("Wired", "https://www.wired.com/feed/rss", "Technologie en samenleving"),
            f("Engadget", "https://www.engadget.com/rss.xml", "Gadgets en consumententech", "gadgets"),
            f("9to5Mac", "https://9to5mac.com/feed/", "Apple-nieuws", "apple, iphone, mac"),
            f("MacRumors", "https://feeds.macrumors.com/MacRumors-All", "Apple-geruchten en -nieuws", "apple, iphone, mac"),
            f("Daring Fireball", "https://daringfireball.net/feeds/main", "John Gruber over Apple", "apple"),
            f("The Register", "https://www.theregister.com/headlines.atom", "IT-nieuws met een knipoog", "it, enterprise"),
            f("Hacker News", "https://hnrss.org/frontpage", "Voorpagina van Hacker News", "programmeren, startups, developers"),
        ]),
        Category(name: "AI", symbol: "sparkles", feeds: [
            f("OpenAI", "https://openai.com/news/rss.xml", "Nieuws van OpenAI", "chatgpt, ai"),
            f("Google AI", "https://blog.google/technology/ai/rss/", "AI-nieuws van Google", "gemini, ai"),
            f("Hugging Face", "https://huggingface.co/blog/feed.xml", "Blog over open AI-modellen", "machine learning, open source"),
            f("Simon Willison", "https://simonwillison.net/atom/everything/", "Blog over LLM's en tooling", "llm, ai"),
            f("MIT Technology Review", "https://www.technologyreview.com/feed/", "AI en opkomende technologie"),
        ]),
        Category(name: "Wetenschap", symbol: "atom", feeds: [
            f("Scientias", "https://www.scientias.nl/feed/", "Nederlandstalig wetenschapsnieuws", "ruimtevaart, ruimte, natuur"),
            f("NU.nl Wetenschap", "https://www.nu.nl/rss/Wetenschap", "Wetenschap bij NU.nl"),
            f("Quanta Magazine", "https://www.quantamagazine.org/feed/", "Wiskunde, natuurkunde, biologie", "wiskunde, natuurkunde"),
            f("ScienceDaily", "https://www.sciencedaily.com/rss/all.xml", "Nieuwste onderzoek"),
            f("Nature", "https://www.nature.com/nature.rss", "Wetenschappelijk tijdschrift", "onderzoek"),
        ]),
        Category(name: "Klimaat", symbol: "leaf", feeds: [
            f("The Guardian Environment", "https://www.theguardian.com/environment/rss", "Klimaat en milieu", "klimaat, milieu, duurzaamheid"),
            f("Carbon Brief", "https://www.carbonbrief.org/feed/", "Klimaatwetenschap en -beleid", "klimaat, energie"),
        ]),
        Category(name: "Economie", symbol: "chart.line.uptrend.xyaxis", feeds: [
            f("NOS Economie", "https://feeds.nos.nl/nosnieuwseconomie", "Economisch nieuws", "financieel"),
            f("NU.nl Economie", "https://www.nu.nl/rss/Economie", "Economie bij NU.nl", "financieel"),
            f("CNBC", "https://www.cnbc.com/id/100003114/device/rss/rss.html", "Markten en bedrijven", "beurs, aandelen, markten"),
            f("MarketWatch", "https://feeds.marketwatch.com/marketwatch/topstories/", "Beurs en financiën", "beurs, aandelen, beleggen"),
            f("Financial Times", "https://www.ft.com/rss/home", "Internationaal financieel nieuws (deels betaald)", "financieel, beurs"),
        ]),
        Category(name: "Internationaal", symbol: "globe.europe.africa", feeds: [
            f("BBC News", "https://feeds.bbci.co.uk/news/rss.xml", "Topverhalen", "engels, uk"),
            f("BBC World", "https://feeds.bbci.co.uk/news/world/rss.xml", "Wereldnieuws", "engels"),
            f("The Guardian", "https://www.theguardian.com/world/rss", "Wereldnieuws", "engels, uk"),
            f("The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", "Voorpagina (deels betaald)", "engels, vs, amerika"),
            f("NPR", "https://feeds.npr.org/1001/rss.xml", "Nieuws uit de VS", "engels, vs, amerika"),
            f("Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml", "Alle artikelen", "engels, midden-oosten"),
            f("DW", "https://rss.dw.com/rdf/rss-en-all", "Deutsche Welle in het Engels", "engels, europa, duitsland"),
            f("The Atlantic", "https://www.theatlantic.com/feed/all/", "Achtergronden en essays", "engels, achtergrond"),
        ]),
        Category(name: "Duits nieuws", symbol: "text.bubble", feeds: [
            f("tagesschau", "https://www.tagesschau.de/xml/rss2/", "Nachrichten der ARD", "duitsland, deutsch"),
            f("DER SPIEGEL", "https://www.spiegel.de/schlagzeilen/index.rss", "Schlagzeilen", "duitsland, deutsch"),
            f("ZEIT ONLINE", "https://newsfeed.zeit.de/index", "Nachrichten", "duitsland, deutsch"),
            f("FAZ", "https://www.faz.net/rss/aktuell/", "Frankfurter Allgemeine", "duitsland, deutsch"),
            f("heise online", "https://www.heise.de/rss/heise-atom.xml", "IT-Nachrichten", "duitsland, deutsch, tech"),
        ]),
        Category(name: "Sport", symbol: "sportscourt", feeds: [
            f("NOS Sport", "https://feeds.nos.nl/nossportalgemeen", "Sportnieuws"),
            f("NOS Voetbal", "https://feeds.nos.nl/nosvoetbal", "Voetbalnieuws", "voetbal, eredivisie"),
            f("NU.nl Sport", "https://www.nu.nl/rss/Sport", "Sport bij NU.nl"),
            f("Formule 1", "https://www.formula1.com/en/latest/all.xml", "Officieel F1-nieuws (Engels)", "f1, formule 1, verstappen, racing, autosport"),
            f("BBC Sport", "https://feeds.bbci.co.uk/sport/rss.xml", "Internationaal sportnieuws", "engels"),
        ]),
        Category(name: "Cultuur & media", symbol: "theatermasks", feeds: [
            f("NOS Cultuur & Media", "https://feeds.nos.nl/nosnieuwscultuurenmedia", "Kunst, film, muziek en media", "film, muziek, kunst"),
            f("Pitchfork", "https://pitchfork.com/rss/news/", "Muzieknieuws (Engels)", "muziek"),
            f("Variety", "https://variety.com/feed/", "Film en tv (Engels)", "film, tv, series, hollywood"),
        ]),
        Category(name: "Games", symbol: "gamecontroller", feeds: [
            f("Polygon", "https://www.polygon.com/rss/index.xml", "Games en entertainment", "gaming, games"),
            f("Eurogamer", "https://www.eurogamer.net/feed", "Gamenieuws en reviews", "gaming, games"),
        ]),
    ]

    /// Alle feeds, zonder dubbele.
    static var all: [FeedCandidate] {
        var seen = Set<String>()
        return categories.flatMap(\.feeds).filter { seen.insert($0.url).inserted }
    }

    /// Zoekt in de catalogus. Elk woord van de zoekopdracht moet ergens
    /// voorkomen; treffers in de naam komen eerst.
    static func search(_ query: String) -> [FeedCandidate] {
        let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var scored: [(FeedCandidate, Int)] = []
        for cat in categories {
            for feed in cat.feeds {
                let name = feed.title.lowercased()
                let hay = [name, feed.detail.lowercased(), feed.site, cat.name.lowercased(),
                           feed.keywords.joined(separator: " ")].joined(separator: " ")
                guard words.allSatisfy(hay.contains) else { continue }
                let score = words.allSatisfy(name.contains) ? 2 : (words.contains(where: feed.keywords.contains) ? 1 : 0)
                scored.append((feed, score))
            }
        }
        var seen = Set<String>()
        return scored
            .sorted { $0.1 > $1.1 }
            .map(\.0)
            .filter { seen.insert($0.url).inserted }
    }
}

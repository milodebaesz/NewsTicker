import Foundation

// RSS 2.0 / RDF / Atom-parser op basis van Foundation's XMLParser.
enum RSS {
    static func fetch(_ source: Source) async throws -> [FeedItem] {
        guard let url = URL(string: source.url) else { throw FetchError.badURL }
        let data = try await HTTP.get(url)
        return parse(data, source: source)
    }

    static func parse(_ data: Data, source: Source) -> [FeedItem] {
        let delegate = FeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        let now = Date.now
        return delegate.entries.compactMap { $0.toItem(source: source, now: now) }
    }

    // Zelfde hash als de extensie, zodat id's overeenkomen.
    static func hashId(_ s: String) -> String {
        var h: Int32 = 0
        for c in s.utf16 { h = h &* 31 &+ Int32(c) }
        return "i" + String(UInt32(bitPattern: h), radix: 36)
    }
}

private struct RawEntry {
    var fields: [String: String] = [:]
    var links: [(rel: String, href: String)] = []
    var categories: [String] = []
    var media: [(url: String, medium: String, type: String)] = []
    var enclosures: [(url: String, type: String)] = []
    var isAtom = false

    func field(_ names: String...) -> String {
        for n in names { if let v = fields[n], !v.isEmpty { return v } }
        return ""
    }

    func toItem(source: Source, now: Date) -> FeedItem? {
        let link: String
        if isAtom {
            let alt = links.first { $0.rel == "alternate" } ?? links.first
            link = alt?.href ?? ""
        } else {
            link = field("link").isEmpty ? (links.first?.href ?? "") : field("link")
        }
        let title = HTMLText.strip(field("title"))
        guard !link.isEmpty, !title.isEmpty else { return nil }

        let rawHtml = isAtom ? field("content", "summary") : field("content:encoded", "description")
        let summarySource = isAtom ? field("summary") : field("description")
        let dateRaw = isAtom ? field("published", "updated") : field("pubDate", "dc:date")

        return FeedItem(
            id: RSS.hashId(link),
            sourceLabel: source.label,
            title: title,
            summary: String(Self.dropLinkMeta(HTMLText.strip(summarySource.isEmpty ? rawHtml : summarySource)).prefix(400)),
            image: pickImage(html: rawHtml),
            topic: firstTopic(),
            url: link,
            publishedAt: FeedDate.parse(dateRaw) ?? now,
            relevance: nil,
            reason: "",
            read: false,
            dismissed: false,
            fetchedAt: now
        )
    }

    // Aggregators als hnrss zetten alleen metadata in de beschrijving
    // ("Article URL: … Comments URL: … Points: 4 # Comments: 2"); dat is geen samenvatting.
    private static func dropLinkMeta(_ s: String) -> String {
        s.replacingOccurrences(
            of: #"(Article URL|Comments URL|Link URL):\s*\S+|Points:\s*\d+|#\s*Comments:\s*\d+"#,
            with: " ", options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Eerste categorie, opgeschoond tot een leesbaar onderwerp.
    private func firstTopic() -> String {
        for raw in categories {
            let first = (raw.split(separator: "/").first.map(String.init) ?? "")
                .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !first.isEmpty { return first.prefix(1).uppercased() + first.dropFirst() }
        }
        return ""
    }

    // Probeert een afbeelding te vinden via de gangbare RSS/Atom-velden,
    // anders de eerste <img> uit de HTML-inhoud.
    private func pickImage(html: String) -> String {
        for e in enclosures where e.type.hasPrefix("image") || Self.isImageURL(e.url) {
            return e.url
        }
        for m in media where m.medium == "image" || m.type.hasPrefix("image") || Self.isImageURL(m.url) || m.medium.isEmpty {
            return m.url
        }
        return Regex.firstGroup(#"<img[^>]+src=["']([^"']+)["']"#, in: html) ?? ""
    }

    private static func isImageURL(_ s: String) -> Bool {
        s.range(of: #"\.(jpe?g|png|webp|gif|avif)(\?|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    var entries: [RawEntry] = []
    private var current: RawEntry?
    private var depth = 0 // diepte binnen het huidige item
    private var textStack: [String] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attr: [String: String]) {
        if current == nil {
            if name == "item" || name == "entry" {
                current = RawEntry(isAtom: name == "entry")
                depth = 0
                textStack = []
            }
            return
        }
        depth += 1
        textStack.append("")
        switch name {
        case "enclosure":
            if let u = attr["url"] { current?.enclosures.append((u, attr["type"] ?? "")) }
        case "media:content", "media:thumbnail":
            if let u = attr["url"] { current?.media.append((u, attr["medium"] ?? "", attr["type"] ?? "")) }
        case "link":
            if let href = attr["href"] { current?.links.append((attr["rel"] ?? "alternate", href)) }
        case "category":
            if let term = attr["term"] ?? attr["label"] { current?.categories.append(term) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard current != nil, !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += string
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        guard current != nil, !textStack.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
        textStack[textStack.count - 1] += s
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        if depth == 0 {
            if let c = current { entries.append(c) }
            current = nil
            return
        }
        let text = (textStack.popLast() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Alleen directe kinderen van het item tellen als veld.
        if depth == 1 {
            if name == "category" {
                if !text.isEmpty { current?.categories.append(text) }
            } else if current?.fields[name] == nil || current?.fields[name]?.isEmpty == true {
                current?.fields[name] = text
            }
        } else if !textStack.isEmpty {
            // XHTML-inhoud in Atom: tekst van kinderen doorgeven aan de ouder.
            textStack[textStack.count - 1] += text
        }
        depth -= 1
    }
}

enum FeedDate {
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let formatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm Z", "dd MMM yyyy HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd",
    ].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let d = isoFrac.date(from: s) ?? iso.date(from: s) { return d }
        for f in formatters { if let d = f.date(from: s) { return d } }
        return nil
    }
}

enum HTMLText {
    static func strip(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return decodeEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "euro": "€", "eacute": "é", "euml": "ë", "iuml": "ï", "ouml": "ö", "uuml": "ü",
    ]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = String(after[..<semi])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
                } else {
                    decoded = named[name.lowercased()]
                }
                if let decoded {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }
}

enum Regex {
    static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }
}

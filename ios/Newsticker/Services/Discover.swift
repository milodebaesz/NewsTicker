import Foundation

struct FeedCandidate: Identifiable, Hashable, Sendable {
    var url: String
    var title: String
    var id: String { url }
}

// Zoekt RSS/Atom-feeds voor een website-URL: leest <link rel="alternate">-tags
// uit de HTML, en probeert anders een paar gangbare feed-paden.
enum Discover {
    private static let feedTypes: Set<String> = ["application/rss+xml", "application/atom+xml", "application/xml", "text/xml"]
    private static let fallbackPaths = ["/feed", "/rss", "/rss.xml", "/feed.xml", "/atom.xml", "/index.xml"]

    static func feeds(for input: String) async throws -> [FeedCandidate] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized) else { throw FetchError.badURL }

        let (data, res) = try await HTTP.getWithResponse(url)
        let body = String(decoding: data, as: UTF8.self)

        // De ingevoerde URL is zelf al een feed.
        if isFeed(contentType: res.mimeType, body: body) {
            return [FeedCandidate(url: normalized, title: title(of: body) ?? normalized)]
        }

        var candidates: [FeedCandidate] = []
        var seen = Set<String>()
        let linkRe = try NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive)
        for m in linkRe.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let r = Range(m.range, in: body) else { continue }
            let attrs = parseAttrs(String(body[r]))
            guard attrs["rel"]?.lowercased() == "alternate",
                  let type = attrs["type"]?.lowercased(), feedTypes.contains(type),
                  let href = attrs["href"], let abs = URL(string: href, relativeTo: url)?.absoluteString,
                  !seen.contains(abs) else { continue }
            seen.insert(abs)
            candidates.append(FeedCandidate(url: abs, title: attrs["title"].flatMap { $0.isEmpty ? nil : $0 } ?? abs))
        }

        if candidates.isEmpty {
            for path in fallbackPaths {
                guard let guess = URL(string: path, relativeTo: url)?.absoluteURL,
                      let (d, r) = try? await HTTP.getWithResponse(guess) else { continue }
                let b = String(decoding: d, as: UTF8.self)
                if isFeed(contentType: r.mimeType, body: b) {
                    candidates.append(FeedCandidate(url: guess.absoluteString, title: title(of: b) ?? guess.absoluteString))
                }
            }
        }
        return candidates
    }

    /// Titel van een feed of pagina, voor het voorvullen van het label.
    static func title(of body: String) -> String? {
        Regex.firstGroup(#"<title[^>]*>(?:<!\[CDATA\[)?([^<\]]*)"#, in: body)
            .map { HTMLText.strip($0) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func isFeed(contentType: String?, body: String) -> Bool {
        if let ct = contentType?.lowercased(), feedTypes.contains(ct) { return true }
        return String(body.prefix(2000)).range(of: #"<(rss|feed|rdf:rdf)[\s>]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func parseAttrs(_ tag: String) -> [String: String] {
        var attrs: [String: String] = [:]
        guard let re = try? NSRegularExpression(pattern: #"([\w-]+)\s*=\s*"([^"]*)"|([\w-]+)\s*=\s*'([^']*)'"#) else { return attrs }
        for m in re.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            let nameRange = Range(m.range(at: 1), in: tag) ?? Range(m.range(at: 3), in: tag)
            let valueRange = Range(m.range(at: 2), in: tag) ?? Range(m.range(at: 4), in: tag)
            if let nameRange {
                attrs[tag[nameRange].lowercased()] = valueRange.map { String(tag[$0]) } ?? ""
            }
        }
        return attrs
    }
}

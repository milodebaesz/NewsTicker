import Foundation

// Haalt de tekst van een artikel op voor de leesweergave in de app, zodat je
// niet langs cookiemuren en advertenties hoeft. Eerst de gestructureerde
// gegevens (JSON-LD `articleBody`), anders de alinea's uit <article>.
enum ArticleReader {
    struct Article: Sendable {
        var paragraphs: [String]
        var text: String { paragraphs.joined(separator: "\n\n") }
    }

    static func fetch(_ urlString: String) async -> Article? {
        guard let url = URL(string: urlString),
              let (data, response) = try? await HTTP.getWithResponse(url) else { return nil }
        // Doorgestuurd naar een toestemmingspagina: geen artikeltekst.
        if let host = response.url?.host(), host.contains("privacy") || host.contains("consent") { return nil }
        let html = String(decoding: data.prefix(2_000_000), as: UTF8.self)

        let paragraphs = fromJSONLD(html) ?? fromParagraphs(html)
        // Minder dan een paar alinea's is meestal een teaser of een foutpagina.
        guard paragraphs.joined().count >= 400 else { return nil }
        return Article(paragraphs: paragraphs)
    }

    // MARK: - JSON-LD

    private static func fromJSONLD(_ html: String) -> [String]? {
        guard let re = try? NSRegularExpression(
            pattern: #"<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range(at: 1), in: html),
                  let json = try? JSONSerialization.jsonObject(with: Data(html[r].utf8)),
                  let body = findArticleBody(json) else { continue }
            let paragraphs = body
                .components(separatedBy: .newlines)
                .map { HTMLText.strip($0) }
                .filter { $0.count >= 30 }
            if paragraphs.joined().count >= 400 { return paragraphs }
        }
        return nil
    }

    private static func findArticleBody(_ json: Any) -> String? {
        if let dict = json as? [String: Any] {
            if let body = dict["articleBody"] as? String, !body.isEmpty { return body }
            for value in dict.values { if let found = findArticleBody(value) { return found } }
        } else if let array = json as? [Any] {
            for value in array { if let found = findArticleBody(value) { return found } }
        }
        return nil
    }

    // MARK: - Alinea's

    private static let boilerplate = try? NSRegularExpression(
        pattern: #"cookie|abonne|advertent|nieuwsbrief|lees ook|lees meer|deel dit|meld je aan|newsletter|subscribe|sign up|all rights reserved|©"#,
        options: .caseInsensitive)

    private static func fromParagraphs(_ html: String) -> [String] {
        // Binnen <article> zoeken als dat er is, anders in de hele pagina.
        let scope = Regex.firstGroup(#"<article\b[^>]*>(.*)</article>"#, in: html.replacingOccurrences(of: "\n", with: " ")) ?? html
        guard let re = try? NSRegularExpression(pattern: #"<p\b[^>]*>(.*?)</p>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: scope, range: NSRange(scope.startIndex..., in: scope)).compactMap { m in
            guard let r = Range(m.range(at: 1), in: scope) else { return nil }
            let text = HTMLText.strip(String(scope[r]))
            guard text.count >= 60,
                  boilerplate?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil else { return nil }
            return text
        }
    }
}

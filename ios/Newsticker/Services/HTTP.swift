import Foundation

enum FetchError: LocalizedError {
    case badURL
    case http(Int)
    case openAI(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: "Ongeldige URL"
        case .http(let code): "HTTP \(code)"
        case .openAI(let code, let body): "OpenAI-fout (\(code)): \(body.prefix(200))"
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static func get(_ url: URL) async throws -> Data {
        try await getWithResponse(url).0
    }

    static func getWithResponse(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        // Sommige sites weigeren requests zonder browser-achtige user-agent.
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Newsticker/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw FetchError.http(0) }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        return (data, http)
    }
}

// Logo van een site, rechtstreeks bij de site zelf (geen externe icoondienst,
// zodat niemand anders ziet welke bronnen je volgt).
enum Favicon {
    static func url(host: String) -> URL? {
        host.isEmpty ? nil : URL(string: "https://\(host)/favicon.ico")
    }
}

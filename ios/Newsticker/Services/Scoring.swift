import Foundation

struct Score: Sendable {
    var relevance: Int
    var reason: String
    var topic: String
}

enum Scoring {
    // Vaste, nette onderwerpen zodat de filterchips consistent blijven.
    static let topics = ["Tech & AI", "Politiek", "Economie", "Wetenschap", "Gezondheid", "Sport", "Cultuur", "Wereld", "Overig"]

    // Scoort één batch items (max 25) in één OpenAI-call.
    static func scoreBatch(_ items: [FeedItem], key: String, model: String, profile: InterestProfile) async throws -> [String: Score] {
        let batch = Array(items.prefix(25))
        guard !key.isEmpty, !batch.isEmpty else { return [:] }

        let payload = batch.enumerated().map { i, it in
            ["i": "\(i)", "bron": it.sourceLabel, "titel": it.title, "samenvatting": String(it.summary.prefix(200))]
        }
        let payloadJSON = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)

        let system = """
        Je bent een persoonlijke nieuws-curator. Beoordeel hoe relevant elk item is voor deze gebruiker (0-100) en deel het in bij één onderwerp.

        Profiel: \(profile.description)
        Interesses: \(profile.keywords.joined(separator: ", "))
        Niet interessant: \(profile.mute.joined(separator: ", "))

        Kies "topic" uit precies deze lijst: \(topics.joined(separator: ", ")).

        Geef ALLEEN JSON terug in dit formaat:
        {"scores":[{"i":0,"relevance":85,"reason":"korte reden, max 8 woorden","topic":"Tech & AI"}]}
        """

        let body: [String: Any] = [
            "model": model.isEmpty ? "gpt-4o-mini" : model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": payloadJSON],
            ],
        ]

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await HTTP.session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw FetchError.openAI(status, String(decoding: data, as: UTF8.self))
        }

        struct Completion: Decodable {
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            let choices: [Choice]
        }
        struct Parsed: Decodable {
            struct S: Decodable { let i: Int; let relevance: Double?; let reason: String?; let topic: String? }
            let scores: [S]?
        }

        let content = try JSONDecoder().decode(Completion.self, from: data).choices.first?.message.content ?? "{}"
        let parsed = try JSONDecoder().decode(Parsed.self, from: Data(content.utf8))

        var result: [String: Score] = [:]
        for sc in parsed.scores ?? [] {
            guard batch.indices.contains(sc.i) else { continue }
            let it = batch[sc.i]
            let topic = topics.contains(sc.topic ?? "") ? sc.topic! : (it.topic.isEmpty ? "Overig" : it.topic)
            result[it.id] = Score(
                relevance: max(0, min(100, Int((sc.relevance ?? 0).rounded()))),
                reason: String((sc.reason ?? "").prefix(80)),
                topic: topic
            )
        }
        return result
    }
}

import Foundation
import FoundationModels

// Korte samenvatting van een artikel (of van een verhaal over meerdere
// bronnen) met Apple Intelligence, op het toestel.
enum Summarizer {
    // Samenvatten is een tekstbewerking; de permissieve filter laat ook nieuws
    // over geweld of rampen door, wat bij nieuws vaak voorkomt.
    private static let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    static var isAvailable: Bool { AppleScoring.isAvailable }

    /// `texts`: per bron de titel plus (indien bekend) de artikeltekst.
    static func summarize(_ texts: [(source: String, text: String)]) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: """
        Je vat nieuws samen in het Nederlands, zakelijk en neutraal.
        Schrijf maximaal drie korte zinnen: wat er gebeurde, waarom het ertoe doet, en wat er nu volgt.
        Voeg niets toe dat niet in de tekst staat. Geen opsommingstekens, geen inleiding.
        """)
        // Het contextvenster is ~8000 tokens; per bron ruim binnen blijven.
        let budget = max(800, 5_000 / max(1, texts.count))
        let prompt = texts
            .map { "Bron: \($0.source)\n\($0.text.prefix(budget))" }
            .joined(separator: "\n\n---\n\n")
        return try await session.respond(to: "Vat samen:\n\n\(prompt)").content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

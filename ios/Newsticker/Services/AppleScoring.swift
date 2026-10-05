import Foundation
import FoundationModels
import os

private let log = Logger(subsystem: "com.mkdebie.newsticker", category: "AppleScoring")

// Relevantiescore met Apple Intelligence: draait volledig op het toestel,
// gratis en zonder API-key. Het kleine lokale model beoordeelt één artikel per
// keer en op een grove schaal; dat bleek in tests veel betrouwbaarder dan een
// batch met cijfers van 0-100.
enum AppleScoring {
    @Generable
    enum Relevance {
        case zeerRelevant, relevant, beetje, nietRelevant

        var score: Int {
            switch self {
            case .zeerRelevant: 90
            case .relevant: 70
            case .beetje: 40
            case .nietRelevant: 10
            }
        }
    }

    @Generable
    enum Topic {
        case techEnAI, politiek, economie, wetenschap, gezondheid, sport, cultuur, wereld, binnenland, misdaad, overig

        var label: String {
            switch self {
            case .techEnAI: "Tech & AI"
            case .politiek: "Politiek"
            case .economie: "Economie"
            case .wetenschap: "Wetenschap"
            case .gezondheid: "Gezondheid"
            case .sport: "Sport"
            case .cultuur: "Cultuur"
            case .wereld: "Wereld"
            case .binnenland: "Binnenland"
            case .misdaad: "Misdaad"
            case .overig: "Overig"
            }
        }
    }

    @Generable
    struct Judgement {
        @Guide(description: "Waar gaat het artikel over?")
        var topic: Topic
        @Guide(description: "Past het artikel bij de interesses van de gebruiker?")
        var relevance: Relevance
        @Guide(description: "Korte reden in het Nederlands, maximaal 8 woorden")
        var reason: String
    }

    enum Status: Equatable {
        case available
        case unavailable(String)
    }

    static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Dit toestel ondersteunt Apple Intelligence niet.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Zet Apple Intelligence aan in Instellingen › Apple Intelligence en Siri.")
        case .unavailable(.modelNotReady):
            return .unavailable("Het model wordt nog gedownload. Probeer het later opnieuw.")
        case .unavailable:
            return .unavailable("Apple Intelligence is nu niet beschikbaar.")
        }
    }

    static var isAvailable: Bool { status == .available }

    private static let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    private static func instructions(for profile: InterestProfile) -> String {
        """
        Je beoordeelt nieuwsartikelen voor één gebruiker.
        \(profile.description.isEmpty ? "" : "Over de gebruiker: \(profile.description)")
        Interesses: \(profile.keywords.isEmpty ? "algemeen nieuws" : profile.keywords.joined(separator: ", ")).
        Niet interessant: \(profile.mute.isEmpty ? "niets in het bijzonder" : profile.mute.joined(separator: ", ")).
        Algemene Nederlandse en internationale actualiteit is 'beetje' relevant.
        'zeerRelevant' alleen als het artikel echt over een van de interesses gaat.
        """
    }

    enum Outcome: Sendable {
        case scored(Score)
        case refused // geweigerd door de veiligheidsfilter, vaak nieuws over geweld
        case failed(String) // model werkt niet; later opnieuw proberen
    }

    /// Beoordeelt één artikel.
    static func score(_ item: FeedItem, profile: InterestProfile) async -> Outcome {
        let session = LanguageModelSession(model: model, instructions: instructions(for: profile))
        let prompt = "\(item.sourceLabel): \(item.title)\n\(item.summary.prefix(200))"
        do {
            let j = try await session.respond(to: prompt, generating: Judgement.self).content
            return .scored(Score(relevance: j.relevance.score, reason: String(j.reason.prefix(80)), topic: j.topic.label))
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            return .refused
        } catch {
            log.error("Scoren mislukt voor \(item.title, privacy: .public): \(String(describing: error), privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }
}

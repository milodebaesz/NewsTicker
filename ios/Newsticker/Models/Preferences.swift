import Foundation
import NaturalLanguage

// Wat de app leert van wat je leest: een gewicht per bron, onderwerp en woord.
// Bewust simpel en inzichtelijk, zodat je in "Jouw algoritme" kunt zien en
// bijsturen wat er gebeurt. Alles blijft op het toestel.
struct LearnedPreferences: Codable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case source = "bron", topic = "onderwerp", word = "woord"

        var title: String {
            switch self {
            case .source: "Bronnen"
            case .topic: "Onderwerpen"
            case .word: "Woorden"
            }
        }
    }

    enum Signal: Sendable {
        case opened, dismissed, more, less

        var amount: Double {
            switch self {
            case .opened: 1
            case .dismissed: -1
            case .more: 3
            case .less: -3
            }
        }
    }

    /// Sleutels als "bron:NOS", "onderwerp:Politiek", "woord:verstappen".
    var weights: [String: Double] = [:]
    /// Hoe zwaar het geleerde meetelt: 0 = uit, 0.5 licht, 1 normaal, 1.5 sterk.
    var influence = 1.0
    var lastDecay = Date.now

    private static let maxWords = 400
    private static let dailyDecay = 0.97 // na een maand weegt een signaal nog ~40%

    // MARK: - Leren

    mutating func learn(_ signal: Signal, from item: FeedItem) {
        decayIfNeeded()
        let amount = signal.amount
        // Een bron telt maar licht mee: één voetbalbericht wegdrukken mag niet
        // meteen heel NU.nl laten zakken.
        weights[Self.key(.source, item.sourceLabel), default: 0] += amount * 0.3
        if !item.topic.isEmpty { weights[Self.key(.topic, item.topic), default: 0] += amount }
        for term in Self.terms(in: item.title) {
            weights[Self.key(.word, term), default: 0] += amount * 0.5
        }
        prune()
    }

    mutating func remove(_ key: String) { weights[key] = nil }
    mutating func reset() { weights = [:] }

    // MARK: - Toepassen

    /// Bijstelling van de relevantie (ongeveer −20…+20 bij normale invloed).
    func boost(for item: FeedItem) -> Double {
        guard influence > 0, !weights.isEmpty else { return 0 }
        var score = weights[Self.key(.source, item.sourceLabel)] ?? 0
        score += weights[Self.key(.topic, item.topic)] ?? 0
        let words = Self.terms(in: item.title)
        if !words.isEmpty {
            let sum = words.reduce(0) { $0 + (weights[Self.key(.word, $1)] ?? 0) }
            score += sum / Double(words.count).squareRoot()
        }
        return influence * 20 * tanh(score / 6)
    }

    // MARK: - Weergave

    struct Entry: Identifiable, Sendable {
        var key: String
        var kind: Kind
        var label: String
        var weight: Double
        var id: String { key }
    }

    /// De sterkste voorkeuren, positief (`liked`) of negatief. Losse woorden
    /// tonen we pas als ze vaker terugkomen; bronnen, onderwerpen en namen eerder.
    func top(_ liked: Bool, limit: Int = 8) -> [Entry] {
        weights
            .filter { key, value in
                let isPlainWord = key.hasPrefix("\(Kind.word.rawValue):") && key.lowercased() == key && !key.contains(" ")
                let threshold = isPlainWord ? 3.0 : 0.9
                return liked ? value >= threshold : value <= -threshold
            }
            .sorted { liked ? $0.value > $1.value : $0.value < $1.value }
            .prefix(limit)
            .compactMap(Self.entry)
    }

    var isEmpty: Bool { top(true, limit: 1).isEmpty && top(false, limit: 1).isEmpty }

    // MARK: - Intern

    static func key(_ kind: Kind, _ value: String) -> String { "\(kind.rawValue):\(value)" }

    /// Woorden uit een kop die iets over je smaak zeggen: namen en zelfstandige
    /// naamwoorden. Voor Engels via NaturalLanguage; Nederlands wordt daar niet
    /// ondersteund, dus daar namen (reeksen met hoofdletter) en lange woorden
    /// (vaak samenstellingen als "fraudezaak").
    static func terms(in title: String) -> Set<String> {
        if NLLanguageRecognizer.dominantLanguage(for: title) == .english {
            return englishTerms(title)
        }
        var terms = Set<String>()
        for segment in title.split(whereSeparator: { ":.,;!?|()–—\"'‘’“”".contains($0) }) {
            let tokens = segment.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            var index = 0
            while index < tokens.count {
                // Reeks woorden met hoofdletter = naam ("Manchester City", "Sierra Leone").
                var end = index
                while end < tokens.count, tokens[end].first?.isUppercase == true { end += 1 }
                let run = tokens[index..<end]
                if run.count >= 2 || (run.count == 1 && index > 0) {
                    terms.insert(run.joined(separator: " "))
                    index = end
                    continue
                }
                let word = tokens[index].lowercased()
                if word.count >= 7, !StoryClusters.stopwords.contains(word), !word.allSatisfy(\.isNumber) {
                    terms.insert(word)
                }
                index += 1
            }
        }
        return terms
    }

    private static func englishTerms(_ title: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = title
        var terms = Set<String>()
        tagger.enumerateTags(in: title.startIndex..<title.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            let word = String(title[range])
            switch tag {
            case .personalName?, .placeName?, .organizationName?: terms.insert(word)
            case .noun? where word.count >= 4: terms.insert(word.lowercased())
            default: break
            }
            return true
        }
        return terms
    }

    private static func entry(_ pair: (key: String, value: Double)) -> Entry? {
        guard let colon = pair.key.firstIndex(of: ":"),
              let kind = Kind(rawValue: String(pair.key[..<colon])) else { return nil }
        return Entry(key: pair.key, kind: kind, label: String(pair.key[pair.key.index(after: colon)...]), weight: pair.value)
    }

    // Oude voorkeuren vervagen, zodat je smaak mag veranderen.
    private mutating func decayIfNeeded() {
        let days = Date.now.timeIntervalSince(lastDecay) / 86_400
        guard days >= 1 else { return }
        let factor = pow(Self.dailyDecay, days)
        for key in weights.keys { weights[key]! *= factor }
        lastDecay = .now
    }

    private mutating func prune() {
        weights = weights.filter { abs($0.value) >= 0.1 }
        let words = weights.filter { $0.key.hasPrefix("\(Kind.word.rawValue):") }
        if words.count > Self.maxWords {
            for (key, _) in words.sorted(by: { abs($0.value) < abs($1.value) }).prefix(words.count - Self.maxWords) {
                weights[key] = nil
            }
        }
    }
}

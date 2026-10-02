import Foundation

// Voegt artikelen over hetzelfde nieuws uit verschillende bronnen samen
// (bv. NOS, NU.nl en de Volkskrant over hetzelfde besluit). Puur op woorden:
// snel, op het toestel, en in tests op echte feeds vrijwel zonder misgrepen.
enum StoryClusters {
    struct Story: Identifiable {
        var lead: FeedItem // het eerst gerangschikte artikel
        var others: [FeedItem] // zelfde verhaal, andere bronnen
        var id: String { lead.id }
        var all: [FeedItem] { [lead] + others }
    }

    /// Groepeert `items` met behoud van volgorde; elk verhaal staat op de plek
    /// van zijn hoogst gerangschikte artikel.
    static func group(_ items: [FeedItem]) -> [Story] {
        var stories: [Story] = []
        var leadWords: [Set<String>] = []
        var leadTitleWords: [Set<String>] = []
        for item in items {
            let words = Self.words(item.title + " " + item.summary.prefix(160))
            let titleWords = Self.words(item.title)
            let match = stories.indices.first { i in
                let lead = stories[i].lead
                guard lead.sourceLabel != item.sourceLabel,
                      !stories[i].others.contains(where: { $0.sourceLabel == item.sourceLabel }) else { return false }
                let shared = words.intersection(leadWords[i]).count
                let overlap = Double(shared) / Double(max(1, min(words.count, leadWords[i].count)))
                return shared >= 3 && overlap >= 0.3 && !titleWords.isDisjoint(with: leadTitleWords[i])
            }
            if let match {
                stories[match].others.append(item)
            } else {
                stories.append(Story(lead: item, others: []))
                leadWords.append(words)
                leadTitleWords.append(titleWords)
            }
        }
        return stories
    }

    static let stopwords: Set<String> = Set("""
    de het een en van in op te dat die voor met is zijn aan er niet om ook als bij of naar uit door over tot was \
    wordt worden heeft hebben nog maar dan meer kan na al wel dit deze zo geen wat wie hoe waar wil gaat komt jaar \
    nieuwe live the a an of to in on for and is are with as at by from that this it be has have after over new more \
    than will its his her their they he she we you not but about into up out says said
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    // Inhoudswoorden, afgekapt op 7 tekens als simpele stam ("stopzetten" ≈ "stopzet").
    static func words(_ text: some StringProtocol) -> Set<String> {
        Set(text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .filter { $0.count >= 3 }
            .map { String($0.prefix(7)) }
            .filter { !stopwords.contains($0) })
    }

}

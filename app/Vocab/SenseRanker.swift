import Foundation
import NaturalLanguage

/// Chooses which senses the detail page leads with: current ones (no obsolete, archaic,
/// dated, rare or nonstandard label), minus near-copies of one already kept, at most
/// `limit`, with every part of speech represented. The rest stay one tap away.
enum SenseRanker {
    struct Result: Equatable {
        var shown: [Sense]
        var hidden: [Sense]
    }

    /// Wiktionary labels that mark a sense as out of everyday use.
    static let outOfUse: Set<String> = [
        "obsolete", "archaic", "dated", "rare", "nonstandard", "historical",
        "uncommon", "nonce word", "proscribed", "now rare", "rare or obsolete",
    ]

    /// Sentence-embedding distance under which two definitions count as one sense. Checked
    /// on 19 words: true duplicates fell at 0.0–0.48, distinct senses as low as 0.53.
    static let duplicateDistance = 0.5
    /// Share of content words two definitions must have in common to count as one sense.
    static let duplicateOverlap = 0.6

    static func rank(_ senses: [Sense], tags: [SenseTag]?, limit: Int = 3) -> Result {
        guard !senses.isEmpty else { return Result(shown: [], hidden: []) }
        let current = senses.filter { !isOutOfUse($0, tags: tags) && !isNoise($0) }
        let pool = current.isEmpty ? senses : current

        var distinct: [Sense] = []
        for sense in pool where !distinct.contains(where: { isDuplicate($0, sense) }) {
            distinct.append(sense)
        }

        // The main part of speech leads; each other one gets a single slot, after it.
        let main = distinct[0].partOfSpeech.lowercased()
        let mainSenses = distinct.filter { $0.partOfSpeech.lowercased() == main }
        var firstOfOthers: [Sense] = []
        var seenPOS: Set<String> = [main]
        for s in distinct where seenPOS.insert(s.partOfSpeech.lowercased()).inserted { firstOfOthers.append(s) }
        var chosen = Array(mainSenses.prefix(firstOfOthers.isEmpty ? limit : limit - 1))
        chosen += firstOfOthers.prefix(limit - chosen.count)
        for s in distinct where chosen.count < limit && !chosen.contains(s) { chosen.append(s) }

        var shown: [Sense] = [], hidden: [Sense] = []
        for s in senses {
            if chosen.contains(s), !shown.contains(s) { shown.append(s) }
            else if !shown.contains(s), !hidden.contains(s) { hidden.append(s) }
        }
        return Result(shown: shown, hidden: hidden)
    }

    /// The sense a card should lead with.
    static func primary(_ senses: [Sense], tags: [SenseTag]?) -> Sense? {
        rank(senses, tags: tags).shown.first ?? senses.first
    }

    // MARK: - Judging

    static func isOutOfUse(_ sense: Sense, tags: [SenseTag]?) -> Bool {
        guard let tag = bestTag(for: sense, in: tags) else { return false }
        return tag.isGroup == true || tag.labels.contains { outOfUse.contains($0) }
    }

    /// Parts of speech that aren't meanings, and pointers to another form of the word.
    private static let noisePOS: Set<String> = ["symbol", "letter", "character", "number", "numeral"]
    private static let formOf = try! Regex(
        #"(?i)^(present participle|past participle|simple past|plural|third-person|comparative|superlative|alternative (form|spelling)|obsolete (form|spelling)|archaic (form|spelling)|misspelling|abbreviation|initialism)\b.*\bof\b"#)

    private static func isNoise(_ sense: Sense) -> Bool {
        noisePOS.contains(sense.partOfSpeech.lowercased()) || sense.definition.contains(formOf)
    }

    /// The definition line whose words best match this sense's text.
    private static func bestTag(for sense: Sense, in tags: [SenseTag]?) -> SenseTag? {
        guard let tags, !tags.isEmpty else { return nil }
        let w = words(sense.definition)
        let best = tags.max { overlap(w, $0.words) < overlap(w, $1.words) }
        return best.flatMap { overlap(w, $0.words) >= 0.5 ? $0 : nil }
    }

    private static func isDuplicate(_ a: Sense, _ b: Sense) -> Bool {
        if a.definition == b.definition { return true }
        guard a.partOfSpeech.lowercased() == b.partOfSpeech.lowercased() else { return false }
        let wa = contentWords(a.definition), wb = contentWords(b.definition)
        if overlap(wa, wb) >= duplicateOverlap { return true }
        // One definition restating the other inside a longer one.
        let small = wa.count <= wb.count ? wa : wb, big = wa.count <= wb.count ? wb : wa
        if !small.isEmpty, Double(small.intersection(big).count) / Double(small.count) >= 0.8 { return true }
        guard let embedding else { return false }
        return embedding.distance(between: a.definition, and: b.definition) < duplicateDistance
    }

    private static let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    // MARK: - Words

    nonisolated static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "of", "to", "or", "and", "in", "on", "by", "for", "with", "as", "at",
        "be", "is", "something", "someone", "one", "that", "which", "its", "it", "from", "not",
    ]

    private static func contentWords(_ text: String) -> Set<String> { words(text).subtracting(stopWords) }

    /// Jaccard overlap: shared words over all words.
    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b).count
        return union == 0 ? 0 : Double(a.intersection(b).count) / Double(union)
    }
}

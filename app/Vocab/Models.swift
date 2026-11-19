import Foundation
import SwiftData

/// One flattened dictionary sense, as stored on a saved word.
struct Sense: Codable, Hashable {
    var partOfSpeech: String
    var definition: String
    var examples: [String]
}

@Model
final class Word {
    @Attribute(.unique) var text: String
    var createdAt: Date
    var sensesData: Data
    var collections: [WordCollection] = []

    // FSRS scheduling state (one schedule per word, shared across collections).
    var stability: Double = 0
    var difficulty: Double = 0
    var due: Date = Date.distantPast
    var lastReview: Date?
    var reps: Int = 0
    var lapses: Int = 0

    init(text: String, senses: [Sense], createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
        self.sensesData = (try? JSONEncoder().encode(senses)) ?? Data()
    }

    var senses: [Sense] {
        let raw = (try? JSONDecoder().decode([Sense].self, from: sensesData)) ?? []
        // Re-clean on read so entries saved before a cleaner fix still display correctly.
        return raw.map { Sense(partOfSpeech: $0.partOfSpeech, definition: Wiktionary.clean($0.definition),
                               examples: $0.examples.map(Wiktionary.clean)) }
    }

    /// Plain-text facts handed to the explainer so it stays grounded.
    var facts: String {
        senses.prefix(8).map { s in
            var line = "- (\(s.partOfSpeech.lowercased())) \(s.definition)"
            if let ex = s.examples.first { line += " Example: \"\(ex)\"" }
            return line
        }.joined(separator: "\n")
    }
}

@Model
final class WordCollection {
    var name: String
    var createdAt: Date
    @Relationship(inverse: \Word.collections) var words: [Word] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}

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
    /// Encoded WordDetails; nil until the detail page first fetches it.
    var detailsData: Data?
    /// An AI-written memory aid, kept once the user asks for one.
    var mnemonic: String?
    /// Words added from this word's page. Links are two-way: read `linked` for both directions.
    @Relationship(deleteRule: .nullify) var linksOut: [Word] = []
    @Relationship(deleteRule: .nullify, inverse: \Word.linksOut) var linksIn: [Word] = []

    /// Every word explicitly linked to this one, whichever page it was added from.
    var linked: [Word] { linksOut + linksIn.filter { w in !linksOut.contains { $0 === w } } }

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

    var details: WordDetails? {
        get { detailsData.flatMap { try? JSONDecoder().decode(WordDetails.self, from: $0) } }
        set { detailsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
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
    /// Position in user-ordered lists (the "Save to" grid, Collections).
    var order: Int = 0
    /// The built-in Favorites collection: always present, can't be deleted.
    var isFavorites: Bool = false
    @Relationship(inverse: \Word.collections) var words: [Word] = []

    init(name: String, createdAt: Date = .now, order: Int = 0, isFavorites: Bool = false) {
        self.name = name
        self.createdAt = createdAt
        self.order = order
        self.isFavorites = isFavorites
    }

    /// User order first; creation date breaks ties for collections made before ordering existed.
    static let userOrder = [SortDescriptor(\WordCollection.order), SortDescriptor(\WordCollection.createdAt)]

    /// Makes sure Favorites exists and is pinned at the top of the list.
    static func ensureFavorites(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<WordCollection>())) ?? []
        let others = all.filter { !$0.isFavorites }
        let top = (others.map(\.order).min() ?? 0) - 1
        if let favorites = all.first(where: \.isFavorites) {
            if favorites.order > top { favorites.order = top }
        } else {
            context.insert(WordCollection(name: "Favorites", createdAt: .distantPast, order: top, isFavorites: true))
        }
    }

    /// The next slot at the end of the user's order.
    static func nextOrder(in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<WordCollection>())) ?? []
        return (all.map(\.order).max() ?? 0) + 1
    }
}

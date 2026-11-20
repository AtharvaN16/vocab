import Foundation

/// Answers to Ask's default questions with no model at all, built only from the word's
/// dictionary entry, so they never claim more than the dictionary says. They use the
/// pill markup: `[[word]]` for a related word, `{{add}}` to end an example sentence.
enum TemplateAnswers {
    enum Kind { case conversation, synonyms, sentences, quiz }

    /// Matched by meaning rather than exact text, so rewording a preset doesn't break it.
    static func kind(for question: String) -> Kind? {
        let q = question.lowercased()
        if q.contains("quiz") { return .quiz }
        if q.contains("synonym") { return .synonyms }
        if q.contains("sentence") { return .sentences }
        if q.contains("conversation") { return .conversation }
        return nil
    }

    /// The template engine's answer for a default question; any other engine or
    /// question goes to the explainer as before. Fetches the word's relations if the
    /// detail page hasn't yet, without saving them.
    static func stream(_ explainer: any Explainer, word: String, facts: String, senses: [Sense],
                       details: WordDetails?, question: String) async -> AsyncThrowingStream<String, Error> {
        guard explainer is TemplateExplainer, let kind = kind(for: question) else {
            return explainer.answer(word: word, facts: facts, question: question)
        }
        var details = details
        if details == nil { details = try? await Wiktionary.details(for: word) }
        let text = answer(kind, word: word, senses: senses, details: details)
        return AsyncThrowingStream { $0.yield(text); $0.finish() }
    }

    static func answer(_ kind: Kind, word: String, senses: [Sense], details: WordDetails?) -> String {
        let f = Facts(word: word, senses: senses, details: details)
        switch kind {
        case .conversation: return conversation(f)
        case .synonyms: return synonyms(f)
        case .sentences: return sentences(f)
        case .quiz: return quiz(f)
        }
    }

    // MARK: - The four answers

    private static func conversation(_ f: Facts) -> String {
        var out = ["“\(f.word)” is \(f.article) \(f.pos): \(f.definitionLowercased)."]
        let ex = f.examples.prefix(2)
        if ex.isEmpty {
            out.append("The dictionary has no example sentences for it yet, so try it in one of your own.")
        } else {
            out.append("Here is how it sits in a sentence:")
            out += ex.map { "\($0) {{add}}" }
        }
        if !f.synonyms.isEmpty {
            out.append("Close neighbours worth knowing: \(list(f.synonyms.prefix(3))).")
        }
        return out.joined(separator: "\n\n")
    }

    private static func synonyms(_ f: Facts) -> String {
        var out = ["“\(f.word)” means \(f.definitionLowercased)."]
        if f.synonyms.isEmpty {
            out.append("The dictionary lists no synonyms for it. An AI engine can suggest some and explain how they differ.")
        } else {
            out.append("The dictionary lists \(list(f.synonyms.prefix(4))) as its closest neighbours.")
            out.append("Templates can only list them. An AI engine can explain how each one differs.")
        }
        if let opposite = f.antonyms.first {
            out.append("Its opposite is [[\(opposite)]].")
        }
        return out.joined(separator: "\n\n")
    }

    private static func sentences(_ f: Facts) -> String {
        let ex = f.examples.prefix(3)
        guard !ex.isEmpty else { return "The dictionary has no example sentences for “\(f.word)” yet." }
        var out = ex.enumerated().map { "\($0.offset + 1). \($0.element) {{add}}" }
        if ex.count < 3 {
            out.append(ex.count == 1 ? "That is the only example the dictionary has." : "Those are all the examples the dictionary has.")
        }
        return out.joined(separator: "\n\n")
    }

    private static func quiz(_ f: Facts) -> String {
        var questions = ["Which word means “\(f.definition)”?"]
        if let gap = f.examples.lazy.compactMap(f.blanked).first {
            questions.append("Fill the gap: \(gap)")
        }
        let synonyms = f.synonyms.prefix(2)
        if !synonyms.isEmpty {
            questions.append("Name a word that means much the same as “\(f.word)”.")
        }
        var out = questions.enumerated().map { "\($0.offset + 1). \($0.element)" }
        var answer = questions.count > 2 || (questions.count == 2 && synonyms.isEmpty)
            ? "Answers: 1 and 2 are “\(f.word)”." : "Answers: 1 is “\(f.word)”."
        if !synonyms.isEmpty {
            answer += " For \(questions.count), \(list(synonyms, joiner: "or")) would do."
        }
        out.append(answer)
        return out.joined(separator: "\n\n")
    }

    /// "[[a]], [[b]] and [[c]]"
    private static func list<S: Collection>(_ words: S, joiner: String = "and") -> String where S.Element == String {
        let pills = words.map { "[[\($0)]]" }
        guard pills.count > 1 else { return pills.first ?? "" }
        return pills.dropLast().joined(separator: ", ") + " \(joiner) " + pills.last!
    }

    // MARK: - Facts

    private struct Facts {
        let word: String
        let pos: String
        let definition: String
        let examples: [String]
        let synonyms: [String]
        let antonyms: [String]
        private let stem: Regex<AnyRegexOutput>?

        init(word: String, senses: [Sense], details: WordDetails?) {
            self.word = word
            let main = senses.first
            pos = main?.partOfSpeech.lowercased() ?? "word"
            var def = main?.definition.trimmingCharacters(in: .whitespacesAndNewlines) ?? "not in the dictionary yet"
            while def.hasSuffix(".") { def.removeLast() }
            definition = def

            var s = word.lowercased().trimmingCharacters(in: .whitespaces)
            if s.count > 4, s.hasSuffix("e") || s.hasSuffix("y") { s.removeLast() }
            stem = s.count >= 3 ? try? Regex("\\b\(NSRegularExpression.escapedPattern(for: s))\\w*").ignoresCase() : nil

            // Real sentences of a readable length, ones that use the word first.
            var seen = Set<String>()
            let all = senses.flatMap(\.examples)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { (20...220).contains($0.count) && !$0.contains("{") && seen.insert($0.lowercased()).inserted }
            let stem = self.stem
            examples = all.filter { e in stem.map { e.contains($0) } ?? false } + all.filter { e in !(stem.map { e.contains($0) } ?? false) }

            func usable(_ list: [String]) -> [String] {
                list.filter { w in
                    w.lowercased() != word.lowercased() && w.split(separator: " ").count <= 2
                        && w.allSatisfy { $0.isLetter || $0 == " " || $0 == "-" || $0 == "’" || $0 == "'" }
                }
            }
            synonyms = usable(details?.synonyms ?? [])
            antonyms = usable(details?.antonyms ?? [])
        }

        var article: String { "aeiou".contains(pos.first ?? "x") ? "an" : "a" }

        var definitionLowercased: String {
            guard let first = definition.first, definition.dropFirst().first?.isLowercase ?? true else { return definition }
            return first.lowercased() + definition.dropFirst()
        }

        /// The example with the word (and its inflections) blanked out; nil if it doesn't appear.
        func blanked(_ example: String) -> String? {
            guard let stem, example.contains(stem) else { return nil }
            return example.replacing(stem, with: "_____")
        }
    }
}

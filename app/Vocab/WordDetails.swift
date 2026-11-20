import Foundation

/// The rest of a dictionary entry beyond senses: pronunciation, word relations and
/// the prose sections. Fetched lazily the first time a word's detail page opens.
nonisolated struct WordDetails: Codable, Hashable {
    var ipa: String?
    var syllables: [String] = []
    /// Register labels found on the senses, e.g. "literary", "archaic".
    var register: [String] = []
    var synonyms: [String] = []
    var antonyms: [String] = []
    /// Derived and related terms: the word's family.
    var family: [String] = []
    var etymology: String?
    var usage: String?
    /// Labels for each definition line, in page order, so senses can be told current
    /// from obsolete. nil on details saved before this field existed: refetch those.
    var senseTags: [SenseTag]?
}

/// A definition line's plain words and its labels ("obsolete", "rare", "transitive").
nonisolated struct SenseTag: Codable, Hashable {
    var words: Set<String>
    var labels: [String]
    /// A heading line whose meaning lives in its "##" sub-senses; the dictionary feed
    /// flattens these into one long combined definition.
    var isGroup: Bool?
}

extension Wiktionary {
    /// Reads the English section of the page's wikitext for the structured fields, then
    /// has Wiktionary render the two prose sections so their templates read as text.
    static func details(for word: String) async throws -> WordDetails {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        for candidate in [trimmed, trimmed.lowercased()] {
            guard let wikitext = try await wikitext(candidate),
                  let english = WikitextEntry.englishSection(wikitext) else { continue }
            let entry = WikitextEntry(english)
            var details = entry.structured
            let (etymology, usage) = try await render(etymology: entry.etymologyWikitext,
                                                      usage: entry.usageWikitext, title: candidate)
            details.etymology = etymology
            details.usage = usage
            return details
        }
        throw LookupError.notFound
    }

    private static func wikitext(_ page: String) async throws -> String? {
        var c = URLComponents(string: "https://en.wiktionary.org/w/api.php")!
        c.queryItems = [
            .init(name: "action", value: "parse"),
            .init(name: "page", value: page),
            .init(name: "prop", value: "wikitext"),
            .init(name: "redirects", value: "1"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
        ]
        var req = URLRequest(url: c.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["parse"] as? [String: Any])?["wikitext"] as? String
    }

    /// One request renders both sections; a marker paragraph splits them back apart.
    private static func render(etymology: String?, usage: String?, title: String) async throws -> (String?, String?) {
        let marker = "VOCABSECTIONBREAK"
        guard etymology != nil || usage != nil else { return (nil, nil) }
        let source = stripReferences("\(etymology ?? "")\n\n\(marker)\n\n\(usage ?? "")")

        var form = URLComponents()
        form.queryItems = [
            .init(name: "action", value: "parse"),
            .init(name: "text", value: source),
            .init(name: "title", value: title),
            .init(name: "contentmodel", value: "wikitext"),
            .init(name: "prop", value: "text"),
            .init(name: "disablelimitreport", value: "1"),
            .init(name: "disableeditsection", value: "1"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
        ]
        var req = URLRequest(url: URL(string: "https://en.wiktionary.org/w/api.php")!)
        req.httpMethod = "POST"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // "+" survives URLComponents unescaped but means a space in form bodies.
        req.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let html = (json?["parse"] as? [String: Any])?["text"] as? String ?? ""
        let parts = clean(html).components(separatedBy: marker)
        func tidy(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        return (tidy(parts[safe: 0]), tidy(parts[safe: 1]))
    }
}

extension Wiktionary {
    /// Footnotes render as "[1]" in the text and a citation list after it; drop both.
    nonisolated static func stripReferences(_ wikitext: String) -> String {
        wikitext
            .replacingOccurrences(of: "(?is)<ref[^>/]*>.*?</ref>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<ref[^>]*/>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<references\\s*/>|\\{\\{reflist[^}]*\\}\\}", with: "", options: .regularExpression)
    }
}

/// A small, forgiving reader for the parts of Wiktionary wikitext the detail page uses.
struct WikitextEntry {
    /// (heading, body) for each level-3+ section inside the English section.
    let sections: [(heading: String, body: String)]
    let full: String

    static func englishSection(_ wikitext: String) -> String? {
        guard let start = wikitext.range(of: "==English==") else { return nil }
        let rest = wikitext[start.upperBound...]
        // The next language heading is a line of exactly two = signs.
        if let next = rest.range(of: "\n==[^=]", options: .regularExpression) {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    init(_ english: String) {
        full = english
        var result: [(String, String)] = []
        var heading = ""
        var body: [Substring] = []
        for line in english.split(separator: "\n", omittingEmptySubsequences: false) {
            if let h = Self.heading(line) {
                result.append((heading, body.joined(separator: "\n")))
                heading = h
                body = []
            } else {
                body.append(line)
            }
        }
        result.append((heading, body.joined(separator: "\n")))
        sections = result
    }

    private static func heading(_ line: Substring) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("==="), t.hasSuffix("===") else { return nil }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
    }

    private func bodies(_ prefix: String) -> [String] {
        sections.filter { $0.heading.hasPrefix(prefix) }.map(\.body)
    }

    var structured: WordDetails {
        var d = WordDetails()
        let ipa = Self.templates(in: full, named: ["IPA"]).first?.positional.dropFirst()
            .first { $0.hasPrefix("/") || $0.hasPrefix("[") }
        d.ipa = ipa
        if let hyph = Self.templates(in: full, named: ["hyphenation", "hyph"]).first {
            // Alternative hyphenations are separated by an empty argument; keep the first.
            d.syllables = Array(hyph.positional.dropFirst().prefix { !$0.isEmpty })
        }
        d.synonyms = relations(templates: ["syn", "synonyms"], section: "Synonyms")
        d.antonyms = relations(templates: ["ant", "antonyms"], section: "Antonyms")
        d.family = Self.unique(bodies("Derived terms").flatMap(Self.terms) + bodies("Related terms").flatMap(Self.terms))
        d.register = registerLabels
        d.senseTags = senseTags
        return d
    }

    private func relations(templates names: Set<String>, section: String) -> [String] {
        let inline = Self.templates(in: full, named: names).flatMap { $0.positional.dropFirst() }
        return Self.unique(inline.map(Self.word) + bodies(section).flatMap(Self.terms))
    }

    static let registers: Set<String> = [
        "formal", "informal", "literary", "poetic", "archaic", "obsolete", "dated", "rare",
        "colloquial", "slang", "humorous", "figurative", "uncommon", "pejorative", "derogatory",
    ]

    /// Labels on the first (main) sense only; later senses often carry "archaic" or "rare"
    /// that would mislabel the word as a whole.
    private var registerLabels: [String] {
        let defLines = String(full.split(separator: "\n").first { $0.hasPrefix("# ") } ?? "")
        let labels = Self.templates(in: defLines, named: ["lb", "lbl", "label"]).flatMap { $0.positional.dropFirst() }
        return Self.unique(labels.map { $0.lowercased() }.filter(Self.registers.contains))
    }

    /// Every definition line ("# " and "## ", not "#:" examples or "#*" quotes). Sub-senses
    /// inherit their heading's labels; a heading takes its sub-senses' words as well.
    private var senseTags: [SenseTag] {
        var tags: [SenseTag] = []
        var parent: Int?
        for line in full.split(separator: "\n") {
            let isSub = line.hasPrefix("## ")
            guard isSub || line.hasPrefix("# ") else { continue }
            let text = String(line.dropFirst(isSub ? 3 : 2))
            var labels = Self.templates(in: text, named: ["lb", "lbl", "label"])
                .flatMap { $0.positional.dropFirst() }.map { $0.lowercased() }
            let words = SenseRanker.words(Self.plain(text))
            if isSub, let p = parent {
                labels = tags[p].labels + labels
                tags[p].isGroup = true
                tags[p].words.formUnion(words)
            }
            tags.append(SenseTag(words: words, labels: labels))
            if !isSub { parent = tags.count - 1 }
        }
        return tags
    }

    /// Wikitext to rough plain text: templates dropped, links reduced to their label.
    static func plain(_ wikitext: String) -> String {
        var s = wikitext
        // Innermost templates first, until none remain.
        while let r = s.range(of: "\\{\\{[^{}]*\\}\\}", options: .regularExpression) { s.removeSubrange(r) }
        s = s.replacingOccurrences(of: "\\[\\[(?:[^\\]|]*\\|)?([^\\]]*)\\]\\]", with: "$1", options: .regularExpression)
        return s.replacingOccurrences(of: "'", with: "")
    }

    // Etymology: the first section only, minus tree/root templates that render as tables.
    var etymologyWikitext: String? {
        guard let body = bodies("Etymology").first else { return nil }
        let kept = body.split(separator: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            // A tree template that carries text= writes the etymology out as prose; keep it.
            if t.hasPrefix("{{ety"), t.contains("text=") { return true }
            return !t.isEmpty && !["{{ety", "{{root", "{{was wotd", "{{wikipedia", "[[File:", "[[Image:", "{{rfe", "{{PIE word"]
                .contains { t.hasPrefix($0) }
        }
        // tree=1 draws the etymology as a diagram, which flattens to noise; the text= prose stays.
        let text = kept.joined(separator: "\n").replacingOccurrences(of: "|tree=1", with: "")
        return text.isEmpty ? nil : text
    }

    var usageWikitext: String? {
        guard let body = bodies("Usage notes").first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else { return nil }
        return body
    }

    // MARK: - Template reading

    struct Template { let name: String; let positional: [String] }

    /// Top-level-ish templates with the given names. Arguments are split on "|" outside
    /// nested links and templates; named arguments (k=v) are dropped.
    static func templates(in text: String, named names: Set<String>) -> [Template] {
        var out: [Template] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count - 1 {
            guard chars[i] == "{", chars[i + 1] == "{" else { i += 1; continue }
            var depth = 0, j = i
            var args: [String] = [], current = ""
            while j < chars.count - 1 {
                let pair = String(chars[j...j + 1])
                if pair == "{{" || pair == "[[" { depth += 1; if depth > 1 { current += pair }; j += 2; continue }
                if pair == "}}" || pair == "]]" {
                    depth -= 1
                    if depth == 0 { break }
                    current += pair; j += 2; continue
                }
                if chars[j] == "|", depth == 1 { args.append(current); current = "" } else { current.append(chars[j]) }
                j += 1
            }
            args.append(current)
            let name = args.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if names.contains(name) {
                let positional = args.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.contains("=") || $0.hasPrefix("/") }
                out.append(Template(name: name, positional: positional))
                i = j + 2
            } else {
                i += 2 // Step inside, so templates nested in other templates are still found.
            }
        }
        return out
    }

    /// Words listed in a relations section: {{col|en|a|b}}, {{l|en|a}} or [[a]].
    static func terms(_ body: String) -> [String] {
        var words: [String] = []
        for t in templates(in: body, named: ["col", "col2", "col3", "col4", "col5", "der2", "der3", "der4",
                                             "rel2", "rel3", "rel4", "col-auto", "der-top"]) {
            words += t.positional.dropFirst().map(word)
        }
        for t in templates(in: body, named: ["l", "link", "l-self"]) {
            if let w = t.positional[safe: 1] { words.append(word(w)) }
        }
        if words.isEmpty {
            let link = try! Regex(#"\[\[([^\]|#]+)(?:\|[^\]]*)?\]\]"#, as: (Substring, Substring).self)
            words += body.matches(of: link).map { String($0.1) }
        }
        // Some lists put alternative spellings in one item: "cost cutting,cost-cutting".
        return words.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    /// Strips inline modifiers ("word<q:formal>") and link brackets.
    static func word(_ raw: String) -> String {
        var w = raw
        if let lt = w.firstIndex(of: "<") { w = String(w[..<lt]) }
        w = w.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        return w.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func unique(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.filter { w in
            guard !w.isEmpty, !w.hasPrefix("Thesaurus:"), !w.contains(":"), !w.contains("{") else { return false }
            return seen.insert(w.lowercased()).inserted
        }
    }
}

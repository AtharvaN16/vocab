import Foundation

/// Live lookups against English Wiktionary (CC BY-SA 4.0). PoC only: the
/// shipped app would prefer the downloadable offline dictionary.
enum Wiktionary {
    // Wikimedia policy: name/version plus contact URL, or requests fall to the 10 req/min tier.
    static let userAgent = "Vocab/0.1 (https://github.com/AtharvaN16/vocab)"

    enum LookupError: LocalizedError {
        case notFound
        var errorDescription: String? { "No English entry on Wiktionary." }
    }

    static func suggestions(for query: String) async throws -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var c = URLComponents(string: "https://en.wiktionary.org/w/api.php")!
        c.queryItems = [
            .init(name: "action", value: "opensearch"),
            .init(name: "search", value: q),
            .init(name: "limit", value: "10"),
            .init(name: "namespace", value: "0"),
            .init(name: "format", value: "json"),
        ]
        let data = try await get(c.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [Any]
        return (json?[safe: 1] as? [String]) ?? []
    }

    static func lookup(_ word: String) async throws -> [Sense] {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        for candidate in [trimmed, trimmed.lowercased()] {
            if let senses = try await fetch(candidate), !senses.isEmpty { return senses }
        }
        throw LookupError.notFound
    }

    private static func fetch(_ word: String) async throws -> [Sense]? {
        let path = word.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? word
        let url = URL(string: "https://en.wiktionary.org/api/rest_v1/page/definition/\(path)")!
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let english = json["en"] as? [[String: Any]] else { return nil }

        var senses: [Sense] = []
        for group in english {
            let pos = group["partOfSpeech"] as? String ?? ""
            for def in group["definitions"] as? [[String: Any]] ?? [] {
                let text = clean(def["definition"] as? String ?? "")
                guard !text.isEmpty else { continue }
                let examples = (def["examples"] as? [String] ?? []).map(clean).filter { !$0.isEmpty }
                senses.append(Sense(partOfSpeech: pos, definition: text, examples: examples))
            }
        }
        return senses
    }

    private static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: req).0
    }

    nonisolated static func clean(_ html: String) -> String {
        // Drop embedded <style>/<script> blocks (and CSS already saved without its tags) before stripping tags.
        var s = html.replacingOccurrences(of: "(?is)<(style|script)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\.mw-parser-output[^{}]*\\{[^}]*\\}", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">"] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        s = decodeNumericEntities(s).replacingOccurrences(of: "\u{200E}", with: "")
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Wiktionary {
    /// "&#42;" and "&#x2A;" to "*".
    nonisolated static func decodeNumericEntities(_ s: String) -> String {
        guard s.contains("&#") else { return s }
        var out = "", rest = Substring(s)
        while let amp = rest.range(of: "&#") {
            out += rest[..<amp.lowerBound]
            let after = rest[amp.upperBound...]
            if let semi = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semi) <= 8 {
                let body = after[..<semi]
                let value = body.first == "x" || body.first == "X"
                    ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
                if let value, let scalar = Unicode.Scalar(value) {
                    out.unicodeScalars.append(scalar)
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&#"
            rest = after
        }
        return out + rest
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

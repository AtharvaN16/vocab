import Foundation
import FoundationModels

/// AI mode is one interface with swappable engines, so the shipping engine
/// (Apple, on-device) and a testing engine (Groq, cloud) compare like for like.
protocol Explainer {
    var label: String { get }
    /// Streams the cumulative answer text for any prompt.
    func respond(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error>
    /// Streams the cumulative answer to a question about one word.
    func answer(word: String, facts: String, question: String) -> AsyncThrowingStream<String, Error>
}

extension Explainer {
    /// A question about one word, grounded in its dictionary facts.
    func answer(word: String, facts: String, question: String) -> AsyncThrowingStream<String, Error> {
        respond(instructions: TutorPrompt.instructions,
                prompt: TutorPrompt.user(word: word, facts: facts, question: question))
    }
}

enum Engine: String, CaseIterable, Identifiable {
    case automatic, apple, groq, templates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .apple: "Apple (on-device)"
        case .groq: "Groq (cloud, testing)"
        case .templates: "Templates (no AI)"
        }
    }

    static func resolve(_ choice: Engine, groqKey: String, groqModel: String) -> any Explainer {
        switch choice {
        case .apple: return AppleExplainer()
        case .groq: return GroqExplainer(key: GroqExplainer.effectiveKey(groqKey), model: groqModel)
        case .templates: return TemplateExplainer()
        case .automatic:
            if AppleExplainer.isAvailable { return AppleExplainer() }
            #if DEBUG
            let key = GroqExplainer.effectiveKey(groqKey)
            if !key.isEmpty { return GroqExplainer(key: key, model: groqModel) }
            #endif
            return TemplateExplainer()
        }
    }
}

enum TutorPrompt {
    static let instructions = """
    You help a fluent, native English speaker bring precise, literary words into their \
    active vocabulary. Base every claim about the word's meaning on the DICTIONARY FACTS \
    provided. If the facts do not settle something, say you are unsure rather than guess. \
    Write plainly and briefly, under 150 words, with no preamble. \
    Use plain text only: no markdown, asterisks, pound signs or backticks. \
    Put each example sentence, synonym or quiz question on its own line, \
    separated by a blank line. \
    Answer only the question asked. Do not add quizzes, quiz questions, synonym \
    lists or other extra sections unless the question asks for them.
    """

    static func user(word: String, facts: String, question: String) -> String {
        "WORD: \(word)\n\nDICTIONARY FACTS:\n\(facts)\n\nQUESTION: \(question)"
    }
}

/// Search's Ask AI: questions that aren't about one saved word.
enum GeneralPrompt {
    static let instructions = """
    You help a fluent, native English speaker express themselves with precise, \
    literary words. Answer the question plainly and briefly, under 150 words, with \
    no preamble. Use plain text only: no markdown, asterisks, pound signs or backticks. \
    Put each example sentence or list item on its own line, separated by a blank line. \
    If you are unsure of a fact, say so rather than guess.
    """

    static func user(question: String, previous: (question: String, answer: String)?) -> String {
        guard let previous else { return question }
        return "EARLIER QUESTION: \(previous.question)\n\nEARLIER ANSWER: \(previous.answer)\n\nFOLLOW-UP: \(question)"
    }
}

/// "Find a word for…": candidates come back one per line as "word | gloss",
/// which every engine can produce without a schema.
enum FindWordPrompt {
    static let instructions = """
    You find the precise English word for a description. Suggest 4 to 6 real English \
    words or short set phrases that fit, the most precise first. Prefer words a well-read \
    adult would use in writing. Output one per line, exactly as: word | gloss \
    The gloss says in under 10 words how the word fits the description. \
    Write each word in lowercase unless it is a proper noun. \
    No numbering, no bullets, no other text.
    """

    /// True for "a word for…", "what's the word for…", "word that means…", "what do you call…".
    static func matches(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("word for") || t.contains("word that") || t.contains("word meaning")
            || t.contains("words for") || t.contains("what do you call") || t.contains("term for")
    }

    struct Candidate: Hashable {
        var word: String
        var gloss: String
    }

    /// "Coy" → "coy", but "SNAFU" and "Machiavellian" stay as they are.
    private static func lowercasedStart(_ w: String) -> String {
        guard let first = w.first, first.isUppercase,
              w.dropFirst().allSatisfy({ !$0.isUppercase }) else { return w }
        let eponyms = ["machiavellian", "byzantine", "kafkaesque", "orwellian", "pyrrhic",
                       "dickensian", "sisyphean", "herculean", "freudian", "panglossian"]
        if eponyms.contains(where: { w.lowercased().hasPrefix($0) }) { return w }
        return first.lowercased() + w.dropFirst()
    }

    /// Parses complete lines only; the last line may still be streaming.
    static func parse(_ text: String, complete: Bool) -> [Candidate] {
        var lines = text.components(separatedBy: .newlines)
        if !complete { lines.removeLast() }
        return lines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-•*0123456789.)\"")))
            }
            guard parts.count == 2, !parts[0].isEmpty, parts[0].count < 40 else { return nil }
            return Candidate(word: lowercasedStart(parts[0]), gloss: parts[1])
        }
    }
}

struct AppleExplainer: Explainer {
    let label = "Apple Foundation Models · on-device"
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func respond(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard Self.isAvailable else {
                        throw ExplainerError.unavailable("Apple Intelligence is off or unsupported on this device.")
                    }
                    let session = LanguageModelSession(instructions: instructions)
                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Testing only. Never ship an API key inside an app.
struct GroqExplainer: Explainer {
    /// Groq's free tier covers its whole catalogue, rate-limited per model.
    static let defaultModel = "openai/gpt-oss-20b"

    /// The key from app/.env, baked into Debug builds only.
    static var bundledKey: String {
        #if DEBUG
        (Bundle.main.object(forInfoDictionaryKey: "GroqAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        #else
        ""
        #endif
    }

    /// A key typed in Settings wins; otherwise the one from app/.env.
    static func effectiveKey(_ typed: String) -> String {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? bundledKey : typed
    }

    let key: String
    let model: String
    var label: String { "Groq · \(model) · cloud" }

    func respond(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !key.isEmpty else { throw ExplainerError.unavailable("Add GROQ_API_KEY to app/.env, or a key in Settings.") }
                    var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    let body: [String: Any] = [
                        "model": model,
                        "stream": false,
                        "messages": [
                            ["role": "system", "content": instructions],
                            ["role": "user", "content": prompt],
                        ],
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, response) = try await URLSession.shared.data(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        let detail = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
                        throw ExplainerError.unavailable("Groq returned \(status). \(detail)")
                    }
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let message = (json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
                    continuation.yield((message?["content"] as? String ?? "(empty response)").trimmingCharacters(in: .whitespacesAndNewlines))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The floor: what the app can say with no model at all.
struct TemplateExplainer: Explainer {
    let label = "Templates · no AI"

    func answer(word: String, facts: String, question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("No AI engine is available, so here is what the dictionary says about “\(word)”:\n\n\(facts)")
            continuation.finish()
        }
    }

    func respond(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ExplainerError.unavailable(
                "No AI engine is available. Turn on Apple Intelligence, or pick another engine in Settings."))
        }
    }
}

enum ExplainerError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let m): m }
    }
}

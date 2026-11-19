import Foundation
import FoundationModels

/// AI mode is one interface with swappable engines, so the shipping engine
/// (Apple, on-device) and a testing engine (OpenCode, cloud) compare like for like.
protocol Explainer {
    var label: String { get }
    /// Streams the cumulative answer text.
    func answer(word: String, facts: String, question: String) -> AsyncThrowingStream<String, Error>
}

enum Engine: String, CaseIterable, Identifiable {
    case automatic, apple, openCode, templates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .apple: "Apple (on-device)"
        case .openCode: "OpenCode (cloud, testing)"
        case .templates: "Templates (no AI)"
        }
    }

    static func resolve(_ choice: Engine, openCodeKey: String, openCodeModel: String) -> any Explainer {
        switch choice {
        case .apple: return AppleExplainer()
        case .openCode: return OpenCodeExplainer(key: openCodeKey, model: openCodeModel)
        case .templates: return TemplateExplainer()
        case .automatic:
            if AppleExplainer.isAvailable { return AppleExplainer() }
            #if DEBUG
            if !openCodeKey.isEmpty { return OpenCodeExplainer(key: openCodeKey, model: openCodeModel) }
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
    Write plainly and briefly, under 150 words, with no preamble.
    """

    static func user(word: String, facts: String, question: String) -> String {
        "WORD: \(word)\n\nDICTIONARY FACTS:\n\(facts)\n\nQUESTION: \(question)"
    }
}

struct AppleExplainer: Explainer {
    let label = "Apple Foundation Models · on-device"
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func answer(word: String, facts: String, question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard Self.isAvailable else {
                        throw ExplainerError.unavailable("Apple Intelligence is off or unsupported on this device.")
                    }
                    let session = LanguageModelSession(instructions: TutorPrompt.instructions)
                    let stream = session.streamResponse(to: TutorPrompt.user(word: word, facts: facts, question: question))
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
struct OpenCodeExplainer: Explainer {
    let key: String
    let model: String
    var label: String { "OpenCode Zen · \(model) · cloud" }

    func answer(word: String, facts: String, question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !key.isEmpty else { throw ExplainerError.unavailable("Add an OpenCode API key in Settings.") }
                    var req = URLRequest(url: URL(string: "https://opencode.ai/zen/v1/chat/completions")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    let body: [String: Any] = [
                        "model": model,
                        "stream": false,
                        "messages": [
                            ["role": "system", "content": TutorPrompt.instructions],
                            ["role": "user", "content": TutorPrompt.user(word: word, facts: facts, question: question)],
                        ],
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, response) = try await URLSession.shared.data(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        let detail = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
                        throw ExplainerError.unavailable("OpenCode returned \(status). \(detail)")
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
}

enum ExplainerError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let m): m }
    }
}

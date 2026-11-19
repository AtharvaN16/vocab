import SwiftUI

struct AskView: View {
    let word: Word

    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("openCodeKey") private var openCodeKey = ""
    @AppStorage("openCodeModel") private var openCodeModel = "big-pickle"

    @State private var question = ""
    @State private var asked: String?
    @State private var answer = ""
    @State private var engineLabel = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    private let presets = [
        "How would I use it in conversation?",
        "How is it different from its closest synonyms?",
        "Give me three sentences that use it well.",
        "Quiz me on it.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Ask about", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(word.text).font(.system(size: 40, weight: .bold))

                    if let asked {
                        Text(asked).font(.headline)
                        if let error {
                            Text(error).foregroundStyle(.red)
                        } else if answer.isEmpty {
                            ProgressView()
                        } else {
                            Text(answer)
                                .font(.system(.body, design: .serif))
                                .textSelection(.enabled)
                        }
                        if !engineLabel.isEmpty {
                            Text(engineLabel).font(.caption).foregroundStyle(.tertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(presets, id: \.self) { p in
                            Button { ask(p) } label: {
                                Text(p).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(Theme.control, in: Capsule())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                TextField("Ask anything about “\(word.text)”", text: $question, axis: .vertical)
                    .focused($focused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onSubmit { ask(question) }
                Button { ask(question) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.page)
                        .frame(width: 48, height: 48)
                        .background(Color.primary, in: Circle())
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(16)
        }
        .background(Theme.page.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onDisappear { task?.cancel() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo") { ask(presets[1]) }
            #endif
        }
    }

    private func ask(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        task?.cancel()
        question = ""
        focused = false
        asked = q
        answer = ""
        error = nil
        let explainer = Engine.resolve(Engine(rawValue: engineRaw) ?? .automatic,
                                       openCodeKey: openCodeKey, openCodeModel: openCodeModel)
        engineLabel = explainer.label
        let word = word.text, facts = self.word.facts
        task = Task {
            do {
                for try await partial in explainer.answer(word: word, facts: facts, question: q) {
                    answer = partial
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

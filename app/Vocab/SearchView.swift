import SwiftUI
import SwiftData

/// A word Search hands to the word sheet, and why the AI suggested it.
struct SearchPick: Identifiable, Equatable {
    var text: String
    /// The AI's one-line reason, for words that came from Ask AI.
    var note: String?
    var id: String { text }
}

/// Search, centre stage. What you type is set large in the middle of the screen,
/// dictionary matches sit under it, and Ask AI stays one tap away next to the mic.
/// A word you pick opens in the deck's pushback sheet, over this screen.
struct SearchView: View {
    var onClose: () -> Void
    @Binding var pick: SearchPick?
    /// Set from outside (the word sheet's "Ask about it") to run a question here.
    @Binding var askRequest: String?

    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("groqKey") private var groqKey = ""
    @AppStorage("groqModel") private var groqModel = GroqExplainer.defaultModel
    @AppStorage("recentSearches") private var recentRaw = ""
    @Query private var saved: [Word]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Typing
    @State private var query = ""
    @State private var suggestions: [String] = []
    /// The query the current suggestions belong to, so a stale empty list isn't read as "no match".
    @State private var suggestionsFor = ""
    @FocusState private var focused: Bool
    @State private var appeared = false
    @State private var lastSubmit = Date.distantPast

    // Answer
    /// The question on screen; nil while typing.
    @State private var asked: String?
    @State private var isFind = false
    @State private var candidates: [FindWordPrompt.Candidate] = []
    /// Candidates below this index were already on screen; newer ones arrive as a group.
    @State private var arrivalBase = 0
    @State private var tokens: [RevealToken] = []
    @State private var answerText = ""
    @State private var finished = false
    @State private var waiting = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var followUp = ""
    @FocusState private var followFocused: Bool

    @State private var dictation = Dictation()
    @State private var dictationBase = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Ask AI leads (ink pill, return asks) once the text stops looking like a word:
    /// more than one word, a question mark, or a single word the dictionary doesn't know.
    private var aiLeads: Bool {
        let t = trimmed
        guard !t.isEmpty else { return false }
        if t.contains(" ") || t.hasSuffix("?") { return true }
        return suggestionsFor == t && suggestions.isEmpty && t.count >= 3
    }

    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private var savedTexts: Set<String> { Set(saved.map { $0.text.lowercased() }) }

    private var engine: Engine { Engine(rawValue: engineRaw) ?? .automatic }
    private var explainer: any Explainer { Engine.resolve(engine, groqKey: groqKey, groqModel: groqModel) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SheetLeadingButton(kind: asked == nil ? .close : .back) {
                    asked == nil ? close() : back()
                }
                Spacer()
            }
            .padding(.horizontal, 10) // concentric with the sheet corner, like SheetHeader
            .padding(.top, -14)

            ZStack {
                if asked == nil {
                    // The typed text leaves fast, so it never sits beside the question.
                    typing.transition(.asymmetric(
                        insertion: .opacity.animation(.strongEaseOut(0.25)),
                        removal: .blurFade.animation(.strongEaseOut(0.16))))
                } else {
                    // The container is static; the question and rows carry the entrance.
                    answer.transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.animation(.strongEaseOut(0.16))))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Theme.page.ignoresSafeArea())
        .onAppear {
            focused = true
            withAnimation(entrance) { appeared = true }
        }
        .onDisappear { task?.cancel(); dictation.stop() }
        .onChange(of: dictation.transcript) { _, t in
            let joined = dictationBase.isEmpty ? t : dictationBase + " " + t
            if asked == nil { query = joined } else { followUp = joined }
        }
        .onChange(of: askRequest) { _, request in
            guard let request else { return }
            askRequest = nil
            ask(request)
        }
        .task(id: trimmed) {
            let q = trimmed
            guard !q.isEmpty, !q.contains(" ") else {
                suggestions = []
                suggestionsFor = q
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let found = (try? await Wiktionary.suggestions(for: q)) ?? []
            guard !Task.isCancelled else { return }
            suggestions = Array(found.prefix(4))
            suggestionsFor = q
        }
    }

    /// Opening Search happens many times a day: short, and it moves only a few points.
    private var entrance: Animation { .strongEaseOut(reduceMotion ? 0.2 : 0.32) }

    // MARK: Typing

    private var typing: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 26) {
                        field
                            .modifier(Enter(on: appeared, rise: 10, reduceMotion: reduceMotion))
                        list
                            .modifier(Enter(on: appeared, rise: 6, reduceMotion: reduceMotion))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.never)
                .scrollBounceBehavior(.basedOnSize)
            }
            controls
                .opacity(appeared ? 1 : 0)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var field: some View {
        TextField("", text: $query,
                  // One line: a multi-line field truncates its prompt to the first line.
                  prompt: Text("Search or ask").foregroundStyle(.ink4),
                  axis: .vertical)
            .focused($focused)
            .font(.system(size: 34, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(1...6)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(aiLeads ? .send : .search)
            .onSubmit(submit)
            // A multi-line field puts return into the text; treat it as submit.
            .onChange(of: query) { _, q in
                guard q.contains("\n") else { return }
                query = q.replacingOccurrences(of: "\n", with: "")
                submit()
            }
            .accessibilityLabel("Search a word or ask anything")
    }

    /// Typed many times a minute, so rows swap without animation.
    @ViewBuilder
    private var list: some View {
        VStack(spacing: 18) {
            if trimmed.isEmpty {
                Text("Type a word, or describe what you want to say")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                ForEach(recents.prefix(3), id: \.self) { r in
                    row(r) { r.contains(" ") ? ask(r) : open(r) }
                }
            } else if !aiLeads || !suggestions.isEmpty {
                ForEach(Array(suggestions.enumerated()), id: \.element) { i, s in
                    row(s, lead: i == 0 && !aiLeads) { open(s) }
                }
            } else if suggestionsFor == trimmed, !trimmed.contains(" ") {
                Text("No dictionary match")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink4)
            }
        }
        .transaction { $0.animation = nil }
    }

    private func row(_ title: String, lead: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(lead ? .semibold : .medium))
                .foregroundStyle(lead ? AnyShapeStyle(Color.ink) : AnyShapeStyle(Color.ink3))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if !trimmed.isEmpty {
                Button { ask(trimmed) } label: {
                    Label("Ask AI", systemImage: "sparkle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(aiLeads ? Theme.page : Color.ink)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(aiLeads ? Color.ink : Theme.control, in: Capsule())
                        // State change, not movement: a quick colour swap.
                        .animation(.easeOut(duration: 0.15), value: aiLeads)
                }
                .buttonStyle(PressStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
            }
            Spacer(minLength: 0)
            micButton { query }
        }
        .animation(.strongEaseOut(0.2), value: trimmed.isEmpty)
    }

    private func micButton(_ current: @escaping () -> String) -> some View {
        Button {
            if !dictation.isRecording { dictationBase = current().trimmingCharacters(in: .whitespaces) }
            Task { await dictation.toggle() }
        } label: {
            Image(systemName: dictation.isRecording ? "waveform" : "mic")
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .background(Theme.control, in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Dictate")
    }

    // MARK: Answer

    private var answer: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let asked {
                        Text(asked)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Rises in just behind the typed text's exit: one handoff, not a
                            // crossfade. Keyed by the question, so each follow-up arrives too.
                            .modifier(ArriveOnce(delay: 0.05, reduceMotion: reduceMotion))
                            .id(asked)
                    }
                    answerBody
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Theme.page.opacity(0), Theme.page], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
                    .allowsHitTesting(false)
            }
            composer
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .modifier(FadeOnce(reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder
    private var answerBody: some View {
        if let error {
            Text(error).foregroundStyle(.ink3)
        } else if waiting {
            ThinkingLines().transition(.opacity)
        } else if isFind, !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(candidates.enumerated()), id: \.element) { i, c in
                    candidateRow(c)
                        .modifier(ArriveOnce(delay: Self.stagger(i - arrivalBase), reduceMotion: reduceMotion))
                }
            }
            // The rows carry the entrance; the list itself must not fade over them.
            .transition(.identity)
            if finished { refinements.modifier(ArriveOnce(delay: 0.1, reduceMotion: reduceMotion)) }
        } else if !tokens.isEmpty {
            StreamingAnswer(tokens: tokens)
        }
    }

    /// Tightening gaps, so the list arrives as one wave rather than a queue.
    private static func stagger(_ i: Int) -> Double {
        [0, 0.05, 0.09, 0.12, 0.14, 0.15][max(0, min(i, 5))]
    }

    private func candidateRow(_ c: FindWordPrompt.Candidate) -> some View {
        Button { pick = SearchPick(text: c.word, note: c.gloss) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.word)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.ink)
                    Text(c.gloss)
                        .font(.subheadline)
                        .foregroundStyle(.ink3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if savedTexts.contains(c.word.lowercased()) {
                    Label("Saved", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ink3)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private var refinements: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["More literary", "One word only", "Less harsh", "More formal"], id: \.self) { r in
                    Button { ask(r, followUp: true) } label: {
                        Text(r)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .overlay(Capsule().strokeBorder(Theme.control, lineWidth: 1.5))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
        // Chips scroll out to the screen edge instead of stopping at the margin.
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .padding(.horizontal, -24)
        .padding(.top, 8)
    }

    /// Ask's composer: frameless text, model pill, mic, send.
    private var composer: some View {
        VStack(spacing: 16) {
            TextField("", text: $followUp,
                      prompt: Text("Ask a follow-up").foregroundStyle(.ink3),
                      axis: .vertical)
                .focused($followFocused)
                .font(.title3)
                .multilineTextAlignment(.center)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { ask(followUp, followUp: true) }
                .onChange(of: followUp) { _, q in
                    guard q.contains("\n") else { return }
                    followUp = q.replacingOccurrences(of: "\n", with: "")
                    ask(followUp, followUp: true)
                }

            HStack(spacing: 12) {
                Menu {
                    Picker("Model", selection: $engineRaw) {
                        ForEach(Engine.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(modelName).lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ink3)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.control, in: Capsule())
                }
                .tint(.primary)

                Spacer(minLength: 0)
                micButton { followUp }

                let canSend = !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { ask(followUp, followUp: true) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(canSend ? Theme.page : Color.ink4)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Color.ink : Theme.control, in: Circle())
                        .animation(.easeOut(duration: 0.15), value: canSend)
                }
                .buttonStyle(PressStyle())
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.top, 8)
    }

    private var modelName: String {
        let name = switch explainer {
        case is AppleExplainer: "Apple Intelligence"
        case let cloud as GroqExplainer: String(cloud.model.split(separator: "/").last ?? "")
        default: "No AI"
        }
        return engine == .automatic ? "\(name) (auto)" : name
    }

    // MARK: Behaviour

    private func submit() {
        // A multi-line field can report return twice (onSubmit and the newline).
        guard Date.now.timeIntervalSince(lastSubmit) > 0.4 else { return }
        lastSubmit = .now
        let t = trimmed
        guard !t.isEmpty else { return }
        if aiLeads {
            ask(t)
        } else {
            open(suggestions.first { $0.lowercased() == t.lowercased() } ?? suggestions.first ?? t)
        }
    }

    private func open(_ word: String) {
        remember(word)
        dictation.stop()
        focused = false
        pick = SearchPick(text: word)
    }

    private func ask(_ raw: String, followUp isFollowUp: Bool = false) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        dictation.stop()
        focused = false
        followFocused = false
        followUp = ""
        dictationBase = ""
        task?.cancel()

        let previous: (question: String, answer: String)? =
            isFollowUp && asked != nil && !answerText.isEmpty ? (asked!, answerText) : nil
        let find = FindWordPrompt.matches(q) || (previous != nil && isFind)
        if previous == nil { remember(q) }

        var plain = Transaction()
        plain.disablesAnimations = true
        withTransaction(plain) {
            candidates = []
            arrivalBase = 0
            tokens = []
            answerText = ""
            finished = false
            error = nil
            waiting = false
            isFind = find
        }
        // The typed text gives way and the question rises in at the top, together.
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0)) {
            asked = q
        }

        let instructions = find ? FindWordPrompt.instructions : GeneralPrompt.instructions
        let prompt = GeneralPrompt.user(question: q, previous: previous)
        let explainer = self.explainer
        let reduce = reduceMotion
        task = Task {
            // Shown only if the model is slow, so a fast answer never flashes a placeholder.
            let thinking = Task {
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled, candidates.isEmpty, tokens.isEmpty, error == nil else { return }
                withAnimation(.strongEaseOut(0.3)) { waiting = true }
            }
            defer { thinking.cancel() }
            do {
                var shown = ""
                for try await partial in explainer.respond(instructions: instructions, prompt: prompt) {
                    try Task.checkCancellation()
                    answerText = partial
                    if find {
                        update(candidates: FindWordPrompt.parse(partial, complete: false))
                    } else if partial.hasPrefix(shown) {
                        tokens += RevealToken.schedule(String(partial.dropFirst(shown.count)),
                                                       after: tokens.last?.born ?? .now, instant: reduce)
                        if waiting { withAnimation(.strongEaseOut(0.3)) { waiting = false } }
                    } else {
                        tokens = RevealToken.schedule(partial, after: .now, instant: true)
                    }
                    shown = partial
                }
                thinking.cancel()
                if find {
                    let all = FindWordPrompt.parse(answerText, complete: true)
                    if all.isEmpty {
                        // The model ignored the format; show what it said.
                        isFind = false
                        tokens = RevealToken.schedule(answerText, after: .now, instant: reduce)
                    } else {
                        update(candidates: all)
                    }
                }
                waiting = false
                finished = true
            } catch is CancellationError {
            } catch {
                waiting = false
                self.error = error.localizedDescription
            }
        }
    }

    private func update(candidates new: [FindWordPrompt.Candidate]) {
        guard new.count > candidates.count else { return }
        arrivalBase = candidates.count
        if waiting { withAnimation(.strongEaseOut(0.25)) { waiting = false } }
        candidates = new
    }

    private func back() {
        task?.cancel()
        dictation.stop()
        withAnimation(.strongEaseOut(0.25)) { asked = nil }
        focused = true
    }

    private func close() {
        task?.cancel()
        dictation.stop()
        focused = false
        onClose()
    }

    private func remember(_ entry: String) {
        let list = [entry] + recents.filter { $0.lowercased() != entry.lowercased() }
        recentRaw = list.prefix(4).joined(separator: "\n")
    }
}

/// Search's entrance: a few points of rise out of a light blur. Driven by one flag
/// so the field and its list move as one.
private struct Enter: ViewModifier {
    let on: Bool
    let rise: CGFloat
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on || reduceMotion ? 0 : 4)
            .offset(y: on || reduceMotion ? 0 : rise)
    }
}

/// Fades and rises in the first time the view appears, after `delay`.
private struct ArriveOnce: ViewModifier {
    let delay: Double
    let reduceMotion: Bool
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .offset(y: shown || reduceMotion ? 0 : 8)
            // A timer, not an animation delay: a delayed animation started inside
            // another transaction runs with it, and the wave collapses into one fade.
            .task {
                if !reduceMotion, delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                withAnimation(.strongEaseOut(reduceMotion ? 0.2 : 0.4)) { shown = true }
            }
    }
}

/// Supporting chrome fades in place, together with the lead; it never moves.
private struct FadeOnce: ViewModifier {
    let reduceMotion: Bool
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .task { withAnimation(.strongEaseOut(reduceMotion ? 0.2 : 0.3)) { shown = true } }
    }
}

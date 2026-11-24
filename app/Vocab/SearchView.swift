import SwiftUI
import SwiftData

/// A word Search hands to the word sheet, and why the AI suggested it.
struct SearchPick: Identifiable, Equatable {
    var text: String
    /// The AI's one-line reason, for words that came from Ask AI.
    var note: String?
    var id: String { text }
}

/// Search, in the same medium bottom sheet as Save to / New collection. It only
/// looks up words: what you type is set large in the middle and dictionary
/// matches sit under it. Anything open-ended goes through Ask AI, which is always
/// in the bottom corner. Asking (the button, or swiping the sheet up) parks the
/// sheet at the top like a deck card and opens the Ask panel under it, carrying
/// over whatever is typed. A tapped word forms over everything as the deck card it
/// would become (`SearchWordStage`); one the AI suggested opens in the word sheet.
struct SearchView: View {
    var onClose: () -> Void
    @Binding var pick: SearchPick?
    /// The question for the Ask panel under the parked sheet.
    @Binding var question: String?
    /// The sheet is parked at the top with the Ask panel showing.
    @Binding var parked: Bool
    /// Set from outside (the word sheet's "Ask about it") to ask a question here.
    @Binding var askRequest: String?

    @AppStorage("recentSearches") private var recentRaw = ""
    @Environment(\.sheetParkProgress) private var parkProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sheetBottomPadding) private var sheetBottomPadding
    /// A 44pt control concentric with the sheet's 32pt corners sits 32 - 22 = 10pt
    /// from the side and the bottom.
    private let cornerInset: CGFloat = 10

    @State private var query = ""
    @State private var suggestions: [String] = []
    /// The query the current suggestions belong to, so a stale empty list isn't read as "no match".
    @State private var suggestionsFor = ""
    @FocusState private var focused: Bool
    @State private var lastSubmit = Date.distantPast
    /// The coming park was asked for with its own question, so the typed text
    /// mustn't replace it.
    @State private var explicitAsk = false
    /// The history list is showing in place of the search box.
    @State private var showHistory = false
    @State private var confirmClear = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        ZStack(alignment: .top) {
            // History scrolls up under its header's veil; typing keeps it above.
            if showHistory {
                history.transition(.blurFade)
            } else {
                VStack(spacing: 0) { header; typing }.transition(.blurFade)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: showHistory)
        // The history list scrolls; the sheet can't be dragged from it.
        .preference(key: SheetPanDisabledKey.self, value: showHistory)
        .confirmationDialog("Delete all search history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { recentRaw = "" }
        }
        // Parking hands the stage to the panel below; only the sheet's edge peeks.
        .opacity(1 - parkProgress)
        .onAppear { focused = true }
        // Back from a formed card (dismissed or added): ready for the next word.
        .onChange(of: pick) { _, p in
            if p == nil, !parked, !showHistory { focused = true }
        }
        // Builds the forming card's GPU pipelines before the first word can be tapped.
        .overlay(alignment: .topLeading) { FormingWarmup() }
        // Swiped up: whatever is typed becomes the question. With nothing typed the
        // panel keeps its last conversation, or offers its opening questions.
        .onChange(of: parked) { _, isParked in
            if isParked {
                focused = false
                if explicitAsk {
                    explicitAsk = false
                } else if !trimmed.isEmpty, trimmed != question {
                    remember(trimmed)
                    question = trimmed
                }
                // The question now lives in the panel; the box comes back empty.
                clearBox()
            }
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

    // MARK: Header

    @ViewBuilder private var header: some View {
        if showHistory {
            SheetHeader(leading: .back, title: "History", onLeading: closeHistory)
        } else {
            SheetHeader(leading: .close, onLeading: close) {
                SheetIconButton(systemImage: "clock", label: "Search history") {
                    focused = false
                    showHistory = true
                }
            }
        }
    }

    // MARK: History

    /// Every recent search, newest first, as plain rows: tap to run it again (a
    /// question asks, a word opens), the x on the right removes it. Delete all
    /// sits where the search controls are.
    private var history: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if recents.isEmpty {
                        Text("Words and questions you search show up here.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.ink4)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                            .transition(.opacity.animation(.strongEaseOut(0.2)))
                    }
                    ForEach(recents, id: \.self) { r in
                        historyRow(r)
                            // Leaves where it stands while the rows below close the gap.
                            .transition(.asymmetric(insertion: .identity, removal: .blurFade))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .sheetEdgeFade { header }

            if !recents.isEmpty {
                Button { confirmClear = true } label: {
                    Text("Delete all")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.red.opacity(0.14), in: Theme.actionShape)
                        .contentShape(Theme.actionShape)
                }
                .buttonStyle(PressStyle())
                // 14pt in from the sheet's sides and bottom.
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14 - sheetBottomPadding)
                .transition(.blurFade)
            }
        }
        .animation(.smooth(duration: 0.3), value: recents)
    }

    private func historyRow(_ r: String) -> some View {
        let isQuestion = r.contains(" ") || r.hasSuffix("?")
        return HStack(spacing: 4) {
            Button {
                showHistory = false
                isQuestion ? ask(r) : open(r)
            } label: {
                Text(r)
                    .font(.headline).foregroundStyle(.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())

            Button { forget(r) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.ink3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Remove \(r) from history")
        }
        .padding(.leading, 8)
    }

    private func forget(_ entry: String) {
        recentRaw = recents.filter { $0 != entry }.joined(separator: "\n")
    }

    private func closeHistory() {
        showHistory = false
        focused = true
    }

    // MARK: Typing

    private var typing: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 26) {
                        field
                        list
                    }
                    // The term leads: when the list under it changes height, the centred
                    // stack glides to its new spot instead of jumping. Keyed by the list's
                    // shape, so typing that only changes the words never moves anything.
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0),
                               value: listShape)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.never)
                .scrollBounceBehavior(.basedOnSize)
                .sheetEdgeFade()
            }
            controls
                .padding(.horizontal, cornerInset)
                // Cancels the sheet's own bottom padding, so the bottom gap is the corner inset.
                .padding(.bottom, cornerInset - sheetBottomPadding)
        }
    }

    private var field: some View {
        TextField("", text: $query,
                  // One line: a multi-line field truncates its prompt to the first line.
                  prompt: Text("Search a word").foregroundStyle(.ink4),
                  axis: .vertical)
            .focused($focused)
            .font(.system(size: 26, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(1...6)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit(submit)
            // A multi-line field puts return into the text; treat it as submit.
            .onChange(of: query) { _, q in
                guard q.contains("\n") else { return }
                query = q.replacingOccurrences(of: "\n", with: "")
                submit()
            }
            .accessibilityLabel("Search a word")
    }

    /// The dictionary came back empty for exactly what's typed.
    private var noMatch: Bool {
        !trimmed.isEmpty && !trimmed.contains(" ") && suggestionsFor == trimmed && suggestions.isEmpty
    }

    /// What the list is showing, as one number: -1 the hint, -2 no match, else how
    /// many rows. Only a change here animates; new words in the same rows swap in place.
    private var listShape: Int {
        if trimmed.isEmpty { return -1 }
        if noMatch { return -2 }
        return suggestions.count
    }

    /// Updated on every keystroke, so the rows arrive together (no stagger) and
    /// are keyed by position: a row whose word changes stays put.
    @ViewBuilder
    private var list: some View {
        VStack(spacing: 18) {
            if trimmed.isEmpty {
                Text("Type a word. For anything else, ask AI.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.hint)
            } else if noMatch {
                Text("No dictionary match")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink4)
                    .transition(.hint)
            } else {
                ForEach(suggestions.indices, id: \.self) { i in
                    let s = suggestions[i]
                    row(s, lead: i == 0) { open(s) }
                        .transition(.suggestion(reduceMotion: reduceMotion))
                }
            }
        }
    }

    private func row(_ title: String, lead: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(lead ? AnyShapeStyle(Color.ink) : AnyShapeStyle(Color.ink3))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    /// Ask AI sits where the mic used to, always there: the way in for anything
    /// that isn't a single word. Whatever is typed goes along as the question.
    private var controls: some View {
        HStack {
            Spacer(minLength: 0)
            Button { ask(trimmed) } label: {
                Label("Ask AI", systemImage: "sparkle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.control, in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
    }

    // MARK: Behaviour

    private func submit() {
        // A multi-line field can report return twice (onSubmit and the newline).
        guard Date.now.timeIntervalSince(lastSubmit) > 0.4 else { return }
        lastSubmit = .now
        let t = trimmed
        guard !t.isEmpty else { return }
        open(suggestions.first { $0.lowercased() == t.lowercased() } ?? suggestions.first ?? t)
    }

    private func open(_ word: String) {
        remember(word)
        focused = false
        clearBox()
        pick = SearchPick(text: word)
    }

    /// Opens the Ask panel. With a question it asks it; with nothing typed the
    /// panel keeps its last conversation, or offers its opening questions.
    private func ask(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        focused = false
        if !q.isEmpty {
            remember(q)
            question = q
            clearBox()
            if !parked { explicitAsk = true }
        }
        parked = true
    }

    /// Empties the box. Return submits from inside the field's own edit, where a
    /// changed binding can be overwritten by the text view, so it clears again a beat later.
    private func clearBox() {
        query = ""
        Task { @MainActor in query = "" }
    }

    private func close() {
        focused = false
        onClose()
    }

    private func remember(_ entry: String) {
        let list = [entry] + recents.filter { $0.lowercased() != entry.lowercased() }
        recentRaw = list.prefix(30).joined(separator: "\n")
    }
}

private extension AnyTransition {
    /// Suggestions support the term's glide: they come in with it out of a light blur
    /// and a short rise, and leave on a quick fade while the term is already moving.
    static func suggestion(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: SuggestionIn(shown: false, reduceMotion: reduceMotion),
                                 identity: SuggestionIn(shown: true, reduceMotion: reduceMotion))
                .animation(.strongEaseOut(reduceMotion ? 0.2 : 0.26)),
            removal: .opacity.animation(.strongEaseOut(0.12)))
    }

    /// Hints are decoration: they only fade, and leave faster than they come.
    static var hint: AnyTransition {
        .asymmetric(insertion: .opacity.animation(.strongEaseOut(0.2)),
                    removal: .opacity.animation(.strongEaseOut(0.1)))
    }
}

private struct SuggestionIn: ViewModifier {
    let shown: Bool
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .offset(y: shown || reduceMotion ? 0 : 6)
    }
}

import SwiftUI
import SwiftData
import CoreHaptics
import NaturalLanguage

/// The page a deck card opens into: the word, and under it one page at a time (the
/// definitions, an example, synonyms, antonyms, etymology, usage, a mnemonic, linked
/// words), each in the card's own big type with no headings. A labelled button at the bottom
/// names the next page; a back button and progress segments sit beside and above it. A short
/// sideways swipe moves too, through a pan that only starts on a horizontal move, so a drag
/// down still closes the page through the zoom transition. Presented with a zoom from the
/// card, so the first page leads with CardFace's word and definition.
///
/// Synonyms and antonyms are big pills. Saved words open their own page on a tap; the rest
/// carry a plus and are added by holding them. Holding fills the pill in; once it is full,
/// its card forms over the page the same way a pill's card does in Ask (`GenerateStage`),
/// and the word is saved and linked both ways to this one as the card lands. Both pages are
/// always there, with an Add pill, so you can write in your own words.
struct WordDetailView: View {
    let word: Word
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("groqKey") private var groqKey = ""
    @AppStorage("groqModel") private var groqModel = GroqExplainer.defaultModel

    @State private var details: WordDetails?
    @State private var mnemonic: String?
    @State private var writingMnemonic = false
    @State private var mnemonicError: String?
    @Query private var saved: [Word]
    /// Related words being looked up and added right now.
    @State private var adding: Set<String> = []
    @State private var addError: String?
    /// The card forming for a held word, over the whole page.
    @State private var job: GenerateJob?
    /// The held word's senses, waiting for its card to land (or the card, for them).
    @State private var fetched: [Sense]?
    @State private var landed = false
    /// Haptics: a firm tap when a hold completes, success when the word is saved.
    @State private var holdCount = 0
    @State private var savedCount = 0
    @State private var failCount = 0
    @State private var openWord: Word?
    /// Which senses lead; set once details (with their labels) are in.
    @State private var ranked: SenseRanker.Result?
    /// The page on screen, by id, so pages that arrive later never move it.
    @State private var currentID = Chunk.meaningID
    /// Which way the last move went: pages rise forward and sink back.
    @State private var forward = true
    /// The relation list whose Add pill is being typed into, and what's typed.
    @State private var entering: Relation?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    /// "Word added", shown once a held word's card has left the page.
    @State private var toaster = Toaster()
    @State private var toastPending = false

    private static let move = Animation.spring(duration: 0.3, bounce: 0)
    private static let shownRelations = 4

    var body: some View {
        let list = chunks
        let index = list.firstIndex { $0.id == currentID } ?? 0
        VStack(alignment: .leading, spacing: 0) {
            closeButton
                .padding(.bottom, 28)
            header
                .padding(.bottom, 20)
            ZStack(alignment: .topLeading) {
                chunkView(list[index])
                    .id(list[index].id)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(ChunkMove(forward: forward)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(SidewaysSwipe { dx, vx in
                if dx < -40 || vx < -400 { go(1) } else if dx > 40 || vx > 400 { go(-1) }
            })
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(list, index) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardSurface().ignoresSafeArea())
        // A held word's card forms over everything, close button included, and the page
        // fogs over behind it. The stage runs its own entrance and exit.
        .pageOverlay(item: job) { job in
            // Held long enough to read the word and its definition before it leaves.
            GenerateStage(job: job, hold: 1.8,
                          onLanded: { landed = true; commit(job.title) },
                          onDone: {
                              self.job = nil
                              if toastPending { toastPending = false; toaster.show("Word added") }
                          })
        }
        .sensoryFeedback(.selection, trigger: currentID)
        .sensoryFeedback(.impact(weight: .medium), trigger: holdCount)
        .sensoryFeedback(.success, trigger: savedCount)
        .sensoryFeedback(.error, trigger: failCount)
        .fullScreenCover(item: $openWord) { WordDetailView(word: $0) }
        .task { await loadDetails() }
        .task { await GenerateStage.prewarm() }
        // A full-screen cover is its own page.
        .pageOverlayHost()
        .toastHost(toaster)
    }

    // MARK: Header

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Theme.control, in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Close")
    }

    /// The card's word, at the card's size, on every page. The speaker is a bare filled glyph
    /// with the same 44 pt touch area as before.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(word.text)
                .font(Theme.detailWordFont)
                // Like CardTitle: one word shrinks on one line; a phrase may wrap first.
                .lineLimit(word.text.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.5)
            Button { Speaker.say(word.text) } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.ink3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Pronounce \(word.text)")
            Spacer(minLength: 0)
        }
    }

    // MARK: Pages

    enum Relation { case synonyms, antonyms }

    struct Chunk: Identifiable {
        enum Kind {
            case definitions([String])
            case example(String)
            case relation(Relation, [String])
            case linked([Word])
            case prose(String?)
            case mnemonic
        }
        static let meaningID = "meaning"
        let id: String
        /// The next button's name for it.
        let title: String
        let kind: Kind
    }

    /// Everything there is to show, in reading order. Definitions, synonyms, antonyms,
    /// etymology and the mnemonic are always there; the example, usage and linked words only
    /// when there are some.
    private var chunks: [Chunk] {
        let primary = SenseRanker.primary(word.senses, tags: details?.senseTags)
        let others = (ranked?.shown ?? []).map(\.definition).filter { $0 != primary?.definition }.prefix(2)
        var out: [Chunk] = []
        out.append(Chunk(id: Chunk.meaningID, title: "Definitions",
                         kind: .definitions([primary?.definition ?? "No definition yet."] + others)))
        if let ex = primary?.examples.first {
            out.append(Chunk(id: "example", title: "In a sentence", kind: .example(ex)))
        }
        let byText = savedByText
        let synonyms = top(details?.synonyms ?? [], saved: byText)
        let antonyms = top(details?.antonyms ?? [], saved: byText)
        out.append(Chunk(id: "synonyms", title: "Synonyms", kind: .relation(.synonyms, synonyms)))
        out.append(Chunk(id: "antonyms", title: "Antonyms", kind: .relation(.antonyms, antonyms)))
        out.append(Chunk(id: "etymology", title: "Etymology",
                         kind: .prose(details?.etymology.map { firstSentences($0, 2) })))
        if let u = details?.usage.map({ firstSentences($0, 2) }), !u.isEmpty {
            out.append(Chunk(id: "usage", title: "Usage", kind: .prose(u)))
        }
        out.append(Chunk(id: "mnemonic", title: "Mnemonic", kind: .mnemonic))
        let linked = linkedWords(shown: Set((synonyms + antonyms).map { $0.lowercased() }))
        if !linked.isEmpty {
            out.append(Chunk(id: "linked", title: "Linked words", kind: .linked(linked)))
        }
        return out
    }

    @ViewBuilder
    private func chunkView(_ chunk: Chunk) -> some View {
        Group {
            switch chunk.kind {
            case .definitions(let defs):
                definitions(defs)
            case .example(let text):
                big("“\(text)”")
            case .prose(let text):
                if let text, !text.isEmpty { big(text) } else { big("Nothing found yet.", ink: AnyShapeStyle(Color.ink4)) }
            case .relation(let kind, let words):
                pills(words, adding: kind)
            case .linked(let words):
                pills(words.map(\.text), adding: nil)
            case .mnemonic:
                mnemonicChunk
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One definition as on the card; several get a hanging "a.", "b.", "c." in the same type
    /// and the faintest ink, with every definition lined up in one column after the letters.
    @ViewBuilder
    private func definitions(_ defs: [String]) -> some View {
        if defs.count == 1 {
            big(defs[0], ink: AnyShapeStyle(.secondary))
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 22) {
                ForEach(Array(defs.enumerated()), id: \.offset) { i, d in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(Self.letter(i))
                            .font(Theme.detailDefinitionFont)
                            .foregroundStyle(.ink4)
                            .accessibilityHidden(true)
                        big(d, ink: AnyShapeStyle(.secondary))
                    }
                }
            }
        }
    }

    private static func letter(_ i: Int) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return "\(letters[i % letters.count])."
    }

    /// The page text type (Theme.detailDefinitionFont), stepping down before it would overflow.
    private func big(_ text: String, ink: AnyShapeStyle = AnyShapeStyle(Color.ink3)) -> some View {
        Text(text)
            .font(Theme.detailDefinitionFont)
            .foregroundStyle(ink)
            .minimumScaleFactor(0.6)
    }

    /// Big pills in the card's type. Saved words open their page; the rest are held to add.
    /// A relation list ends with an Add pill for writing in your own word.
    private func pills(_ words: [String], adding kind: Relation?) -> some View {
        let byText = savedByText
        return VStack(alignment: .leading, spacing: 16) {
            FlowLayout(spacing: 12, lineSpacing: 12) {
                ForEach(words, id: \.self) { w in
                    if let target = byText[w.lowercased()] {
                        Button { openWord = target } label: {
                            Text(target.text)
                                .font(Theme.detailDefinitionFont)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal, 24)
                                .frame(height: BigPill.height)
                                .background(Theme.control, in: Capsule())
                        }
                        .buttonStyle(PressStyle(pressedScale: 0.97))
                        .accessibilityHint("Opens \(target.text)")
                        .transition(.blurReplace)
                    } else {
                        HoldToAdd(text: w, busy: adding.contains(w), big: true) { add(w) }
                            .transition(.blurReplace)
                    }
                }
                if let kind {
                    addPill(kind)
                }
            }
            if let addError, adding.isEmpty {
                Text(addError).font(.footnote).foregroundStyle(.ink3)
            }
        }
    }

    /// An outlined pill that turns into a field: type a word, return adds it to this list.
    @ViewBuilder
    private func addPill(_ kind: Relation) -> some View {
        if entering == kind {
            TextField("word", text: $draft)
                .font(Theme.detailDefinitionFont)
                .foregroundStyle(.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit { addCustom(kind) }
                .fixedSize()
                .frame(minWidth: 120)
                .padding(.horizontal, 24)
                .frame(height: BigPill.height)
                .overlay { Capsule().strokeBorder(Theme.control, lineWidth: BigPill.stroke) }
                .transition(.blurReplace)
        } else {
            Button {
                draft = ""
                withAnimation(.strongEaseOut(0.25)) { entering = kind }
                fieldFocused = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .bold))
                    Text("Add")
                }
                .font(Theme.detailDefinitionFont)
                .foregroundStyle(.ink3)
                .padding(.leading, 20)
                .padding(.trailing, 24)
                .frame(height: BigPill.height)
                .overlay { Capsule().strokeBorder(Theme.control, lineWidth: BigPill.stroke) }
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle(pressedScale: 0.97))
            .accessibilityLabel(kind == .synonyms ? "Add a synonym" : "Add an antonym")
            .transition(.blurReplace)
        }
    }

    @ViewBuilder
    private var mnemonicChunk: some View {
        if let text = mnemonic ?? word.mnemonic {
            big(text)
                .transition(.blurReplace)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Button { writeMnemonic() } label: {
                    HStack(spacing: 10) {
                        if writingMnemonic {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(writingMnemonic ? "Writing…" : "Write one with AI")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 22)
                    .frame(height: 56)
                    .background(Theme.control, in: Capsule())
                }
                .buttonStyle(PressStyle(pressedScale: 0.97))
                .disabled(writingMnemonic)
                if let mnemonicError {
                    Text(mnemonicError).font(.footnote).foregroundStyle(.ink3)
                }
            }
        }
    }

    // MARK: Moving between pages

    /// Progress segments over the back and next buttons. The next button names the page it
    /// leads to; on the last page it closes the page.
    private func bottomBar(_ list: [Chunk], _ index: Int) -> some View {
        let isLast = index >= list.count - 1
        let nextTitle = isLast ? "Back to the deck" : list[index + 1].title
        return VStack(spacing: 22) {
            HStack(spacing: 5) {
                ForEach(list.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Color.ink : Color.ink4.opacity(0.35))
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(index + 1) of \(list.count)")
            HStack(spacing: 10) {
                if index > 0 {
                    Button { go(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .background(Theme.control, in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Back to \(list[index - 1].title)")
                    .transition(.blurReplace)
                }
                Button { isLast ? dismiss() : go(1) } label: {
                    HStack {
                        ZStack(alignment: .leading) {
                            Text(nextTitle)
                                .id(nextTitle)
                                .transition(.blurReplace)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: isLast ? "xmark" : "chevron.right")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 22)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .background(Theme.control, in: Capsule())
                }
                .buttonStyle(PressStyle(pressedScale: 0.97))
                .accessibilityLabel(isLast ? "Back to the deck" : "Next: \(nextTitle)")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(Self.move, value: index)
    }

    /// Moves `delta` pages. The direction is set first and the move lands a beat later, so the
    /// leaving page takes its exit from the new direction too (rise forward, sink back).
    private func go(_ delta: Int) {
        let list = chunks
        let index = list.firstIndex { $0.id == currentID } ?? 0
        let next = index + delta
        guard list.indices.contains(next) else { return }
        forward = delta > 0
        fieldFocused = false
        entering = nil
        let id = list[next].id
        Task { @MainActor in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Self.move) { currentID = id }
        }
    }

    // MARK: Words

    /// Saved words keyed by lowercased text.
    private var savedByText: [String: Word] {
        Dictionary(saved.map { ($0.text.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Up to four words, saved ones first, never this word itself.
    private func top(_ words: [String], saved: [String: Word]) -> [String] {
        let me = word.text.lowercased()
        let candidates = words.filter { $0.lowercased() != me }
        let inApp = candidates.filter { saved[$0.lowercased()] != nil }
        let others = candidates.filter { saved[$0.lowercased()] == nil }
        return Array((inApp + others).prefix(Self.shownRelations))
    }

    /// Adds a typed word to the front of this word's synonyms or antonyms, so it shows.
    private func addCustom(_ kind: Relation) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { draft = ""; fieldFocused = false; withAnimation(.strongEaseOut(0.25)) { entering = nil } }
        guard !text.isEmpty, text.lowercased() != word.text.lowercased() else { return }
        var d = details ?? WordDetails()
        switch kind {
        case .synonyms:
            d.synonyms.removeAll { $0.lowercased() == text.lowercased() }
            d.synonyms.insert(text, at: 0)
        case .antonyms:
            d.antonyms.removeAll { $0.lowercased() == text.lowercased() }
            d.antonyms.insert(text, at: 0)
        }
        withAnimation(.strongEaseOut(0.3)) { details = d }
        word.details = d
        try? context.save()
    }

    /// Words linked to this one that the synonym and antonym pages don't already show:
    /// added from either page, or naming this word in their own relations.
    private func linkedWords(shown: Set<String>) -> [Word] {
        let me = word.text.lowercased()
        let mentioning = saved.filter { other in
            guard let d = other.details else { return false }
            return (d.synonyms + d.antonyms + d.family).contains { $0.lowercased() == me }
        }
        var seen: Set<String> = [me]
        return (word.linked + mentioning).filter { w in
            let key = w.text.lowercased()
            return !shown.contains(key) && seen.insert(key).inserted
        }
    }

    /// The first `n` sentences of the first paragraph, so a long etymology or usage note
    /// fits one screen.
    private func firstSentences(_ text: String, _ n: Int) -> String {
        let firstParagraph = text.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = firstParagraph
        var out: [String] = []
        tokenizer.enumerateTokens(in: firstParagraph.startIndex..<firstParagraph.endIndex) { range, _ in
            out.append(firstParagraph[range].trimmingCharacters(in: .whitespacesAndNewlines))
            return out.count < n
        }
        return out.joined(separator: " ")
    }

    // MARK: Loading

    /// Starts the card for a held word and looks the word up while it forms. The word
    /// is saved once both the senses are in and the card has landed (`commit`).
    private func add(_ text: String) {
        guard job == nil, !adding.contains(text) else { return }
        adding.insert(text)
        addError = nil
        fetched = nil
        landed = false
        holdCount += 1
        let new = GenerateJob(tag: PillTag(kind: .word, payload: text), hostWord: word.text)
        job = new
        Task {
            do {
                let senses = try await Wiktionary.lookup(text)
                // The definition arrives while the card is still soft.
                if job?.id == new.id, let sense = SenseRanker.primary(senses, tags: nil) {
                    job?.body = sense.definition
                }
                fetched = senses
                commit(text)
            } catch {
                adding.remove(text)
                if job?.id == new.id { withAnimation(.strongEaseOut(0.2)) { job = nil } }
                addError = "Couldn't add “\(text)”. \(error.localizedDescription)"
                failCount += 1
            }
        }
    }

    /// Saves the held word and links it to this one, once its card has landed and its
    /// senses are in, whichever comes last. Its outlined pill turns into a saved one
    /// underneath the leaving card.
    private func commit(_ text: String) {
        guard landed, let senses = fetched else { return }
        fetched = nil
        let existing = saved.first { $0.text.lowercased() == text.lowercased() }
        let added = existing ?? Word(text: text, senses: senses)
        withAnimation(.strongEaseOut(0.3)) {
            if existing == nil { context.insert(added) }
            if !word.linked.contains(where: { $0 === added }) { word.linksOut.append(added) }
            adding.remove(text)
        }
        do {
            try context.save()
            savedCount += 1
            // The toast follows the card off the page; if the card has already gone, now.
            if job == nil { toaster.show("Word added") } else { toastPending = true }
        } catch {
            addError = "Couldn't add “\(text)”. \(error.localizedDescription)"
            failCount += 1
        }
    }

    private func loadDetails() async {
        defer { ranked = SenseRanker.rank(word.senses, tags: details?.senseTags) }
        // Details saved before sense labels existed are fetched again, once.
        if let saved = word.details, saved.senseTags != nil { details = saved; return }
        details = word.details
        guard let fetched = try? await Wiktionary.details(for: word.text) else { return }
        details = fetched
        word.details = fetched
        try? context.save()
    }

    private func writeMnemonic() {
        let explainer = Engine.resolve(Engine(rawValue: engineRaw) ?? .automatic, groqKey: groqKey, groqModel: groqModel)
        let text = word.text, facts = word.facts
        let question = """
        Write one short, vivid mnemonic that ties the sound or parts of "\(text)" to its main meaning. \
        One or two sentences, no preamble.
        """
        writingMnemonic = true
        mnemonicError = nil
        Task {
            defer { writingMnemonic = false }
            do {
                var result = ""
                for try await partial in explainer.answer(word: text, facts: facts, question: question) {
                    result = partial
                }
                // The template engine has no model; it can only echo the dictionary.
                guard !(explainer is TemplateExplainer) else {
                    mnemonicError = "Turn on an AI model in Settings to write a mnemonic."
                    return
                }
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                withAnimation(.strongEaseOut(0.3)) { mnemonic = trimmed }
                word.mnemonic = trimmed
                try? context.save()
            } catch {
                mnemonicError = error.localizedDescription
            }
        }
    }
}

/// A chunk coming or going: it rises into focus from below and rises out of focus above
/// when moving forward, and the mirror image when moving back.
private struct ChunkMove: Transition {
    let forward: Bool
    func body(content: Content, phase: TransitionPhase) -> some View {
        let rise: CGFloat = forward ? 18 : -18
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 8)
            .offset(y: phase == .willAppear ? rise : phase == .didDisappear ? -rise : 0)
    }
}

/// A related word that isn't saved yet: outlined, with a plus. Holding it fills it in from
/// the left, linearly over the hold, into the filled look of a saved word, so the gesture
/// shows its own progress. The phone fills with it: a rumble and a run of ticks that both
/// build as the pill fills (`FillHaptics`), cut the moment you let go. Letting go early drains the fill quickly (slow where you are
/// deciding, fast where the app answers). A tap just flickers the fill, which hints at
/// the hold. Once full, it stays filled and pressed while its card is made.
private struct HoldToAdd: View {
    let text: String
    let busy: Bool
    /// The detail page's size: card type in a 60 pt pill (`BigPill`).
    var big = false
    let onAdd: () -> Void

    @State private var progress: CGFloat = 0
    @State private var pressing = false
    private static let hold = 1.0

    var body: some View {
        let down = pressing || busy
        label(ink: .ink3, icon: .ink4)
            .overlay { Capsule().strokeBorder(Theme.control, lineWidth: big ? BigPill.stroke : 1.5) }
            .overlay {
                label(ink: .ink, icon: .ink2)
                    .background(Theme.control, in: Capsule())
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: busy ? 1 : progress, anchor: .leading)
                    }
            }
            .contentShape(Capsule())
            .scaleEffect(down ? (big ? 0.97 : 0.95) : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: down)
            .onLongPressGesture(minimumDuration: Self.hold, maximumDistance: 12) {
                onAdd()
            } onPressingChanged: { isDown in
                pressing = isDown
                if isDown {
                    withAnimation(.linear(duration: Self.hold)) { progress = 1 }
                    FillHaptics.shared.start(duration: Self.hold)
                } else {
                    withAnimation(.strongEaseOut(0.2)) { progress = 0 }
                    FillHaptics.shared.stop()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityHint("Hold to add to Vocab")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Add to Vocab") { onAdd() }
    }

    private func label(ink: Color, icon: Color) -> some View {
        HStack(spacing: big ? 8 : 5) {
            Image(systemName: "plus").font(.system(size: big ? 20 : 11, weight: .bold)).foregroundStyle(icon)
            Text(text).lineLimit(1).minimumScaleFactor(big ? 0.5 : 1)
        }
        .font(big ? Theme.detailDefinitionFont : .subheadline.weight(.medium))
        .foregroundStyle(ink)
        .padding(.leading, big ? 20 : 11)
        .padding(.trailing, big ? 24 : 14)
        .frame(height: big ? BigPill.height : 36)
    }
}

/// The feel of a pill filling under your finger: a soft rumble that swells, with ticks
/// riding on it that come harder as it fills, so the hold can be felt as well as seen.
/// It skips its first 80 ms, where a touch that is really the start of a scroll gets
/// cancelled, so brushing past words while scrolling stays silent. Does nothing on
/// hardware without haptics.
@MainActor
final class FillHaptics {
    static let shared = FillHaptics()
    private let engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var pending: Task<Void, Never>?
    private static let lead = 0.08

    private init() {
        engine = CHHapticEngine.capabilitiesForHardware().supportsHaptics ? try? CHHapticEngine() : nil
        engine?.isAutoShutdownEnabled = true
    }

    func start(duration: Double) {
        stop()
        guard engine != nil else { return }
        pending = Task {
            try? await Task.sleep(for: .seconds(Self.lead))
            guard !Task.isCancelled else { return }
            play(duration - Self.lead)
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    private func play(_ d: Double) {
        guard let engine, d > 0 else { return }
        var events = [CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
        ], relativeTime: 0, duration: d)]
        // Ticks every 120 ms, climbing in strength and crispness.
        let ticks = Int(d / 0.12)
        for i in 0..<ticks {
            let f = Float(i) / Float(max(ticks - 1, 1))
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55 + 0.35 * f),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35 + 0.4 * f),
            ], relativeTime: Double(i) * 0.12))
        }
        // The rumble swells from clearly there to full.
        let swell = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.45),
            .init(relativeTime: d, value: 1),
        ], relativeTime: 0)
        do {
            try engine.start()
            let p = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: events, parameterCurves: [swell]))
            try p.start(atTime: CHHapticTimeImmediate)
            player = p
        } catch {
            player = nil
        }
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil
    private var rowGap: CGFloat { lineSpacing ?? spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowGap * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                // Centred in the row, so plain words line up with the pills beside them.
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowGap
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// The detail page's word pills: the card's 32 pt type in a 60 pt capsule.
private enum BigPill {
    static let height: CGFloat = 60
    static let stroke: CGFloat = 2
}

/// A sideways swipe that only starts on a horizontal move. Vertical drags never begin it,
/// so the zoom transition's drag down to close keeps working.
private struct SidewaysSwipe: UIGestureRecognizerRepresentable {
    var onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        if pan.state == .ended {
            onEnded(pan.translation(in: nil).x, pan.velocity(in: nil).x)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: nil)
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

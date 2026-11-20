import SwiftUI
import SwiftData

struct AskView: View {
    let word: Word
    /// Pull-down to close: called with the finger's vertical travel while the
    /// panel owns the drag, then once on release with travel and velocity.
    var onPull: ((CGFloat) -> Void)? = nil
    var onPullEnd: ((_ translation: CGFloat, _ velocity: CGFloat) -> Void)? = nil
    /// Closes Ask AI (pull down or tap the peeking card; no on-screen button).
    var onClose: (() -> Void)? = nil
    /// The panel has committed open. The opening questions wait for this, so a
    /// half-pulled card shows an empty panel and they arrive as it settles.
    var revealed = true

    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("groqKey") private var groqKey = ""
    @AppStorage("groqModel") private var groqModel = GroqExplainer.defaultModel

    @State private var question = ""
    @State private var asked: String?
    /// The answer, word by word, each with the moment it starts to fade in.
    @State private var tokens: [RevealToken] = []
    /// When the last word finishes appearing.
    @State private var revealEnd = Date.distantPast
    @State private var error: String?
    /// The suggestions are leaving; each row runs its own delayed exit off this flag.
    @State private var exiting = false
    /// The suggestion that was tapped, which leaves last.
    @State private var tapped: String?
    /// A previous question and answer are fading out before the next one arrives.
    @State private var contentOut = false
    /// The follow-ups are leaving as a wave, tapped one last.
    @State private var followUpsLeaving = false
    /// The question has settled and the model still hasn't sent a word.
    @State private var waiting = false
    /// Light tap on every ask, matching the deck's gestures.
    @State private var askCount = 0
    /// Pills tapped in the current answer (untapped ones are `.new`, or `.added` if in the deck).
    @State private var pillStates: [String: PillState] = [:]
    /// The card being made from a tapped pill, shown above the composer.
    @State private var job: GenerateJob?
    /// Success tap when a card lands.
    @State private var landedCount = 0
    /// The panel's top edge on screen; the forming card's stage reaches up by this much.
    @State private var stageLift: CGFloat = 0
    /// Every saved word, so pills for words already in the deck show as added.
    @Query private var deck: [Word]
    /// Follow-up suggestions above the composer, shown once an answer has fully appeared.
    @State private var showSuggestions = false
    /// How many opening questions have arrived, top down.
    @State private var presetsIn = 0
    /// Steps the opening questions in, or clears them once the panel has closed.
    @State private var arrival: Task<Void, Never>?
    /// Sequences the exit, the question's entrance and the answer.
    @State private var choreo: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    /// The answer is scrolled to its top, so a downward drag can close instead of scroll.
    @State private var atTop = true
    /// Global bottom edge of the scrolling area; touches below it start in the composer.
    @State private var scrollBottom: CGFloat = 0
    /// Who owns the current drag: nil until decided, true = closing, false = scrolling.
    @State private var pulling: Bool?

    private let presets = [
        "How would I use it in conversation?",
        "How is it different from its closest synonyms?",
        "Give me three sentences that use it well.",
        "Quiz me on it.",
    ]

    @State private var dictation = Dictation()
    /// What was typed before dictation started; the transcript is appended to it.
    @State private var dictationBase = ""

    private var engine: Engine { Engine(rawValue: engineRaw) ?? .automatic }

    private var explainer: any Explainer {
        Engine.resolve(engine, groqKey: groqKey, groqModel: groqModel)
    }

    /// Short name for the model pill, e.g. "Apple Intelligence (auto)".
    private var modelName: String {
        let name = switch explainer {
        case is AppleExplainer: "Apple Intelligence"
        case let cloud as GroqExplainer:
            // "openai/gpt-oss-120b" -> "gpt-oss-120b"
            String(cloud.model.split(separator: "/").last ?? "")
        default: "Dictionary"
        }
        return engine == .automatic ? "\(name) (auto)" : name
    }

    private var canSend: Bool { !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let asked {
                        VStack(alignment: .leading, spacing: 44) {
                        VStack(alignment: .leading, spacing: 28) {
                            Text(asked)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(asked)
                                // Leaves instantly: by then it is already faded out.
                                .transition(.asymmetric(insertion: reduceMotion ? .opacity : .riseIn,
                                                        removal: .identity))

                            // Shimmer and answer share one spot, so swapping them never shifts layout.
                            ZStack(alignment: .topLeading) {
                                if let error {
                                    Text(error).foregroundStyle(.red)
                                } else if !tokens.isEmpty {
                                    StreamingAnswer(tokens: tokens, highlight: word.text, pills: pillContext)
                                        // A fresh view per question: the words animate themselves,
                                        // so no outer animation may crossfade old text into new.
                                        .id(asked)
                                        .transaction { $0.animation = nil }
                                } else if waiting {
                                    ThinkingLines()
                                        .transition(.blurFade)
                                }
                            }
                        }
                        .opacity(contentOut ? 0 : 1)
                        .blur(radius: contentOut && !reduceMotion ? 10 : 0)

                            if showSuggestions {
                                FollowUps(items: presets.filter { $0 != asked }, leaving: followUpsLeaving,
                                          tapped: tapped) { ask($0) }
                            }
                        }
                        // Inset past the question's edge so the answer sits inside the card.
                        .padding(.horizontal, 12)
                    }

                    if asked == nil {
                        presetList.padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Short content stays still, so pulling it reads as moving the panel.
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollDisabled(pulling == true)
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y + $0.contentInsets.top <= 1
            } action: { _, top in atTop = top }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { scrollBottom = $0 }
            // Text scrolling toward the composer fades out instead of being cut off at an edge.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Theme.page.opacity(0), Theme.page], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
                    .allowsHitTesting(false)
            }
            // Same at the top, but only once scrolled, so the question isn't faded at rest.
            .overlay(alignment: .top) {
                LinearGradient(colors: [Theme.page, Theme.page.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
                    .opacity(atTop ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: atTop)
                    .allowsHitTesting(false)
            }
            composer
                .padding(.horizontal, 16)
        }
        .background(Theme.page.ignoresSafeArea(edges: .bottom))
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { stageLift = $0 }
        // A tapped pill's card forms over the whole screen. The panel sits below the parked
        // deck card, so the stage reaches up past its own top edge to cover that card too.
        // It runs its own entrance and exit, so it is added and removed without animation.
        .overlay {
            if let job {
                GenerateStage(job: job,
                              onLanded: {
                                  pillStates[job.tag.id] = .added
                                  landedCount += 1
                              },
                              onDone: { self.job = nil })
                    .id(job.id)
                    .padding(.top, -stageLift)
            }
        }
        // While a card forms, a drag on the scrim must not pull the panel closed.
        .simultaneousGesture(pullGesture, including: onPull == nil ? .none : job == nil ? .all : .subviews)
        .accessibilityAction(named: "Close Ask AI") { onClose?() }
        .onChange(of: dictation.transcript) { _, t in
            question = dictationBase.isEmpty ? t : dictationBase + " " + t
        }
        .sensoryFeedback(.impact(weight: .light), trigger: askCount)
        .sensoryFeedback(.success, trigger: landedCount)
        .onDisappear { task?.cancel(); choreo?.cancel(); arrival?.cancel(); dictation.stop() }
        .onChange(of: revealed, initial: true) { _, open in
            stagePresets(open)
            // Closing Ask drops a card still forming; its pill can be tapped again.
            if !open, let job {
                if pillStates[job.tag.id] == .generating { pillStates[job.tag.id] = nil }
                self.job = nil
            }
        }
        // Builds the forming card's GPU pipelines before the first pill can be tapped.
        .overlay(alignment: .topLeading) { if revealed { FormingWarmup() } }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-cycleEngine") {
                for e in [Engine.templates, .automatic, .templates] {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.spring(duration: 0.4, bounce: 0)) { engineRaw = e.rawValue }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                // `-askPreset N` picks which default question the demo asks.
                ask(presets[min(presets.count - 1, UserDefaults.standard.string(forKey: "askPreset").flatMap { Int($0) } ?? 1)])
                // Then tap a follow-up, to check the re-ask path.
                if ProcessInfo.processInfo.arguments.contains("-followUp") {
                    try? await Task.sleep(for: .seconds(7))
                    ask(presets[2])
                }
            }
            #endif
        }
    }

    private var presetList: some View {
        VStack(spacing: 26) {
            ForEach(Array(presets.enumerated()), id: \.element) { i, p in
                let exit = exitMotion(for: i)
                let rise = Self.arrivalRise[min(i, 3)]
                Button { ask(p) } label: {
                    Text(p)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                // The tapped row stays pressed instead of springing back before it leaves.
                .buttonStyle(PressStyle(held: exiting && p == tapped))
                // Arrival is driven by `stagePresets`; the exit wave below has its own animation.
                .opacity(i < presetsIn ? 1 : 0)
                .blur(radius: i < presetsIn || reduceMotion ? 0 : 6)
                .offset(y: i < presetsIn || reduceMotion ? 0 : rise)
                .allowsHitTesting(i < presetsIn)
                .opacity(exiting ? 0 : 1)
                .blur(radius: exiting ? exit.blur : 0)
                .scaleEffect(exiting ? exit.scale : 1)
                .offset(y: exiting ? exit.drift : 0)
                .animation(.strongEaseOut(exit.duration).delay(exit.delay), value: exiting)
            }
        }
        .padding(.horizontal, 20)
        .allowsHitTesting(!exiting)
    }

    /// When each opening question starts, measured from the swipe's commit. The first
    /// lands as the card is settling into its park (0.45s spring); gaps tighten so
    /// the four read as one wave, and every start is in by ~0.33s.
    private static let arrivalStarts: [Double] = [0.16, 0.23, 0.29, 0.33]
    /// The first question travels furthest; the rest follow with less.
    private static let arrivalRise: [CGFloat] = [14, 11, 9, 8]

    /// Opening: questions step in top down, each with its own spring, so later
    /// rows keep moving while earlier ones settle. Closing: nothing animates; the
    /// panel is fading with the card, and the rows clear once it is out of sight
    /// so the next open starts from empty. Reopening mid-close cancels the clear.
    private func stagePresets(_ open: Bool) {
        arrival?.cancel()
        if open {
            guard presetsIn < presets.count else { return }
            if reduceMotion {
                arrival = Task {
                    try? await Task.sleep(for: .seconds(0.15))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) { presetsIn = presets.count }
                }
                return
            }
            let start = Date.now
            let from = presetsIn
            arrival = Task {
                for i in from..<presets.count {
                    let wait = Self.arrivalStarts[min(i, 3)] - Date.now.timeIntervalSince(start)
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(duration: 0.55, bounce: 0)) { presetsIn = i + 1 }
                }
            }
        } else {
            arrival = Task {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                var plain = Transaction()
                plain.disablesAnimations = true
                withTransaction(plain) { presetsIn = 0 }
            }
        }
    }

    private struct ExitMotion {
        var delay: Double, duration: Double, drift: CGFloat, blur: CGFloat, scale: CGFloat
    }

    /// Gaps between the other rows shrink as the wave spreads.
    private static let waveDelays: [Double] = [0, 0.08, 0.15, 0.20]

    /// The rows nearest the tapped one leave first, drifting away from it, so the
    /// wave starts where the finger was. The tapped row leaves last and stays put.
    /// A typed question has no tapped row; the wave just runs top to bottom.
    private func exitMotion(for i: Int) -> ExitMotion {
        if reduceMotion { return ExitMotion(delay: 0, duration: 0.25, drift: 0, blur: 0, scale: 1) }
        guard let tapped, let t = presets.firstIndex(of: tapped) else {
            return ExitMotion(delay: Self.waveDelays[min(i, 3)], duration: 0.4, drift: -12, blur: 5, scale: 1)
        }
        if i == t {
            let last = Self.waveDelays[min(presets.count - 2, 3)]
            return ExitMotion(delay: last + 0.16, duration: 0.42, drift: 0, blur: 7, scale: 0.98)
        }
        let rank = presets.indices.filter { $0 != t }
            .sorted { (abs($0 - t), $0) < (abs($1 - t), $1) }
            .firstIndex(of: i) ?? 0
        return ExitMotion(delay: Self.waveDelays[min(rank, 3)], duration: 0.4,
                          drift: i < t ? -14 : 14, blur: 5, scale: 1)
    }

    /// A floating box: the question on top, the model pill and buttons along its bottom edge.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("", text: $question,
                      prompt: Text("Ask anything…").foregroundStyle(.ink4),
                      axis: .vertical)
                .focused($focused)
                .font(.body)
                .lineLimit(1...5)
                .onSubmit { ask(question) }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The whole text area focuses the field, not just the line of text.
                .contentShape(Rectangle())
                .onTapGesture { focused = true }

            if let error = dictation.error {
                Text(error).font(.footnote).foregroundStyle(.ink3).padding(.horizontal, 8)
            }

            HStack(spacing: 12) {
                // The pill is drawn as a plain view so its width animates with the
                // label; a Menu's own label is hosted by the system and snaps in size.
                // An invisible Menu on top takes the taps.
                HStack(spacing: 6) {
                    // An invisible copy sets the width, which springs to the new name;
                    // the visible names swap on top of it: the old one blurs out fast,
                    // the new one blurs in as the pill settles.
                    Text(modelName)
                        .lineLimit(1)
                        .hidden()
                        .overlay(alignment: .leading) {
                            ZStack(alignment: .leading) {
                                Text(modelName)
                                    .lineLimit(1)
                                    .id(modelName)
                                    .transition(.asymmetric(
                                        insertion: .blurFade.animation(.strongEaseOut(0.3).delay(0.1)),
                                        removal: .blurFade.animation(.strongEaseOut(0.15))))
                            }
                        }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.ink3)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Theme.control, in: Capsule())
                // Nothing spills past the pill while the text changes.
                .clipShape(Capsule())
                // Text, chevron and capsule resize as one shape.
                .geometryGroup()
                .overlay {
                    Menu {
                        // One spring for the whole switch, so the pill and its label change together.
                        Picker("Model", selection: $engineRaw.animation(.spring(duration: 0.4, bounce: 0))) {
                            ForEach(Engine.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Capsule())
                    }
                    .tint(.primary)
                }
                .accessibilityLabel("Model, \(modelName)")

                Spacer(minLength: 0)

                Button {
                    if !dictation.isRecording { dictationBase = question.trimmingCharacters(in: .whitespaces) }
                    Task { await dictation.toggle() }
                } label: {
                    Image(systemName: dictation.isRecording ? "waveform" : "mic")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 38, height: 38)
                        .background(Theme.control, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Dictate")

                Button { ask(question) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? Theme.page : Color.ink4)
                        .frame(width: 38, height: 38)
                        .background(canSend ? Color.ink : Theme.control, in: Circle())
                        .animation(.easeOut(duration: 0.15), value: canSend)
                }
                .buttonStyle(PressStyle())
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.top, 14)
        .padding([.horizontal, .bottom], 12)
        .background(Theme.sheet, in: Theme.cardShape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.08), radius: 18, y: 6)
        // Lifted off the bottom edge so it reads as floating.
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Decides ownership once, on the first movement, and never hands off mid-gesture:
    /// scrolling up to the top and continuing to pull must not close the card by accident.
    /// Global space, because the panel moves with the finger.
    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { v in
                if pulling == nil {
                    let t = v.translation
                    let downward = t.height > 0 && t.height > abs(t.width)
                    let inComposer = v.startLocation.y > scrollBottom
                    pulling = downward && (atTop || inComposer)
                }
                if pulling == true { onPull?(v.translation.height) }
            }
            .onEnded { v in
                if pulling == true { onPullEnd?(v.translation.height, v.velocity.height) }
                pulling = nil
            }
    }

    private var pillContext: PillContext {
        let inDeck = Set(deck.map { $0.text.lowercased() })
        return PillContext(
            state: { tag in
                pillStates[tag.id] ?? (tag.kind == .word && inDeck.contains(tag.payload.lowercased()) ? .added : .new)
            },
            onTap: { tapPill($0) })
    }

    /// Makes the pill's card in place. Template mode only previews it: nothing is
    /// saved to the deck or the word's detail page.
    private func tapPill(_ tag: PillTag) {
        guard job == nil, (pillStates[tag.id] ?? .new) == .new else { return }
        pillStates[tag.id] = .generating
        let new = GenerateJob(tag: tag, hostWord: word.text)
        job = new
        guard tag.kind == .word else { return }
        // The definition arrives while the card is still a blur.
        Task {
            guard let senses = try? await Wiktionary.lookup(tag.payload), job?.id == new.id,
                  let sense = SenseRanker.primary(senses, tags: nil) else { return }
            job?.body = sense.definition
        }
    }

    private func ask(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askCount += 1
        arrival?.cancel()
        // A new answer brings its own pills.
        pillStates = [:]
        job = nil
        task?.cancel()
        choreo?.cancel()
        dictation.stop()
        question = ""
        dictationBase = ""
        focused = false

        // Start the model now; the choreography only decides when its words may show.
        let fromPresets = asked == nil
        // Either wave is visibly gone by ~0.75s (strong ease-out); the question starts as
        // the tapped row's tail fades, leaving only a short beat of empty space.
        let exitTime = reduceMotion ? 0.25 : 0.85
        // The answer waits until the question has settled (0.65s), so the two never arrive together.
        let floor = Date.now.addingTimeInterval(exitTime + (reduceMotion ? 0 : 0.65))
        var pending: [RevealToken] = []
        var entered = false

        choreo = Task {
            // 1. Everything on screen leaves: a wave through the suggestions with the
            //    tapped one last, or the previous answer all at once.
            tapped = presets.contains(q) ? q : nil
            if fromPresets {
                exiting = true
            } else {
                withAnimation(.strongEaseOut(0.45)) { contentOut = true }
                followUpsLeaving = true
            }
            try? await Task.sleep(for: .seconds(exitTime))
            guard !Task.isCancelled else { return }

            // 2. The question rises in at the top, left-aligned. The old content is
            //    cleared without animation while it is invisible, so nothing from the
            //    previous answer can ghost back in during the entrance.
            var plain = Transaction()
            plain.disablesAnimations = true
            withTransaction(plain) {
                tokens = []
                error = nil
                showSuggestions = false
                followUpsLeaving = false
                waiting = false
            }
            withAnimation(reduceMotion ? .easeOut(duration: 0.35) : .spring(duration: 0.65, bounce: 0)) {
                asked = q
            }
            // The question carries its own entrance; the container just switches back on.
            // An answer that is already here (templates, a fast model) streams in word by
            // word rather than fading in as one block.
            withTransaction(plain) {
                contentOut = false
                tokens = pending
            }
            entered = true

            // 3. If the model is still working once the question settles, say so quietly.
            try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.65))
            guard !Task.isCancelled, tokens.isEmpty, error == nil else { return }
            withAnimation(.strongEaseOut(0.5)) { waiting = true }
        }

        // 3. Words queue up behind the question's entrance, then stream in.
        let explainer = self.explainer
        let word = word.text, facts = self.word.facts
        let senses = self.word.senses, details = self.word.details
        task = Task {
            do {
                #if DEBUG
                // Simulates a slow model, to check the thinking state.
                if ProcessInfo.processInfo.arguments.contains("-slowAI") { try await Task.sleep(for: .seconds(3)) }
                #endif
                var shown = ""
                // Templates answer the default questions from the dictionary, with pills.
                let source = await TemplateAnswers.stream(explainer, word: word, facts: facts, senses: senses,
                                                          details: details, question: q)
                for try await partial in source {
                    var list = entered ? tokens : pending
                    if partial.hasPrefix(shown) {
                        list += RevealToken.schedule(String(partial.dropFirst(shown.count)),
                                                     after: max(floor, list.last?.born ?? floor),
                                                     instant: reduceMotion)
                    } else {
                        // The model revised earlier text; show the new snapshot as a whole.
                        list = RevealToken.schedule(partial, after: max(floor, .now), instant: true)
                    }
                    shown = partial
                    if entered {
                        // The shimmer dissolves as the first words arrive in its place.
                        if waiting { withAnimation(.strongEaseOut(0.4)) { waiting = false } }
                        tokens = list
                    } else { pending = list }
                    revealEnd = (list.last?.born ?? .now).addingTimeInterval(StreamingAnswer.duration)
                }
                // 4. Once the last word lands, follow-ups rise in under the answer.
                try await Task.sleep(for: .seconds(max(0, revealEnd.timeIntervalSinceNow) + 0.15))
                showSuggestions = true
            } catch is CancellationError {
            } catch {
                await choreo?.value
                self.error = error.localizedDescription
                waiting = false
            }
        }
    }
}

/// Follow-up questions under a finished answer: a quiet label and plain rows, no
/// dividers or icons. They rise out of a blur in a short, tightening stagger.
private struct FollowUps: View {
    let items: [String]
    /// Leaving as a wave: the label and untapped rows first, the tapped row last.
    var leaving = false
    var tapped: String?
    let onTap: (String) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let delays: [Double] = [0, 0.08, 0.14, 0.18]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Follow up")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink4)
                .padding(.bottom, 4)
                .modifier(Arrive(on: appeared, delay: 0, reduceMotion: reduceMotion))
                .modifier(Leave(on: leaving, delay: 0, scale: 1, reduceMotion: reduceMotion))

            ForEach(Array(items.enumerated()), id: \.element) { i, p in
                let isTapped = p == tapped
                Button { onTap(p) } label: {
                    Text(p)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.ink3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(held: leaving && isTapped))
                .modifier(Arrive(on: appeared, delay: Self.delays[min(i, 3)] + 0.04, reduceMotion: reduceMotion))
                .modifier(Leave(on: leaving,
                                delay: isTapped ? 0.36 : Self.delays[min(i, 3)] + 0.04,
                                scale: isTapped ? 0.98 : 1,
                                reduceMotion: reduceMotion))
            }
        }
        .allowsHitTesting(!leaving)
        .onAppear { appeared = true }
    }
}

/// Fade and blur out where it stands; matches the suggestion wave.
private struct Leave: ViewModifier {
    let on: Bool
    let delay: Double
    let scale: CGFloat
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0 : 1)
            .blur(radius: on && !reduceMotion ? 6 : 0)
            .scaleEffect(on && !reduceMotion ? scale : 1, anchor: .leading)
            .animation(.strongEaseOut(reduceMotion ? 0.25 : 0.42).delay(reduceMotion ? 0 : delay), value: on)
    }
}

/// Where the answer will be: soft lines with a light sweeping across them,
/// shown only while the model is still working.
struct ThinkingLines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let widths: [CGFloat] = [1, 0.9, 0.55]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            // One sweep every 1.6s, left to right.
            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            VStack(alignment: .leading, spacing: 16) {
                ForEach(widths.indices, id: \.self) { i in
                    GeometryReader { geo in
                        Capsule()
                            .fill(Theme.control)
                            .overlay {
                                if !reduceMotion {
                                    LinearGradient(colors: [.clear, Color.ink.opacity(0.07), .clear],
                                                   startPoint: .leading, endPoint: .trailing)
                                        .frame(width: geo.size.width * 0.5)
                                        .offset(x: (phase * 2 - 0.5) * geo.size.width)
                                }
                            }
                            .clipShape(Capsule())
                            .frame(width: geo.size.width * widths[i])
                    }
                    .frame(height: 12)
                }
            }
            .padding(.top, 6)
        }
        .accessibilityLabel("Thinking")
    }
}

extension AnyTransition {
    /// Dissolve with a soft blur, used where one thing gives way to another in place.
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(on: false), identity: BlurFade(on: true))
    }
}

private struct BlurFade: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content.opacity(on ? 1 : 0).blur(radius: on ? 0 : 6)
    }
}

/// Fade, un-blur and rise into place.
struct Arrive: ViewModifier {
    let on: Bool
    let delay: Double
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on || reduceMotion ? 0 : 8)
            .offset(y: on || reduceMotion ? 0 : 10)
            .animation(.spring(duration: 0.6, bounce: 0).delay(reduceMotion ? 0 : delay), value: on)
    }
}

extension Animation {
    /// Strong ease-out: moves at once and settles long, so exits start without hesitation.
    static func strongEaseOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
}

/// The question's entrance: rises 24 pt and settles (a spring with a little give, so it
/// lands ~2–3 pt high and eases back) while coming into focus. Focus and movement are
/// timed apart: only the movement bounces, so the blur and fade can't overshoot.
struct RiseIn: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .animation(.strongEaseOut(0.45)) {
                $0.opacity(shown ? 1 : 0).blur(radius: shown ? 0 : 8)
            }
            .animation(.spring(duration: 0.65, bounce: 0.18)) {
                $0.offset(y: shown ? 0 : 24)
            }
    }
}

extension AnyTransition {
    static var riseIn: AnyTransition {
        .modifier(active: RiseIn(shown: false), identity: RiseIn(shown: true))
    }
}

// MARK: - Streaming answer

/// One word of an answer (with its trailing space) and when it starts to appear.
struct RevealToken {
    let text: String
    let born: Date

    /// Splits newly arrived text into words and gives each its own entrance at a
    /// steady reading pace, so an answer that arrives all at once (cloud, dictionary)
    /// still streams in. The pace only quickens for very long answers, so the
    /// reveal never runs past about three and a half seconds.
    static func schedule(_ text: String, after start: Date, instant: Bool) -> [RevealToken] {
        var words: [String] = []
        var current = ""
        for ch in text {
            if !ch.isWhitespace, let last = current.last, last.isWhitespace {
                words.append(current)
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty { words.append(current) }
        guard !words.isEmpty else { return [] }

        let begin = max(start, .now)
        let step = instant ? 0 : max(0.01, min(0.02, 3.5 / Double(words.count)))
        return words.enumerated().map { i, w in
            RevealToken(text: w, born: begin.addingTimeInterval(Double(i + 1) * step))
        }
    }
}

private struct SelectableWhen: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.textSelection(.enabled) } else { content }
    }
}

/// When a run of answer text starts to appear. Also read by `PillOverlay`.
nonisolated struct BornAt: TextAttribute {
    let date: Date
}

/// Lays the whole answer out at once (so lines never reflow) and fades each word
/// in place with a small rise. Words that have finished appearing render as plain text.
/// Each line of the answer is its own block, so sentences and list items get a gap.
struct StreamingAnswer: View {
    let tokens: [RevealToken]
    /// The word being studied; every use of it is drawn in full ink.
    var highlight: String = ""
    /// Live pills for `[[word]]` and `{{add}}` markup; nil leaves their spots empty.
    var pills: PillContext? = nil
    static let duration: TimeInterval = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped once the last word settles, to stop the timeline.
    @State private var settledAt = Date.distantPast

    private var end: Date { (tokens.last?.born ?? .distantPast).addingTimeInterval(Self.duration) }

    var body: some View {
        let parsed = AnswerFormat.parse(tokens, highlight: highlight)
        TimelineView(.animation(paused: settledAt >= end)) { ctx in
            let blocks = AnswerFormat.render(parsed, settledBefore: ctx.date.addingTimeInterval(-Self.duration))
            VStack(alignment: .leading, spacing: 26) {
                ForEach(blocks.indices, id: \.self) { i in
                    let b = blocks[i]
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let marker = b.marker { marker.frame(minWidth: 14, alignment: .leading) }
                        b.text
                    }
                    .padding(.top, b.isHeading && i > 0 ? 6 : 0)
                }
            }
            .font(.system(size: 22, weight: .medium))
            .lineSpacing(5)
            .foregroundStyle(.ink2)
            .textRenderer(RevealRenderer(now: ctx.date, rise: reduceMotion ? 0 : 6))
            .frame(maxWidth: .infinity, alignment: .leading)
            // Pills are real buttons laid over the spots reserved for them in the text.
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                if let pills { PillOverlay(layouts: layouts, now: ctx.date, context: pills) }
            }
        }
        // Selectable text is drawn by the system and ignores the renderer, so
        // selection only switches on once every word has appeared.
        .modifier(SelectableWhen(on: settledAt >= end))
        .task(id: end) {
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            settledAt = end
        }
    }
}

/// Turns the model's text into styled blocks: strips markdown markers (headings,
/// bullets, **bold**, *italic*, `code`) and keeps each character's entrance time.
enum AnswerFormat {
    struct Block {
        var marker: Text?
        var text: Text
        var isHeading = false
    }

    /// A line of the answer with markdown resolved; parsed once per change of the
    /// answer, not once per frame.
    struct Parsed {
        fileprivate var marker: String?
        fileprivate var markerBorn: Date?
        fileprivate var glyphs: [Glyph]
        var isHeading: Bool
    }

    fileprivate struct Glyph {
        var ch: Character
        var born: Date?
        var bold = false
        var italic = false
        var ink = false
        /// A `[[word]]` or `{{add}}` pill, drawn as one reserved spot.
        var pill: PillTag?
    }

    /// Per frame: words that have finished appearing lose their timing, so they
    /// merge into plain runs and the renderer draws them without work.
    static func render(_ parsed: [Parsed], settledBefore cutoff: Date) -> [Block] {
        parsed.map { p in
            let glyphs = p.glyphs.map { g -> Glyph in
                var g = g
                if let b = g.born, b <= cutoff { g.born = nil }
                return g
            }
            let markerBorn = p.markerBorn.flatMap { $0 <= cutoff ? nil : $0 }
            return Block(marker: p.marker.map { styled(Text($0), born: markerBorn) },
                         text: join(glyphs), isHeading: p.isHeading)
        }
    }

    static func parse(_ tokens: [RevealToken], highlight: String) -> [Parsed] {
        var chars: [Character] = []
        var born: [Date?] = []
        for t in tokens {
            for ch in t.text { chars.append(ch); born.append(t.born) }
        }
        let pattern = highlightPattern(highlight)

        var blocks: [Parsed] = []
        var start = 0
        while start < chars.count {
            var end = start
            while end < chars.count, chars[end] != "\n" { end += 1 }
            if let block = block(chars, born, start..<end, pattern) { blocks.append(block) }
            start = end + 1
        }
        return blocks
    }

    private static func block(_ chars: [Character], _ born: [Date?], _ range: Range<Int>,
                              _ pattern: Regex<AnyRegexOutput>?) -> Parsed? {
        var i = range.lowerBound
        let end = range.upperBound
        func skipSpaces() { while i < end, chars[i] == " " || chars[i] == "\t" { i += 1 } }
        /// Index of the first character of `pair` at or after `from`, within this line.
        func closing(_ pair: String, from: Int) -> Int? {
            let p = Array(pair)
            var j = from
            while j + 1 < end { if chars[j] == p[0], chars[j + 1] == p[1] { return j }; j += 1 }
            return nil
        }
        skipSpaces()
        guard i < end else { return nil }
        let lineBorn = born[i]

        var marker: String?
        var heading = false
        if chars[i] == "#" {
            while i < end, chars[i] == "#" { i += 1 }
            heading = true
        } else if chars[i] == ">" {
            i += 1
        } else if "-*•+".contains(chars[i]), i + 1 < end, chars[i + 1] == " " {
            marker = "•"; i += 2
        } else {
            var j = i
            while j < end, chars[j].isNumber { j += 1 }
            if j > i, j + 1 < end, chars[j] == "." || chars[j] == ")", chars[j + 1] == " " {
                marker = String(chars[i...j]); i = j + 2
            }
        }
        skipSpaces()

        // Inline markers.
        var glyphs: [Glyph] = []
        var bold = heading, italic = false
        while i < end {
            let c = chars[i]
            let next: Character? = i + 1 < end ? chars[i + 1] : nil
            let prev: Character? = i > range.lowerBound ? chars[i - 1] : nil
            // Pill markup: [[word]] and {{add}}. Each becomes one placeholder glyph.
            if c == "[", next == "[", let close = closing("]]", from: i + 2) {
                let w = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespaces)
                if !w.isEmpty {
                    glyphs.append(Glyph(ch: "\u{FFFC}", born: born[i],
                                        pill: PillTag(kind: .word, payload: w)))
                }
                i = close + 2; continue
            }
            if c == "{", next == "{", let close = closing("}}", from: i + 2), String(chars[(i + 2)..<close]) == "add" {
                glyphs.append(Glyph(ch: "\u{FFFC}", born: born[i], pill: PillTag(kind: .example, payload: "")))
                i = close + 2; continue
            }
            if (c == "*" || c == "_"), next == c {
                bold.toggle(); i += 2; continue
            }
            if c == "`" { i += 1; continue }
            if c == "*" {
                let opens = !italic && next.map { !$0.isWhitespace } == true
                let closes = italic && prev.map { !$0.isWhitespace } == true
                if opens || closes { italic.toggle(); i += 1; continue }
            }
            glyphs.append(Glyph(ch: c, born: born[i], bold: bold, italic: italic))
            i += 1
        }
        while let last = glyphs.last, last.ch.isWhitespace { glyphs.removeLast() }
        guard !glyphs.isEmpty else { return nil }

        // An {{add}} pill keeps the sentence it ends: the line's text without its pills.
        if glyphs.contains(where: { $0.pill?.kind == .example }) {
            let sentence = String(glyphs.filter { $0.pill == nil }.map(\.ch)).trimmingCharacters(in: .whitespaces)
            for k in glyphs.indices where glyphs[k].pill?.kind == .example {
                glyphs[k].pill = PillTag(kind: .example, payload: sentence)
            }
        }

        if let pattern {
            let plain = String(glyphs.map(\.ch))
            for match in plain.ranges(of: pattern) {
                let a = plain.distance(from: plain.startIndex, to: match.lowerBound)
                let b = plain.distance(from: plain.startIndex, to: match.upperBound)
                for k in a..<b { glyphs[k].ink = true }
            }
        }

        return Parsed(marker: marker, markerBorn: lineBorn, glyphs: glyphs, isHeading: heading)
    }

    /// Consecutive characters with the same style and entrance become one run.
    private static func join(_ glyphs: [Glyph]) -> Text {
        var out = Text("")
        var k = 0
        while k < glyphs.count {
            let g = glyphs[k]
            if let pill = g.pill {
                out = Text("\(out)\(styled(WordPill.placeholder(pill), born: g.born))")
                k += 1
                continue
            }
            var s = ""
            while k < glyphs.count, glyphs[k].pill == nil, glyphs[k].born == g.born, glyphs[k].bold == g.bold,
                  glyphs[k].italic == g.italic, glyphs[k].ink == g.ink {
                s.append(glyphs[k].ch); k += 1
            }
            var t = Text(s)
            if g.bold { t = t.fontWeight(.semibold) }
            if g.italic { t = t.italic() }
            if g.ink { t = t.foregroundStyle(.ink).fontWeight(.semibold) }
            out = Text("\(out)\(styled(t, born: g.born))")
        }
        return out
    }

    private static func styled(_ t: Text, born: Date?) -> Text {
        born.map { t.customAttribute(BornAt(date: $0)) } ?? t
    }

    /// The word and its inflections: "obfuscate" also matches "obfuscated", "obfuscating".
    private static func highlightPattern(_ word: String) -> Regex<AnyRegexOutput>? {
        var stem = word.lowercased().trimmingCharacters(in: .whitespaces)
        guard stem.count >= 3 else { return nil }
        if stem.count > 4, stem.hasSuffix("e") || stem.hasSuffix("y") { stem.removeLast() }
        let escaped = NSRegularExpression.escapedPattern(for: stem)
        return try? Regex("\\b\(escaped)\\w*").ignoresCase()
    }
}

private struct RevealRenderer: TextRenderer {
    let now: Date
    let rise: CGFloat

    var displayPadding: EdgeInsets { EdgeInsets(top: 6, leading: 6, bottom: rise + 6, trailing: 6) }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let born = run[BornAt.self]?.date else {
                    ctx.draw(run)
                    continue
                }
                let t = min(1, max(0, now.timeIntervalSince(born) / StreamingAnswer.duration))
                guard t > 0 else { continue }
                let p = 1 - pow(1 - t, 3) // ease-out: quick to show, slow to settle
                var c = ctx
                c.opacity = p
                if rise > 0 {
                    c.translateBy(x: 0, y: (1 - p) * rise)
                    // Each word comes into focus as it settles.
                    if p < 1 { c.addFilter(.blur(radius: (1 - p) * 5)) }
                }
                c.draw(run)
            }
        }
    }
}

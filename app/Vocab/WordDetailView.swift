import SwiftUI
import SwiftData
import CoreHaptics

/// The full entry a deck card expands into: every sense and example, relations,
/// etymology, usage and a mnemonic. Related words that are already saved show as
/// pills that open their own page; the rest are outlined and added by holding them.
/// Holding fills the word in; once it is full, its card forms over the page the
/// same way a pill's card does in Ask (`GenerateStage`), and the word is saved and
/// linked both ways to this one as the card lands. Presented with a zoom transition from
/// the card, so its top mirrors CardFace (same padding, same title) and the morph
/// reads as one surface.
struct WordDetailView: View {
    let word: Word
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("groqKey") private var groqKey = ""
    @AppStorage("groqModel") private var groqModel = GroqExplainer.defaultModel

    @State private var details: WordDetails?
    @State private var loadingDetails = false
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let ranked {
                    ForEach(Array(ranked.shown.enumerated()), id: \.offset) { n, sense in
                        senseRow(sense, number: n + 1)
                    }
                }

                if let details {
                    relations(details, saved: savedByText)
                    prose("etymology", details.etymology)
                    prose("usage", details.usage)
                } else if loadingDetails {
                    ProgressView().frame(maxWidth: .infinity)
                }

                linkedSection(saved: savedByText)

                mnemonicSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: details)
        }
        .scrollIndicators(.hidden)
        .background(Theme.card.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Theme.control, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Close")
            .padding(.trailing, 20)
        }
        // A held word's card forms over everything, close button included. The stage runs
        // its own entrance and exit.
        .overlay {
            if let job {
                GenerateStage(job: job,
                              onLanded: { landed = true; commit(job.title) },
                              onDone: { self.job = nil })
                    .id(job.id)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: holdCount)
        .sensoryFeedback(.success, trigger: savedCount)
        .sensoryFeedback(.error, trigger: failCount)
        .fullScreenCover(item: $openWord) { WordDetailView(word: $0) }
        .task { await loadDetails() }
        .task { await GenerateStage.prewarm() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(word.text)
                .font(Theme.wordFont)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            Button { Speaker.say(word.text) } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.control, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Pronounce \(word.text)")
            Spacer(minLength: 0)
        }
    }

    // MARK: Sections

    private func senseRow(_ sense: Sense, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(number) · \(sense.partOfSpeech.lowercased())")
                .font(Theme.labelFont).foregroundStyle(.ink2)
            Text(sense.definition)
                .font(Theme.detailDefinitionFont)
                .foregroundStyle(.ink2)
            ForEach(sense.examples, id: \.self) { ex in
                Text("“\(ex)”")
                    .font(.callout).italic()
                    .foregroundStyle(.ink3)
            }
        }
    }

    /// Saved words keyed by lowercased text.
    private var savedByText: [String: Word] {
        Dictionary(saved.map { ($0.text.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }

    @ViewBuilder
    private func relations(_ d: WordDetails, saved: [String: Word]) -> some View {
        related("synonyms", d.synonyms, saved: saved)
        related("antonyms", d.antonyms, saved: saved)
        related("word family", d.family, saved: saved)
    }

    /// Saved words first, as pills; the rest follow as plain text.
    @ViewBuilder
    private func related(_ label: String, _ words: [String], saved: [String: Word]) -> some View {
        let inApp = words.filter { saved[$0.lowercased()] != nil }
        let others = words.filter { saved[$0.lowercased()] == nil }
        let shown = inApp + others.prefix(max(0, 12 - inApp.count))
        if !shown.isEmpty {
            section(label) {
                FlowLayout(spacing: 12, lineSpacing: 8) {
                    ForEach(shown, id: \.self) { w in
                        if let target = saved[w.lowercased()] {
                            savedPill(target)
                        } else {
                            addableWord(w)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    /// Words linked to this one that the relation lists above don't already show:
    /// added from either page, or naming this word in their own relations.
    @ViewBuilder
    private func linkedSection(saved: [String: Word]) -> some View {
        let me = word.text.lowercased()
        let listed = Set(([details?.synonyms, details?.antonyms, details?.family]
            .compactMap { $0 }.flatMap { $0 }).map { $0.lowercased() })
        let mentioning = self.saved.filter { other in
            guard let d = other.details else { return false }
            return (d.synonyms + d.antonyms + d.family).contains { $0.lowercased() == me }
        }
        var seen: Set<String> = [me]
        let words = (word.linked + mentioning).filter { w in
            let key = w.text.lowercased()
            return !listed.contains(key) && seen.insert(key).inserted
        }
        if !words.isEmpty {
            section("linked") {
                FlowLayout(spacing: 8) {
                    ForEach(words, id: \.text) { savedPill($0) }
                }
            }
        }
    }

    private func savedPill(_ target: Word) -> some View {
        Button { openWord = target } label: {
            Text(target.text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.control, in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Opens \(target.text)")
        .transition(.blurReplace)
    }

    /// A word not in the app: hold it to add it.
    private func addableWord(_ text: String) -> some View {
        HoldToAdd(text: text, busy: adding.contains(text)) { add(text) }
            .transition(.blurReplace)
    }

    @ViewBuilder
    private func prose(_ label: String, _ text: String?) -> some View {
        if let text {
            section(label) {
                Text(text)
                    .font(Theme.detailBodyFont)
                    .foregroundStyle(.ink2)
            }
            .transition(.opacity)
        }
    }

    private var mnemonicSection: some View {
        section("mnemonic") {
            if let text = mnemonic ?? word.mnemonic {
                Text(text)
                    .font(Theme.detailBodyFont)
                    .foregroundStyle(.ink2)
                    .contentTransition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Button { writeMnemonic() } label: {
                        HStack(spacing: 8) {
                            if writingMnemonic {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(writingMnemonic ? "Writing…" : "Write one with AI")
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Theme.control, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(writingMnemonic)
                    if let mnemonicError {
                        Text(mnemonicError).font(.footnote).foregroundStyle(.ink3)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label)
                .font(Theme.labelFont).foregroundStyle(.ink2)
            content()
            if let addError, adding.isEmpty, label == lastRelationLabel {
                Text(addError).font(.footnote).foregroundStyle(.ink3)
            }
        }
    }

    // MARK: Loading

    /// Where an add error shows: under the last relation list on the page.
    private var lastRelationLabel: String? {
        guard let d = details else { return nil }
        if !d.family.isEmpty { return "word family" }
        if !d.antonyms.isEmpty { return "antonyms" }
        if !d.synonyms.isEmpty { return "synonyms" }
        return nil
    }

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
        loadingDetails = true
        defer { loadingDetails = false }
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
                mnemonic = trimmed
                word.mnemonic = trimmed
                try? context.save()
            } catch {
                mnemonicError = error.localizedDescription
            }
        }
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
    let onAdd: () -> Void

    @State private var progress: CGFloat = 0
    @State private var pressing = false
    private static let hold = 1.0

    var body: some View {
        let down = pressing || busy
        label(ink: .ink3, icon: .ink4)
            .overlay { Capsule().strokeBorder(Theme.control, lineWidth: 1.5) }
            .overlay {
                label(ink: .ink, icon: .ink2)
                    .background(Theme.control, in: Capsule())
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: busy ? 1 : progress, anchor: .leading)
                    }
            }
            .contentShape(Capsule())
            .scaleEffect(down ? 0.95 : 1)
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
        HStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(icon)
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(ink)
        .padding(.leading, 11)
        .padding(.trailing, 14)
        .frame(height: 36)
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

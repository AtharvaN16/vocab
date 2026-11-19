import SwiftUI
import SwiftData

/// Spaced-repetition study for one collection. Front shows the meaning, you
/// recall the word (trains active use), tap to reveal, then swipe to grade.
struct StudyView: View {
    let collection: WordCollection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var queue: [Word] = []
    @State private var started = false
    @State private var reviewed = 0
    @State private var revealed = false
    @State private var offset: CGSize = .zero
    @State private var askWord: Word?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).background(Theme.control, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Close")
                Spacer()
                Text("\(collection.name) · \(queue.count) left")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }

            GeometryReader { geo in
                ZStack {
                    if let current = queue.first {
                        if queue.count > 1 {
                            let p = min(1, max(abs(offset.width) / geo.size.width, abs(offset.height) / geo.size.height))
                            front(queue[1]).scaleEffect(0.92 + 0.08 * p).opacity(Double(p))
                        }
                        SwipeCard(offset: $offset, allowed: [.left, .right, .up, .down],
                                  flyOff: [.left, .right, .down], tilt: true) { dir in
                            handle(dir, current)
                        } content: {
                            ZStack {
                                if revealed { CardFace(word: current) } else { front(current) }
                                gradeTint
                            }
                            .contentShape(Theme.cardShape)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.25, bounce: 0)) { revealed.toggle() }
                            }
                        }
                        .id(current.persistentModelID)
                    } else if started {
                        doneCard
                    }
                }
            }

            Text("← didn't know   ↓ sort of   knew it →\n↑ ask AI")
                .font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .background(Theme.page.ignoresSafeArea())
        .sheet(item: $askWord) { AskView(word: $0) }
        .onAppear(perform: buildQueue)
    }

    private func front(_ word: Word) -> some View {
        let sense = word.senses.first
        return VStack(alignment: .leading, spacing: 14) {
            Text("Which word means…").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            if let sense {
                Text(mask(sense.definition, word: word.text))
                    .font(.system(.title2, design: .serif))
                if let ex = sense.examples.first {
                    Text("“\(mask(ex, word: word.text))”")
                        .font(.system(.callout, design: .serif)).italic().foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Tap to reveal").font(.footnote).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: Theme.cardShape)
    }

    /// Colour and label derived from the drag, so it always matches the gesture.
    private var gradeTint: some View {
        let dx = offset.width, dy = offset.height
        let (label, color, amount): (String, Color, CGFloat) =
            abs(dx) >= abs(dy)
            ? (dx > 0 ? ("Knew it", .green, dx) : ("Didn't know", .red, -dx))
            : (dy > 0 ? ("Sort of", .orange, dy) : ("Ask AI", .blue, -dy * 2))
        let p = Double(min(1, max(0, amount / 140)))
        return ZStack {
            Theme.cardShape.fill(color.opacity(0.18 * p))
            Text(label).font(.title.weight(.bold)).foregroundStyle(color).opacity(p)
        }
        .allowsHitTesting(false)
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Done for now").font(.system(size: 40, weight: .bold))
            Text("\(reviewed) reviews. Words come back when you're about to forget them.")
                .font(.system(.title3, design: .serif)).foregroundStyle(.secondary)
            Spacer()
            Button("Study everything anyway") { buildQueue(all: true) }
                .font(.headline).frame(maxWidth: .infinity).frame(height: 56)
                .background(Theme.control, in: Capsule())
                .buttonStyle(PressStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: Theme.cardShape)
    }

    private func buildQueue() { buildQueue(all: false) }

    private func buildQueue(all: Bool) {
        let now = Date.now
        queue = collection.words
            .filter { all || $0.due <= now }
            .sorted { $0.due < $1.due }
        started = true
        revealed = false
    }

    private func handle(_ dir: SwipeDirection, _ word: Word) {
        let grade: Grade
        switch dir {
        case .up: askWord = word; return
        case .right: grade = .good
        case .left: grade = .again
        case .down: grade = .hard
        }
        FSRS.review(word, grade: grade)
        try? context.save()
        reviewed += 1
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            queue.removeFirst()
            if grade == .again { queue.append(word) }
            revealed = false
            offset = .zero
        }
    }

    private func mask(_ text: String, word: String) -> String {
        text.replacingOccurrences(of: word, with: "_____", options: .caseInsensitive)
    }
}

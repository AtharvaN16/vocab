import SwiftUI

/// A spaced-repetition session over one collection, run on the deck itself.
struct StudySession {
    /// What is being studied: every word, or one collection.
    let scope: DeckScope
    /// Words still to grade, in order. A word graded Again goes back on the end.
    var queue: [Word]
    /// How many words the session started with; the progress line runs against it.
    var total: Int
    var reviewed = 0
    /// Where the deck was, so ending the session puts you back there.
    let returnIndex: Int

    var progress: Double { total == 0 ? 1 : 1 - Double(queue.count) / Double(total) }

    /// The words due now, most overdue first, or every word when `all`.
    static func queue(from words: [Word], all: Bool, now: Date = .now) -> [Word] {
        words
            .filter { all || $0.due <= now }
            .sorted { $0.due < $1.due }
    }
}

/// A study card: the word alone on the front, the deck's card face on the back.
/// Tapping flips it around its vertical axis; Reduce Motion crossfades instead.
struct StudyCard: View {
    let word: Word
    let flipped: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    front.opacity(flipped ? 0 : 1)
                    CardFace(word: word).opacity(flipped ? 1 : 0)
                }
            } else {
                Flip(angle: flipped ? -180 : 0, front: front, back: CardFace(word: word))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flipped ? backLabel : word.text)
    }

    private var front: some View {
        CardTitle(text: word.text)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.card, in: Theme.cardShape)
    }

    private var backLabel: String {
        let meaning = SenseRanker.primary(word.senses, tags: word.details?.senseTags)?.definition
        return [word.text, meaning].compactMap { $0 }.joined(separator: ". ")
    }
}

/// Turns from the front (0°) to the back (−180°), swapping faces at the edge-on
/// midpoint so neither is ever seen mirrored.
private struct Flip<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showsBack = abs(angle) > 90
        ZStack {
            front.opacity(showsBack ? 0 : 1)
            back
                .opacity(showsBack ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
    }
}

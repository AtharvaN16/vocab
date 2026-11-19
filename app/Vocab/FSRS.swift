import Foundation

enum Grade: Int {
    case again = 1, hard, good, easy
}

/// Minimal FSRS-4.5 scheduler with default weights, targeting 90% retention
/// (at which the next interval equals stability in days).
enum FSRS {
    static let w: [Double] = [0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
                              1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755]
    static let decay = -0.5
    static let factor = 19.0 / 81.0

    static func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        pow(1 + factor * t / s, decay)
    }

    static func initialDifficulty(_ g: Grade) -> Double {
        clamp(w[4] - Double(g.rawValue - 3) * w[5])
    }

    private static func clamp(_ d: Double) -> Double { min(10, max(1, d)) }

    static func review(_ word: Word, grade g: Grade, now: Date = .now) {
        let G = Double(g.rawValue)
        if word.reps == 0 || word.stability == 0 {
            word.stability = w[g.rawValue - 1]
            word.difficulty = initialDifficulty(g)
        } else {
            let s = word.stability, d = word.difficulty
            let t = max(0, now.timeIntervalSince(word.lastReview ?? now) / 86_400)
            let r = retrievability(elapsedDays: t, stability: s)
            if g == .again {
                let growth: Double = pow(s + 1, w[13]) - 1
                word.stability = w[11] * pow(d, -w[12]) * growth * exp(w[14] * (1 - r))
                word.lapses += 1
            } else {
                let hard = g == .hard ? w[15] : 1
                let easy = g == .easy ? w[16] : 1
                let base: Double = exp(w[8]) * (11 - d) * pow(s, -w[9])
                let recall: Double = exp(w[10] * (1 - r)) - 1
                word.stability = s * (base * recall * hard * easy + 1)
            }
            word.difficulty = clamp(w[7] * initialDifficulty(.easy) + (1 - w[7]) * (d - w[6] * (G - 3)))
        }
        word.reps += 1
        word.lastReview = now
        word.due = g == .again
            ? now.addingTimeInterval(5 * 60)
            : now.addingTimeInterval(max(1, word.stability.rounded()) * 86_400)
    }
}

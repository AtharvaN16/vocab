import SwiftUI
import AVFoundation

enum Theme {
    static let page = dynamic(light: 0.957, dark: 0.0)
    static let card = dynamic(light: 0.918, dark: 0.11)
    static let control = dynamic(light: 0.902, dark: 0.16)

    private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1) })
    }

    static let cardShape = RoundedRectangle(cornerRadius: 44, style: .continuous)
}

enum Speaker {
    static let synth = AVSpeechSynthesizer()
    static func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-GB")
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }
}

/// The word card used on the deck and on the back of study cards.
struct CardFace: View {
    let word: Word

    var body: some View {
        let senses = word.senses
        VStack(alignment: .leading, spacing: 14) {
            Text(word.text)
                .font(.system(size: 46, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(.bottom, 6)
            ForEach(Array(senses.prefix(2).enumerated()), id: \.offset) { _, sense in
                SenseView(sense: sense)
            }
            if senses.count > 2 {
                Text("+\(senses.count - 2) more \(senses.count == 3 ? "sense" : "senses") · swipe up to ask")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button { Speaker.say(word.text) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.page)
                        .frame(width: 56, height: 56)
                        .background(Color.primary, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Pronounce \(word.text)")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: Theme.cardShape)
    }
}

struct SenseView: View {
    let sense: Sense
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sense.partOfSpeech.lowercased())
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(sense.definition)
                .font(.system(.title3, design: .serif))
                .lineLimit(4)
            if let ex = sense.examples.first {
                Text("“\(ex)”")
                    .font(.system(.callout, design: .serif)).italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

struct CircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 64, height: 64)
                .background(Theme.control, in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// Press feedback: quick scale on touch-down, no bounce (no force was applied).
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}

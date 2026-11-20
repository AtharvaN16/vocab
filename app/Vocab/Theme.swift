import SwiftUI
import AVFoundation

enum Theme {
    static let page = dynamic(light: 0.957, dark: 0.0)
    static let card = dynamic(light: 0.918, dark: 0.11)
    static let control = dynamic(light: 0.902, dark: 0.16)
    /// Sheets sit above the page: white in light mode, raised grey in dark.
    static let sheet = dynamic(light: 1.0, dark: 0.11)

    /// Nonisolated: UIKit resolves the provider on whatever thread renders, including
    /// SwiftUI's async renderer during animations. A main-actor closure traps there.
    nonisolated private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1) })
    }

    /// One face and weight throughout; definitions are set apart by size and the ink scale (.ink … .ink4).
    static let wordFont = Font.system(size: 44, weight: .bold)
    /// The simplified card's word.
    static let cardWordFont = Font.system(size: 52, weight: .bold)
    /// The simplified card's single definition.
    static let cardDefinitionFont = Font.system(size: 32, weight: .bold)
    /// Definitions in the detail view, where there are many and they should read as body text.
    static let detailDefinitionFont = Font.system(size: 20, weight: .semibold)
    /// Prose sections in the detail view (etymology, usage, mnemonic): a step below definitions.
    static let detailBodyFont = Font.system(size: 16, weight: .medium)
    /// Labels in the detail view ("1 · adjective", "synonyms"): same face and ink as the
    /// text they head, set apart only by being smaller and lighter.
    static let labelFont = Font.system(size: 13, weight: .medium)

    static let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    /// Rows under the card (Favorite, Delete): the card's continuous corner, scaled
    /// down so a 56 pt row reads as a small card rather than a pill.
    static let actionShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    /// Opaque greys so a step reads the same on page, card and sheet.
    fileprivate static func ink(light: CGFloat, dark: CGFloat) -> Color { dynamic(light: light, dark: dark) }
}

/// The ink scale, strongest to faintest. Hierarchy comes from these steps, not from weight.
extension ShapeStyle where Self == Color {
    /// Words, titles, the thing the screen is about.
    static var ink: Color { Theme.ink(light: 0.07, dark: 0.96) }
    /// Text you read: definitions and prose in the detail view, AI answers.
    /// Brighter than the card's definition ink.
    static var ink2: Color { Theme.ink(light: 0.26, dark: 0.80) }
    /// Supporting text: examples, labels, captions, counts. Matches the card's definition ink.
    static var ink3: Color { Theme.ink(light: 0.50, dark: 0.60) }
    /// Hints, placeholders, attribution, disabled controls.
    static var ink4: Color { Theme.ink(light: 0.64, dark: 0.42) }
}

/// User-chosen appearance. `.system` follows the device's light/dark setting.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
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

/// The word card used on the deck and on the back of study cards: the word and
/// its first (most common) definition only. Everything else lives in WordDetailView.
struct CardFace: View {
    private let word: Word?
    private let title: String
    private let definition: String?
    /// 0…1: how far the definition has come in (Ask's forming card brings it in after
    /// the word). It rises a few points while coming into focus; the deck always shows 1.
    private let definitionIn: Double

    init(word: Word) {
        self.word = word
        title = ""
        definition = nil
        definitionIn = 1
    }

    /// The same card for a word that isn't saved yet (Ask's forming card).
    init(title: String, definition: String?, definitionIn: Double = 1) {
        word = nil
        self.title = title
        self.definition = definition
        self.definitionIn = definitionIn
    }

    var body: some View {
        // A saved word is read here, not in init, so only this view observes it.
        let text = word?.text ?? title
        let meaning = word.map { SenseRanker.primary($0.senses, tags: $0.details?.senseTags)?.definition } ?? definition
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(Theme.cardWordFont)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(.bottom, 6)
            if let meaning {
                Text(meaning)
                    .font(Theme.cardDefinitionFont)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.5)
                    .opacity(definitionIn)
                    .blur(radius: 6 * (1 - definitionIn))
                    .offset(y: 8 * (1 - definitionIn))
            }
            Spacer(minLength: 0)
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
                .font(.subheadline.weight(.medium)).foregroundStyle(.ink3)
            Text(sense.definition)
                .font(.title3)
                .lineLimit(4)
            if let ex = sense.examples.first {
                Text("“\(ex)”")
                    .font(.callout).italic()
                    .foregroundStyle(.ink3)
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
    /// Keeps the pressed size after release, for a button that is leaving.
    var held = false
    /// 0.94 suits round controls; wide rows use 0.97 so they don't visibly narrow.
    var pressedScale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.ink)
            .scaleEffect(configuration.isPressed || held ? pressedScale : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}

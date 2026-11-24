import SwiftUI
import AVFoundation

/// Surface greys. Light mode needs more steps than dark: on a white sheet the
/// control grey reads heavy, so large fills there take a paler step of their own.
/// Light ramp, palest first: sheet 1.0 · page 0.957 · row 0.953 · card 0.918 · control 0.902.
enum Theme {
    static let page = dynamic(light: 0.957, dark: 0.0)
    static let card = dynamic(light: 0.918, dark: 0.11)
    /// Small controls: circle buttons, capsules, a sheet's Cancel.
    static let control = dynamic(light: 0.902, dark: 0.16)
    /// Sheets sit above the page: white in light mode, raised grey in dark.
    static let sheet = dynamic(light: 1.0, dark: 0.11)
    /// Large filled surfaces on a sheet: list rows, tiles, a picker's track. Paler
    /// than `control` in light mode so a stack of them doesn't darken the sheet;
    /// the same as `control` in dark, where the step already reads.
    static let row = dynamic(light: 0.953, dark: 0.16)

    /// Nonisolated: UIKit resolves the provider on whatever thread renders, including
    /// SwiftUI's async renderer during animations. A main-actor closure traps there.
    nonisolated private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: dark, alpha: 1) : UIColor(white: light, alpha: 1) })
    }

    /// One face and weight throughout; definitions are set apart by size and the ink scale (.ink … .ink4).
    static let wordFont = Font.system(size: 44, weight: .bold)
    /// The simplified card's word (deck, study, Ask's forming card). Use `CardTitle`, which
    /// shrinks a long word down to `cardWordMinScale` instead of breaking it.
    static let cardWordFont = Font.system(size: 48, weight: .bold)
    /// 24 pt: room for a 20-letter word on one line of a card.
    static let cardWordMinScale: CGFloat = 0.5
    /// The simplified card's single definition.
    static let cardDefinitionFont = Font.system(size: 30, weight: .bold)
    /// 18 pt: a long definition shrinks to fit the card before it would be cut off.
    static let cardDefinitionMinScale: CGFloat = 0.6
    /// The word detail page's word and its page text (definitions, examples, pills).
    static let detailWordFont = Font.system(size: 44, weight: .bold)
    static let detailDefinitionFont = Font.system(size: 28, weight: .semibold)
    /// Labels in the detail view ("1 · adjective", "synonyms"): same face and ink as the
    /// text they head, set apart only by being smaller and lighter.
    static let labelFont = Font.system(size: 13, weight: .medium)

    static let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    /// Full-width buttons (Delete all, sheet actions): pills, like every
    /// button in the app. Rows and cards keep rounded corners.
    static let actionShape = Capsule()
    /// The deck card's Favorite and Delete rows: the card's continuous corner,
    /// scaled down so a 56 pt row reads as a small card, not a pill.
    static let cardActionShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    /// Opaque greys so a step reads the same on page, card and sheet.
    fileprivate static func ink(light: CGFloat, dark: CGFloat) -> Color { dynamic(light: light, dark: dark) }
}

/// A card's paper: Theme.card with the portfolio site's grain baked in, at 0.8x the
/// site's strength (Assets: CardGrain, made by Tools/import_portfolio_grain.py). The
/// tile is opaque and centred on the card grey, so it costs the same as the flat
/// colour: no blending, and a moving card just carries it.
struct CardSurface: View {
    var body: some View {
        Image("CardGrain")
            .resizable(resizingMode: .tile)
            .accessibilityHidden(true)
    }
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

/// User-chosen accent for the deck's main action (the search button). A solid fill
/// with its own tone per mode: dark tones are lifted so they read on black without glaring.
enum Accent: String, CaseIterable, Identifiable {
    case ink, graphite, grey, ultramarine, forest, plum, teal, saffron, orange, chartreuse
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: "Ink"
        case .graphite: "Graphite"
        case .grey: "Grey"
        case .ultramarine: "Ultramarine"
        case .forest: "Forest"
        case .plum: "Plum"
        case .teal: "Teal"
        case .saffron: "Saffron"
        case .orange: "Orange"
        case .chartreuse: "Chartreuse"
        }
    }

    /// Fill (light, dark) as 0xRRGGBB. Dark tones are muted a step (not pastel) so they
    /// don't glow on black; Saffron and Chartreuse's light tones are deepened to show on the page.
    private var tones: (UInt32, UInt32) {
        switch self {
        case .ink: (0x121212, 0xF5F5F5)
        case .graphite: (0x3A3A3C, 0xB8B8BE)
        case .grey: (0xE6E6E6, 0x292929)
        case .ultramarine: (0x2B44D6, 0x6C82F2)
        case .forest: (0x1E6B47, 0x5DBB8A)
        case .plum: (0x5E2B96, 0xA47BDE)
        case .teal: (0x0B6E73, 0x39B0B2)
        case .saffron: (0xC98A12, 0xD9A42E)
        case .orange: (0xC44C23, 0xE66D37)
        case .chartreuse: (0x9EBC2D, 0xD4F55A)
        }
    }

    /// Glyph (light, dark): whichever of white or ink contrasts more with the fill.
    private var glyphs: (UInt32, UInt32) {
        switch self {
        case .ink, .graphite: (0xFFFFFF, 0x000000)
        case .grey: (0x121212, 0xF5F5F5)
        case .ultramarine, .forest, .plum, .teal, .orange: (0xFFFFFF, 0x121212)
        case .saffron, .chartreuse: (0x121212, 0x121212)
        }
    }

    var fill: Color { dynamicHex(tones) }
    var glyph: Color { dynamicHex(glyphs) }
}

/// A (light, dark) pair of 0xRRGGBB values as one colour that follows the appearance.
/// Nonisolated, like `Theme.dynamic`: the provider can run on the async renderer.
nonisolated private func dynamicHex(_ pair: (UInt32, UInt32)) -> Color {
    let (light, dark) = pair
    return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? hex(dark) : hex(light) })
}

nonisolated private func hex(_ v: UInt32) -> UIColor {
    UIColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// A user collection's colour: bright, saturated hues, shown as a `CollectionDot`.
/// No strong reds, so a collection never reads as destructive.
/// Stored by raw value, so reordering the cases never changes saved colours.
enum CollectionColor: String, CaseIterable, Identifiable {
    case peach, butter, lime, mint, aqua, sky, periwinkle, lavender
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// (light, dark) as 0xRRGGBB. Dark mode is a touch lighter to hold up on grey.
    private var tones: (UInt32, UInt32) {
        switch self {
        case .peach: (0xFF7A33, 0xFF8A4A)
        case .butter: (0xFFBB00, 0xFFC61A)
        case .lime: (0x7FCC00, 0x93DB1A)
        case .mint: (0x00C27A, 0x1FD18E)
        case .aqua: (0x00B8C2, 0x1AC8D1)
        case .sky: (0x1F8FFF, 0x3DA0FF)
        case .periwinkle: (0x5B6BFF, 0x7381FF)
        case .lavender: (0x9F55F2, 0xB06FF5)
        }
    }

    var fill: Color { dynamicHex(tones) }
}

/// Two circles, one inside the other: a pale tint of the colour around a large
/// solid dot. The tint is mixed with white, not faded: see-through goes muddy on grey.
struct CollectionDot: View {
    let color: CollectionColor
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle().fill(color.fill.mix(with: .white, by: 0.55))
            Circle().fill(color.fill).padding(size * 0.16)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
    /// Keeps a favorited word's heart off the card while the floating heart is still
    /// in flight; it settles in once that animation is over.
    private let heartHeld: Bool
    /// 0…1: placeholder lines in the definition's place while it is still loading.
    private let loading: Double
    /// 0…1 through the placeholder's shimmer sweep.
    private let shimmer: Double

    init(word: Word, heartHeld: Bool = false) {
        self.word = word
        title = ""
        definition = nil
        definitionIn = 1
        self.heartHeld = heartHeld
        loading = 0
        shimmer = 0
    }

    /// The same card for a word that isn't saved yet (Ask's forming card).
    init(title: String, definition: String?, definitionIn: Double = 1,
         loading: Double = 0, shimmer: Double = 0) {
        word = nil
        self.title = title
        self.definition = definition
        self.definitionIn = definitionIn
        heartHeld = false
        self.loading = loading
        self.shimmer = shimmer
    }

    var body: some View {
        // A saved word is read here, not in init, so only this view observes it.
        let text = word?.text ?? title
        let meaning = word.map { SenseRanker.primary($0.senses, tags: $0.details?.senseTags)?.definition } ?? definition
        let favorite = word?.collections.contains { $0.isFavorites } ?? false
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(text: text)
                .padding(.bottom, 6)
            // The placeholder and the definition share the slot, so one crossfades into the other.
            if meaning != nil || loading > 0 {
                ZStack(alignment: .topLeading) {
                    if loading > 0 {
                        DefinitionSkeleton(shimmer: shimmer)
                            .opacity(loading)
                            .transition(.opacity)
                    }
                    if let meaning {
                        Text(meaning)
                            .font(Theme.cardDefinitionFont)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(Theme.cardDefinitionMinScale)
                            .opacity(definitionIn)
                            .blur(radius: 6 * (1 - definitionIn))
                            .offset(y: 8 * (1 - definitionIn))
                            .transition(.opacity)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // A large, faint heart in the bottom-right corner, cut off by the card's edge.
            ZStack(alignment: .bottomTrailing) {
                CardSurface()
                if favorite && !heartHeld {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(Color.ink.opacity(0.06))
                        .offset(x: 10, y: 32)
                        .transition(.blurReplace)
                        .accessibilityLabel("Favorited")
                }
            }
            .clipShape(Theme.cardShape)
        }
    }
}

/// Three rounded bars where a definition is about to be, set to the definition's line
/// pitch (32 pt bold: ~38 pt lines) so the text lands where the bars were. A soft band of
/// light sweeps across them left to right; with Reduce Motion they hold still.
private struct DefinitionSkeleton: View {
    let shimmer: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let widths: [CGFloat] = [1, 0.86, 0.58]

    private let barHeight: CGFloat = 24
    private let gap: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let bars = ZStack(alignment: .topLeading) {
                ForEach(widths.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .frame(width: w * widths[i], height: barHeight)
                        .offset(y: CGFloat(i) * (barHeight + gap))
                }
            }
            .frame(width: w, height: geo.size.height, alignment: .topLeading)

            bars.foregroundStyle(Color.ink.opacity(0.08))
                .overlay {
                    if !reduceMotion {
                        let band = w * 0.5
                        LinearGradient(colors: [.clear, Color.ink.opacity(0.07), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band, height: geo.size.height)
                            .offset(x: -band + (w + band) * shimmer)
                            .frame(width: w, height: geo.size.height, alignment: .leading)
                            .mask(bars)
                    }
                }
        }
        // Three lines' worth; 7 pt down so the bars sit on the text's x-height.
        .frame(height: CGFloat(widths.count) * barHeight + CGFloat(widths.count - 1) * gap)
        .padding(.top, 7)
        .accessibilityHidden(true)
    }
}

/// A card's word: 48 pt, shrinking to fit down to 24 pt. A single word stays on one line,
/// shrinking rather than breaking mid-word; a phrase may wrap onto a second line first.
struct CardTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.cardWordFont)
            .lineLimit(text.contains(" ") ? 2 : 1)
            .minimumScaleFactor(Theme.cardWordMinScale)
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
    /// nil: the plain grey control. Set: a solid accent fill with its glyph colour.
    var accent: Accent? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent?.glyph ?? Color.ink)
                .frame(width: 64, height: 64)
                .background(accent?.fill ?? Theme.control, in: Circle())
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

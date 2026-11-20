import SwiftUI
import UIKit

// MARK: - Model

/// A pill inside an AI answer. In the answer text, `[[word]]` marks a word that can
/// become a card and `{{add}}` ends an example sentence that can be kept.
nonisolated struct PillTag: TextAttribute, Hashable {
    enum Kind: Hashable { case word, example }
    let kind: Kind
    /// The word, or the example sentence the pill ends.
    let payload: String

    var id: String { kind == .word ? "w:" + payload.lowercased() : "e:" + payload }
}

nonisolated enum PillState: Hashable { case new, generating, added }

/// What an answer needs to draw live pills: each pill's state and what a tap does.
struct PillContext {
    let state: (PillTag) -> PillState
    let onTap: (PillTag) -> Void
}

// MARK: - Look

/// Nonisolated: the placeholder's drawing closure can run on SwiftUI's async renderer.
nonisolated enum WordPill {
    static let height: CGFloat = 30
    static let labelSize: CGFloat = 17
    static let iconWidth: CGFloat = 12
    private static let labelFont = UIFont.systemFont(ofSize: labelSize, weight: .semibold)

    /// The pill's footprint. Example pills are sized for "Added" so the line never
    /// reflows when the label changes.
    static func size(for tag: PillTag) -> CGSize {
        let text = tag.kind == .word ? tag.payload : "Added"
        let w = (text as NSString).size(withAttributes: [.font: labelFont]).width
        return CGSize(width: ceil(10 + iconWidth + 5 + w + 12), height: height)
    }

    /// Reserves the pill's place in the answer text, so it wraps like a word. The
    /// button itself is laid over this spot (see `PillOverlay`).
    static func placeholder(_ tag: PillTag) -> Text {
        Text(Image(size: size(for: tag), label: Text(tag.kind == .word ? tag.payload : "Add")) { _ in })
            .baselineOffset(-7)
            .customAttribute(tag)
    }
}

/// A neutral raised key: white in light mode, grey in dark, with a bare plus before
/// the label. Once added, it goes flat with a tick.
struct PillFace: View {
    let tag: PillTag
    let state: PillState
    var pressed = false
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    /// Held down while its card is being made, like `PressStyle(held:)`.
    private var down: Bool { pressed || state == .generating }
    private var isWord: Bool { tag.kind == .word }

    var body: some View {
        let size = WordPill.size(for: tag)
        HStack(spacing: 5) {
            Image(systemName: state == .added ? "checkmark" : "plus")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(state == .added ? Color.ink3 : Color.ink2)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: WordPill.iconWidth)
            Text(isWord ? tag.payload : (state == .added ? "Added" : "Add"))
                .font(.system(size: WordPill.labelSize, weight: .semibold))
                .foregroundStyle(labelInk)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(width: size.width, height: size.height, alignment: isWord ? .leading : .center)
        .background { face }
        .scaleEffect(down ? 0.95 : 1)
        .offset(y: down ? 1 : 0)
        .animation(.spring(duration: 0.2, bounce: 0), value: down)
        .animation(.easeOut(duration: 0.3), value: state)
    }

    @ViewBuilder private var face: some View {
        let shape = Capsule()
        if state == .added {
            shape.fill(Theme.control)
        } else {
            shape.fill(fill)
                // Inset light along the top, a darker lip along the bottom.
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [highlight, .clear, lip],
                                                      startPoint: .top, endPoint: .bottom),
                                       lineWidth: 1)
                        .opacity(down ? 0 : 1)
                }
                .overlay { shape.strokeBorder(edge, lineWidth: 0.5) }
                // Tight, neutral drop shadow. No coloured glow.
                .shadow(color: drop.opacity(down ? 0 : 1), radius: 0.5, y: 1)
                .shadow(color: drop.opacity(down ? 0 : 0.8), radius: 1.5, y: 2)
        }
    }

    private var fill: AnyShapeStyle {
        let top = Color(white: dark ? 0.23 : 1), bottom = Color(white: dark ? 0.17 : 0.945)
        if down { return AnyShapeStyle(bottom) }
        return AnyShapeStyle(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
    }

    private var highlight: Color { .white.opacity(dark ? 0.16 : 0.85) }
    private var lip: Color { .black.opacity(dark ? 0.35 : 0.06) }
    private var edge: Color { dark ? .white.opacity(0.07) : .black.opacity(0.14) }
    private var drop: Color { .black.opacity(dark ? 0.6 : 0.14) }

    private var labelInk: Color { state == .added ? .ink3 : .ink }
}

private struct PillPress: ButtonStyle {
    let tag: PillTag
    let state: PillState
    func makeBody(configuration: Configuration) -> some View {
        PillFace(tag: tag, state: state, pressed: configuration.isPressed)
    }
}

// MARK: - Placement over the answer text

/// Finds every reserved pill spot in the answer's laid-out text and puts a real button
/// on it. Pills pop in when the streaming answer reaches them.
struct PillOverlay: View {
    let layouts: Text.LayoutKey.Value
    let now: Date
    let context: PillContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Placed: Identifiable {
        let id: Int
        let tag: PillTag
        let rect: CGRect
        let born: Date?
    }

    var body: some View {
        GeometryReader { proxy in
            ForEach(Self.place(layouts, in: proxy)) { p in
                let state = context.state(p.tag)
                Button { context.onTap(p.tag) } label: { EmptyView() }
                    .buttonStyle(PillPress(tag: p.tag, state: state))
                    .allowsHitTesting(state == .new)
                    .accessibilityLabel(label(p.tag, state))
                    .modifier(PillArrival(progress: arrival(p.born), reduceMotion: reduceMotion))
                    .position(x: p.rect.midX, y: p.rect.midY)
                    #if DEBUG
                    .task { await DebugPillTap.maybeTap(index: p.id) { context.onTap(p.tag) } }
                    #endif
            }
        }
    }

    private func arrival(_ born: Date?) -> Double {
        guard let born else { return 1 }
        return min(1, max(0, now.timeIntervalSince(born) / 0.45))
    }

    private func label(_ tag: PillTag, _ state: PillState) -> String {
        switch (tag.kind, state) {
        case (.word, .added): "\(tag.payload), in your deck"
        case (.word, _): "Add \(tag.payload) to your deck"
        case (.example, .added): "Example added"
        case (.example, _): "Add this example"
        }
    }

    static func place(_ layouts: Text.LayoutKey.Value, in proxy: GeometryProxy) -> [Placed] {
        var out: [Placed] = []
        for anchored in layouts {
            let origin = proxy[anchored.origin]
            for line in anchored.layout {
                for run in line {
                    guard let tag = run[PillTag.self] else { continue }
                    let rect = run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
                    out.append(Placed(id: out.count, tag: tag, rect: rect, born: run[BornAt.self]?.date))
                }
            }
        }
        return out
    }
}

/// Fade, un-blur and a small overshoot into place, in step with the words around it.
private struct PillArrival: ViewModifier {
    let progress: Double
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        let p = progress
        // Ease-out-back: lands slightly past full size, then settles.
        let s = 1 + 2.2 * pow(p - 1, 3) + 1.2 * pow(p - 1, 2)
        content
            .opacity(min(1, p * 1.6))
            .scaleEffect(reduceMotion ? 1 : 0.86 + 0.14 * s)
            .blur(radius: reduceMotion ? 0 : (1 - p) * 4)
    }
}

#if DEBUG
/// `-tapPill N` taps the Nth pill of the first answer once it has settled, for recordings.
enum DebugPillTap {
    private static var done = false
    static func maybeTap(index: Int, _ tap: () -> Void) async {
        let args = ProcessInfo.processInfo.arguments
        guard !done, let i = args.firstIndex(of: "-tapPill"), let n = Int(args[safe: i + 1] ?? ""), n == index else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled, !done else { return }
        done = true
        tap()
    }
}
#endif

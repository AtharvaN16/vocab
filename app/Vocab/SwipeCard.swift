import SwiftUI

enum SwipeDirection: Hashable {
    case left, right, up, down
}

/// A card that tracks the finger 1:1 and hands off to a velocity-seeded spring
/// on release (Emil Kowalski's gesture rules, in SwiftUI).
///
/// - Directions in `flyOff` throw the card off screen, then call `onSwipe`.
///   The parent must then swap content and reset `offset` without animation.
/// - Directions in `park` slide the card that far and leave it there (used to
///   open a sheet underneath). The parent springs `offset` back when done.
/// - Other allowed directions call `onSwipe` and spring the card back (used to
///   open sheets). Disallowed directions rubber-band.
/// - A swipe commits on distance OR a fast flick.
struct SwipeCard<Content: View>: View {
    @Binding var offset: CGSize
    var allowed: Set<SwipeDirection>
    var flyOff: Set<SwipeDirection>
    /// Committed swipes in these directions skip the fly-off: `onHandOff` gets the
    /// release velocity and the parent animates the exit, so the next card is live
    /// at once instead of after the throw finishes.
    var handOff: Set<SwipeDirection> = []
    var tilt = false
    /// Distance (points) the card travels and rests at for a committed swipe.
    var park: [SwipeDirection: CGFloat] = [:]
    /// Swipes in these directions tap once, mid-drag, when the pull passes the commit
    /// threshold: letting go now will go through. Release then stays silent.
    var armHaptic: Set<SwipeDirection> = []
    /// Told when the pull arms or disarms, and `false` once the touch has ended
    /// (after `onSwipe`, so a committed swipe can still read the armed state).
    var onArmChange: ((Bool) -> Void)? = nil
    /// While parked, a tap calls `onTap`; dragging back toward rest and
    /// releasing past the threshold springs the card home and calls `onUnpark`.
    var parked = false
    /// When set, a touch that never moves past the slop counts as a tap. The tap
    /// lives in the same gesture as the drag so the two can never fight.
    var onUnpark: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    /// When set, a touch held still for `holdDuration` calls this instead of tapping.
    /// Like the tap, it lives inside the drag gesture: moving past the slop cancels it.
    var onLongPress: (() -> Void)? = nil
    var onHandOff: ((SwipeDirection, _ velocity: CGFloat) -> Void)? = nil
    var onSwipe: (SwipeDirection) -> Void
    @ViewBuilder var content: () -> Content

    @State private var axis: Axis?
    @State private var parkedBase: CGSize?
    @State private var commits = 0
    @State private var pressed = false
    @State private var holdTask: Task<Void, Never>?
    /// The current touch already fired `onLongPress`; the rest of it is ignored.
    @State private var held = false
    @State private var holds = 0
    /// A hold is under way: the press keeps deepening, slowly, until the hold fires.
    @State private var holding = false
    /// This drag has passed the commit threshold in an `armHaptic` direction.
    @State private var armed = false
    @State private var arms = 0
    private let holdDuration = 0.45
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(pressed ? 0.98 : 1)
                .animation(.spring(duration: 0.2, bounce: 0), value: pressed)
                // On top of the press: 0.98 × 0.98 ≈ 0.96 by the time the hold fires.
                // Slow and linear while you are deciding; springs back when it answers.
                .scaleEffect(holding ? 0.98 : 1)
                .offset(offset)
                .rotationEffect(.degrees(tilt ? Double(offset.width / geo.size.width) * 10 : 0), anchor: .bottom)
                .gesture(drag(in: geo.size))
                .sensoryFeedback(.impact(weight: .light), trigger: commits)
                .sensoryFeedback(.impact(weight: .medium), trigger: holds)
                .sensoryFeedback(.impact(weight: .medium), trigger: arms)
                .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                .accessibilityAction { onTap?() }
        }
    }

    private func direction(_ axis: Axis, _ value: CGFloat) -> SwipeDirection {
        axis == .horizontal ? (value < 0 ? .left : .right) : (value < 0 ? .up : .down)
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: onTap == nil ? 8 : 0)
            .onChanged { value in
                let t = value.translation
                if held { return }
                if parked {
                    if parkedBase == nil {
                        guard hypot(t.width, t.height) >= 8 else { return }
                        parkedBase = offset
                    }
                    guard let base = parkedBase else { return }
                    // Toward home: 1:1, stopping at rest. Away from home: resistance.
                    let dy = t.height
                    let y = dy < 0 ? base.height + rubberBand(dy, limit: size.height * 0.3) : min(0, base.height + dy)
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) { offset = CGSize(width: 0, height: y) }
                    return
                }
                if axis == nil && hypot(t.width, t.height) < 8 {
                    if onTap != nil { pressed = true }
                    if let onLongPress, holdTask == nil {
                        withAnimation(.linear(duration: holdDuration)) { holding = true }
                        holdTask = Task {
                            try? await Task.sleep(for: .seconds(holdDuration))
                            guard !Task.isCancelled else { return }
                            held = true
                            pressed = false
                            // Together with the lift, on its spring.
                            withAnimation(.spring(duration: 0.3, bounce: 0)) { holding = false }
                            holds += 1
                            onLongPress()
                        }
                    }
                    return
                }
                cancelHold()
                pressed = false
                // Horizontal unless clearly vertical (steeper than ~56°): a fast thumb
                // flick often starts on a slight downward arc, which locked it vertical.
                if axis == nil { axis = abs(t.height) > abs(t.width) * 1.5 ? .vertical : .horizontal }
                guard let axis else { return }
                let raw = axis == .horizontal ? t.width : t.height
                let limit = axis == .horizontal ? size.width : size.height
                let dir = direction(axis, raw)
                // Track phase: 1:1 where the card can go, resistance where it can't.
                let tracked: CGFloat
                if allowed.contains(dir), flyOff.contains(dir) || handOff.contains(dir) {
                    tracked = raw
                } else if allowed.contains(dir), let stop = park[dir] {
                    // Friction toward the resting spot: heavier the further you pull.
                    tracked = resisted(raw, stop: stop)
                } else {
                    tracked = rubberBand(raw, limit: limit * 0.6)
                }
                if armHaptic.contains(dir), allowed.contains(dir) {
                    // The same distance and straightness rules the release uses.
                    let threshold = axis == .horizontal ? size.width * 0.35 : 110
                    let straight = axis == .horizontal || abs(t.height) > abs(t.width)
                    // Hysteresis: arms past the threshold, disarms only 15 pt short of it,
                    // so a shaking thumb on the line taps once, not repeatedly.
                    setArmed(straight && abs(raw) > (armed ? threshold - 15 : threshold))
                } else {
                    setArmed(false)
                }
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    offset = axis == .horizontal ? CGSize(width: tracked, height: 0) : CGSize(width: 0, height: tracked)
                }
            }
            .onEnded { value in
                pressed = false
                cancelHold()
                // The arming tap already said it: a committed release stays silent.
                let wasArmed = armed
                defer { setArmed(false) }
                if held { held = false; axis = nil; return }
                if parked {
                    guard let base = parkedBase else {
                        let t = value.translation
                        if hypot(t.width, t.height) < 8 { onTap?() }
                        return
                    }
                    parkedBase = nil
                    let dy = value.translation.height
                    let vy = value.velocity.height
                    // A short park (the delete lift) comes home after half its distance.
                    let home = dy > min(110, abs(base.height) * 0.5) || (vy > 700 && dy > 0)
                    let target: CGFloat = home ? 0 : base.height
                    if home { commits += 1; onUnpark?() }
                    withAnimation(.interpolatingSpring(duration: 0.45, bounce: 0,
                                                       initialVelocity: relative(vy, from: offset.height, to: target))) {
                        offset = CGSize(width: 0, height: target)
                    }
                    return
                }
                guard let axis else {
                    let t = value.translation
                    if hypot(t.width, t.height) < 8 { onTap?() }
                    return
                }
                self.axis = nil
                let raw = axis == .horizontal ? value.translation.width : value.translation.height
                let velocity = axis == .horizontal ? value.velocity.width : value.velocity.height
                let current = axis == .horizontal ? offset.width : offset.height
                let dir = direction(axis, raw)
                // Parking (Ask) is guarded harder than other swipes so it isn't opened by accident.
                let parks = allowed.contains(dir) && !flyOff.contains(dir) && park[dir] != nil
                let threshold = axis == .horizontal ? size.width * 0.35 : parks ? parkThreshold : 110
                // Under pull resistance the card moved slower than the finger; hand off the card's speed.
                var cardVelocity = velocity
                if allowed.contains(dir), !flyOff.contains(dir), let stop = park[dir] {
                    cardVelocity *= resistedSlope(raw, stop: stop)
                }
                let flicked = abs(velocity) > (parks ? parkFlick : 700) && velocity.sign == raw.sign
                // A vertical swipe must still be mostly vertical when it ends, so a
                // flick that curved sideways doesn't open the up/down action.
                let straight = axis == .horizontal
                    || abs(value.translation.height) > abs(value.translation.width)
                // Armed means ready: inside the hysteresis band it still commits, unless
                // the finger flicks back the other way.
                let flickedBack = abs(velocity) > 700 && velocity.sign != raw.sign
                let committed = allowed.contains(dir) && straight
                    && (abs(raw) > threshold || flicked || (wasArmed && !flickedBack))

                if committed, handOff.contains(dir), let onHandOff {
                    commits += 1
                    onHandOff(dir, velocity)
                } else if committed && flyOff.contains(dir) {
                    let distance = axis == .horizontal ? size.width * 1.4 : size.height * 1.2
                    let target = raw < 0 ? -distance : distance
                    let target2D = axis == .horizontal ? CGSize(width: target, height: 0) : CGSize(width: 0, height: target)
                    commits += 1
                    withAnimation(.interpolatingSpring(duration: 0.35, bounce: 0,
                                                       initialVelocity: relative(velocity, from: current, to: target)),
                                  completionCriteria: .logicallyComplete) {
                        offset = target2D
                    } completion: {
                        onSwipe(dir)
                    }
                } else if committed, let stop = park[dir] {
                    let target = raw < 0 ? -stop : stop
                    commits += 1
                    // Hand off now so whatever opens underneath rises with the card.
                    onSwipe(dir)
                    withAnimation(.interpolatingSpring(duration: 0.45, bounce: 0,
                                                       initialVelocity: relative(cardVelocity, from: current, to: target))) {
                        offset = axis == .horizontal ? CGSize(width: target, height: 0) : CGSize(width: 0, height: target)
                    }
                } else {
                    if committed {
                        if !wasArmed { commits += 1 }
                        onSwipe(dir)
                    }
                    // Release phase, seeded with the finger's velocity. A cancel snaps back
                    // with a little bounce: "not this time". A commit opens a sheet, and the
                    // card settles home without bounce, on the sheet's unhurried family, so
                    // it rises with the sheet as one move instead of wobbling under it.
                    withAnimation(.interpolatingSpring(duration: committed ? 0.45 : 0.4,
                                                       bounce: committed || reduceMotion ? 0 : 0.2,
                                                       initialVelocity: relative(cardVelocity, from: current, to: 0))) {
                        offset = .zero
                    }
                }
            }
    }

    private func setArmed(_ on: Bool) {
        guard on != armed else { return }
        armed = on
        if on { arms += 1 }
        onArmChange?(on)
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        if holding { withAnimation(.spring(duration: 0.2, bounce: 0)) { holding = false } }
    }

    /// SwiftUI spring velocity is relative to the distance still to travel.
    private func relative(_ velocity: CGFloat, from current: CGFloat, to target: CGFloat) -> Double {
        let remaining = target - current
        guard abs(remaining) > 1 else { return 0 }
        return Double(velocity / remaining)
    }

    /// Pull resistance for parking directions. Starts at `parkFriction` of the
    /// finger's speed and eases toward `stop` without ever passing it. Heavy on
    /// purpose: parking opens Ask, and a light pull made accidental swipe-ups easy.
    private let parkFriction: CGFloat = 0.5
    /// Finger travel (pt) or flick speed (pt/s) needed to commit a parking swipe;
    /// other swipes commit at 110 pt or 700 pt/s.
    private let parkThreshold: CGFloat = 170
    private let parkFlick: CGFloat = 1200

    private func resisted(_ x: CGFloat, stop: CGFloat) -> CGFloat {
        let sign: CGFloat = x < 0 ? -1 : 1
        return sign * stop * (1 - 1 / (abs(x) * parkFriction / stop + 1))
    }

    private func resistedSlope(_ x: CGFloat, stop: CGFloat) -> CGFloat {
        let d = abs(x) * parkFriction / stop + 1
        return parkFriction / (d * d)
    }

    /// iOS-style resistance: moves a shrinking fraction of the finger's distance.
    private func rubberBand(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = x < 0 ? -1 : 1
        return sign * (1 - 1 / (abs(x) * 0.55 / limit + 1)) * limit
    }
}

extension View {
    /// A card lying under another one. `revealed` runs from 0 (fully covered) to 1
    /// (the top card has cleared it): it comes forward, from soft, receded into
    /// the page and slightly smaller to sharp and full size.
    ///
    /// It recedes behind a page-coloured veil rather than by fading: the pixels
    /// match a fade over the page, but the card stays solid and the veil is one
    /// plain layer. The veil is also what keeps the top card's edge visible, since
    /// both cards share a fill. At 0 it is fully transparent, so SwiftUI drops it
    /// from rendering (a covered card left blurred cost three blur passes a frame).
    /// `simple` (fast swiping) drops the blur, the one costly effect.
    func underCard(_ revealed: CGFloat, simple: Bool = false) -> some View {
        let p = min(1, max(0, revealed))
        return blur(radius: simple ? 0 : 4 * (1 - p))
            .modifier(Veil(amount: Veil.amount(revealed: p)))
            .opacity(p <= 0 ? 0 : 1)
            .scaleEffect(0.94 + 0.06 * p)
    }
}

/// A page-coloured layer over a card, receding it into the page by `amount`
/// (0 none, 1 gone). Animatable so a rising card can shed it on a transition.
struct Veil: ViewModifier, Animatable {
    var amount: CGFloat

    /// How far a fully covered card recedes. Enough to show the top card's edge,
    /// small enough that lifting it doesn't read as a flash.
    static let receded: CGFloat = 0.4

    /// The veil for a card `revealed` (0…1) from under the top card. It eases off
    /// faster than the reveal (squared), so most of it is gone while the finger is
    /// still dragging and little is left to lift when the top card is thrown.
    static func amount(revealed: CGFloat) -> CGFloat {
        let covered = 1 - min(1, max(0, revealed))
        return receded * covered * covered
    }

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content.overlay {
            Theme.cardShape.fill(Theme.page.opacity(amount)).allowsHitTesting(false)
        }
    }
}

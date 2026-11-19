import SwiftUI

enum SwipeDirection: Hashable {
    case left, right, up, down
}

/// A card that tracks the finger 1:1 and hands off to a velocity-seeded spring
/// on release (Emil Kowalski's gesture rules, in SwiftUI).
///
/// - Directions in `flyOff` throw the card off screen, then call `onSwipe`.
///   The parent must then swap content and reset `offset` without animation.
/// - Other allowed directions call `onSwipe` and spring the card back (used to
///   open sheets). Disallowed directions rubber-band.
/// - A swipe commits on distance OR a fast flick.
struct SwipeCard<Content: View>: View {
    @Binding var offset: CGSize
    var allowed: Set<SwipeDirection>
    var flyOff: Set<SwipeDirection>
    var tilt = false
    var onSwipe: (SwipeDirection) -> Void
    @ViewBuilder var content: () -> Content

    @State private var axis: Axis?
    @State private var commits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(offset)
                .rotationEffect(.degrees(tilt ? Double(offset.width / geo.size.width) * 10 : 0), anchor: .bottom)
                .gesture(drag(in: geo.size))
                .sensoryFeedback(.impact(weight: .light), trigger: commits)
        }
    }

    private func direction(_ axis: Axis, _ value: CGFloat) -> SwipeDirection {
        axis == .horizontal ? (value < 0 ? .left : .right) : (value < 0 ? .up : .down)
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let t = value.translation
                if axis == nil { axis = abs(t.width) > abs(t.height) ? .horizontal : .vertical }
                guard let axis else { return }
                let raw = axis == .horizontal ? t.width : t.height
                let limit = axis == .horizontal ? size.width : size.height
                let dir = direction(axis, raw)
                // Track phase: 1:1 where the card can go, resistance where it can't.
                let tracked = allowed.contains(dir) && flyOff.contains(dir) ? raw : rubberBand(raw, limit: limit * 0.6)
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    offset = axis == .horizontal ? CGSize(width: tracked, height: 0) : CGSize(width: 0, height: tracked)
                }
            }
            .onEnded { value in
                guard let axis else { return }
                self.axis = nil
                let raw = axis == .horizontal ? value.translation.width : value.translation.height
                let velocity = axis == .horizontal ? value.velocity.width : value.velocity.height
                let current = axis == .horizontal ? offset.width : offset.height
                let dir = direction(axis, raw)
                let threshold = axis == .horizontal ? size.width * 0.35 : 110
                let flicked = abs(velocity) > 700 && velocity.sign == raw.sign
                let committed = allowed.contains(dir) && (abs(raw) > threshold || flicked)

                if committed && flyOff.contains(dir) {
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
                } else {
                    if committed {
                        commits += 1
                        onSwipe(dir)
                    }
                    // Release phase: fast snap-back seeded with the finger's velocity.
                    withAnimation(.interpolatingSpring(duration: 0.4, bounce: reduceMotion ? 0 : 0.2,
                                                       initialVelocity: relative(velocity, from: current, to: 0))) {
                        offset = .zero
                    }
                }
            }
    }

    /// SwiftUI spring velocity is relative to the distance still to travel.
    private func relative(_ velocity: CGFloat, from current: CGFloat, to target: CGFloat) -> Double {
        let remaining = target - current
        guard abs(remaining) > 1 else { return 0 }
        return Double(velocity / remaining)
    }

    /// iOS-style resistance: moves a shrinking fraction of the finger's distance.
    private func rubberBand(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = x < 0 ? -1 : 1
        return sign * (1 - 1 / (abs(x) * 0.55 / limit + 1)) * limit
    }
}

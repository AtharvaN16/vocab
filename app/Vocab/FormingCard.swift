import SwiftUI

/// What the forming card shows: a deck card for a new word, or the host word with an example.
struct GenerateJob: Identifiable, Equatable {
    let id = UUID()
    let tag: PillTag
    var title: String
    /// The definition slot. A word's arrives from Wiktionary while the card is still soft.
    var body: String?

    init(tag: PillTag, hostWord: String) {
        self.tag = tag
        switch tag.kind {
        case .word:
            title = tag.payload
        case .example:
            title = hostWord
            body = tag.payload
        }
    }
}

/// How a card that stays (one with actions) leaves.
enum StageExit: Equatable {
    /// Added: up past the top edge, toward the deck it is joining.
    case toDeck
    /// Handed on (Ask AI): blurs out where it is while the next view takes over.
    case fade
    /// Dismissed: back down the way it rose.
    case drop
}

/// A tapped pill's card, made in front of you over a darkened screen.
///
/// Choreography (one lead, everything else still):
/// · Card (lead): rises 120 pt and settles (spring 0.4s, bounce 0.12), forming as it comes.
/// · Backdrop (support): the whole page fogs over behind the card (`Backdrop`)
///   as it rises (0.3s) and clears as it leaves (0.25s). The stage reports this to
///   the page host through `\.pageCover`; the page itself isn't otherwise touched.
///
/// Forming runs `pace` seconds from the tap, overlapping the rise rather than following it:
/// the card arrives as a few dark masses (blur ≤ 16 pt, contrast 2.4 about the paper, a
/// drifting ripple) and resolves into the sharp card. It holds `hold` (0.35s) so the word can be read,
/// then slides up past the top edge, toward the deck it is joining, blurring as it goes.
/// A tap on the scrim skips straight to the exit.
///
/// With `actions` (Search) the card stays once formed, with the actions under it and a
/// way back centred near the bottom of the screen. The card and actions centre as one
/// group, so the card settles above centre by half the actions' share. The way back
/// arrives and leaves with the actions. The actions follow the landing
/// (fade + 8 pt rise, 0.25s): the card forms, then you can act on it. They leave at once
/// (fade, 0.15s, no movement) while the card takes its `exit`. A tap on the scrim skips
/// the forming, or once formed dismisses.
struct GenerateStage: View {
    let job: GenerateJob
    /// Seconds from the tap to the sharp card.
    var pace: Double = 1.1
    /// How liquid the surface is while it forms, 0…1.
    var ripple: Double = 0.5
    /// Seconds a formed card holds before it leaves (cards without actions).
    var hold: Double = 0.35
    /// Shown under the formed card. With actions the card stays until `exit` is set.
    var actions: AnyView? = nil
    var actionsHeight: CGFloat = 52
    /// Centred near the bottom of the screen, with the actions.
    var back: AnyView? = nil
    /// Sends a staying card off.
    var exit: StageExit? = nil
    /// A tap on the scrim around a formed, staying card.
    var onDismiss: (() -> Void)? = nil
    /// The card is sharp: the pill can show it as added.
    let onLanded: () -> Void
    /// The card has left and the scrim has lifted: remove the stage.
    let onDone: () -> Void

    enum Phase { case hidden, forming, landed, leaving }
    @State private var phase = Phase.hidden
    @State private var clock = FrameClock()
    @State private var runner: Task<Void, Never>?
    @State private var leaveStyle = StageExit.toDeck
    /// The card starts a few degrees off straight and rights itself as it settles, so the
    /// rise reads as a card being set down rather than a rectangle sliding on a rail.
    /// Re-rolled per card (3–5°, either way) so no two land identically.
    @State private var tilt = Double.random(in: 3...5) * (Bool.random() ? 1 : -1)
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set when hosted by the page: the page fogs over while the card is shown.
    @Environment(\.pageCover) private var pageCover

    /// The deck card's size, scaled down so it reads as one being made, not the deck itself.
    private let scale: CGFloat = 0.8
    private let rise: CGFloat = 120
    private var duration: Double { reduceMotion ? 0.4 : pace }
    /// The card's paper as a luminance (Theme.card); contrast turns about this.
    private var paper: Double { scheme == .dark ? 0.11 : 0.918 }
    private var shown: Bool { phase == .forming || phase == .landed }
    private var stays: Bool { actions != nil }
    private let actionsGap: CGFloat = 20
    /// A staying card sits this far above centre, so it and its actions centre as one group.
    private var groupLift: CGFloat { stays ? (actionsGap + actionsHeight) / 2 : 0 }

    var body: some View {
        GeometryReader { geo in
            // Same geometry as the deck: the page's 24 pt margins, 1 : 1.4.
            let width = geo.size.width - 48
            let height = min(width * 1.4, geo.size.height / scale)
            ZStack {
                scrim
                    .opacity(shown ? 1 : 0)
                    .animation(.strongEaseOut(phase == .leaving ? 0.25 : 0.3), value: phase)
                    .contentShape(Rectangle())
                    .onTapGesture { scrimTap() }
                    .accessibilityHidden(true)

                card
                    .frame(width: width, height: height)
                    // Leaving stays crisp for its first stretch, then blurs and fades so it is
                    // gone just as it clears the top edge (as a thrown deck card does).
                    .blur(radius: phase == .leaving && !reduceMotion ? 8 : 0)
                    .opacity(shown ? 1 : 0)
                    .animation(fade, value: phase)
                    .scaleEffect(scale * scaleFactor)
                    .rotationEffect(.degrees(phase == .hidden && !reduceMotion ? tilt : 0))
                    .offset(y: (reduceMotion ? 0 : travel(phase, screen: geo.size.height, card: height)) - groupLift)
                    .animation(move, value: phase)
                    .allowsHitTesting(false)
                    .accessibilityHidden(stays)

                if let actions {
                    let landed = phase == .landed
                    actions
                        .frame(width: width * scale, height: actionsHeight)
                        .opacity(landed ? 1 : 0)
                        .blur(radius: landed || reduceMotion ? 0 : 4)
                        .offset(y: landed || reduceMotion || phase == .leaving ? 0 : 8)
                        .animation(landed ? .strongEaseOut(0.25) : .strongEaseOut(0.15), value: landed)
                        .offset(y: height * scale / 2 - groupLift + actionsGap + actionsHeight / 2)
                        .allowsHitTesting(landed)
                }

            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        // Outside the safe-area-free stage, so it sits above the home indicator.
        .overlay(alignment: .bottom) {
            if let back {
                let landed = phase == .landed
                back
                    .opacity(landed ? 1 : 0)
                    .blur(radius: landed || reduceMotion ? 0 : 4)
                    .animation(landed ? .strongEaseOut(0.25) : .strongEaseOut(0.15), value: landed)
                    .padding(.bottom, 16)
                    .allowsHitTesting(landed)
            }
        }
        .onAppear { runner = Task { await run() } }
        .onDisappear { runner?.cancel() }
        .onChange(of: exit) { _, new in if let new { leave(new) } }
        // The fog shares the card's fade: in 0.3s, out a touch quicker.
        .onChange(of: shown, initial: true) { _, on in
            // A staying card (Search) is all there is to look at: the page goes deep.
            withAnimation(.strongEaseOut(on ? 0.3 : 0.25)) { pageCover?(on ? (stays ? .deep : .standard) : nil) }
        }
        .modifier(StageAccessibility(stays: stays, title: job.title, detail: job.body,
                                     onActivate: skip, onEscape: { onDismiss?() }))
    }

    /// Only catches taps. The page host pushes the page back behind the card; unhosted,
    /// the stage lays the same fog itself.
    private var scrim: some View {
        pageCover == nil ? Theme.page.opacity(Backdrop.fog) : Color.clear
    }

    /// Entering from slightly small; a handed-on card shrinks a touch as it blurs out.
    private var scaleFactor: CGFloat {
        guard !reduceMotion else { return 1 }
        if phase == .hidden { return 0.95 }
        if phase == .leaving && leaveStyle == .fade { return 0.97 }
        return 1
    }

    /// Compiles the forming shader functions ahead of the first tap (part of `FormingWarmup`).
    static func prewarm() async {
        guard !prewarmed else { return }
        prewarmed = true
        try? await ShaderLibrary.generateRipple(.float(0), .float(0)).compile(as: .distortionEffect)
        try? await ShaderLibrary.paperContrast(.float(1), .float(0.5)).compile(as: .colorEffect)
    }
    private static var prewarmed = false

    /// From below, to centre, to past the top edge.
    private func travel(_ phase: Phase, screen: CGFloat, card: CGFloat) -> CGFloat {
        switch phase {
        case .hidden: rise
        case .forming, .landed: 0
        case .leaving:
            switch leaveStyle {
            case .toDeck: -(screen / 2 + card * scale / 2 + 24)
            case .fade: 0
            case .drop: rise
            }
        }
    }

    /// Entering: a settle with a little give. Leaving: no bounce, quicker.
    private var move: Animation {
        guard phase == .leaving else { return .spring(duration: 0.4, bounce: 0.12) }
        return leaveStyle == .toDeck ? .spring(duration: 0.35, bounce: 0) : .spring(duration: 0.3, bounce: 0)
    }

    /// Thrown to the deck it stays crisp for a beat; handed on or dismissed it goes at once.
    private var fade: Animation {
        guard phase == .leaving else { return .strongEaseOut(0.2) }
        return leaveStyle == .toDeck ? .strongEaseOut(0.22).delay(0.1) : .strongEaseOut(0.2)
    }

    /// Starts the rise and the forming. Landing is driven by the forming clock reaching 1
    /// (see `card`), not by a sleep, so a late frame delays the landing instead of cutting
    /// the forming short.
    private func run() async {
        // One frame at the start state, so the rise has somewhere to come from.
        try? await Task.sleep(for: .milliseconds(16))
        guard !Task.isCancelled else { return }
        phase = .forming
    }

    private func land() {
        guard phase == .forming else { return }
        phase = .landed
        onLanded()
        guard !stays else { return }
        runner = Task {
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            await leave()
        }
    }

    private func leave() async {
        phase = .leaving
        try? await Task.sleep(for: .seconds(leaveStyle == .toDeck ? 0.38 : 0.3))
        onDone()
    }

    /// Sends the card off now, finishing its forming first if it was still soft.
    private func leave(_ style: StageExit) {
        guard phase == .forming || phase == .landed else { return }
        runner?.cancel()
        leaveStyle = style
        if phase == .forming { phase = .landed; onLanded() }
        runner = Task { await leave() }
    }

    private func skip() {
        guard phase == .forming || phase == .landed else { return }
        runner?.cancel()
        if phase == .forming { phase = .landed; onLanded() }
        runner = Task { await leave() }
    }

    /// A pill's card leaves. A staying card finishes forming, or once formed is dismissed.
    private func scrimTap() {
        guard stays else { return skip() }
        if phase == .forming {
            runner?.cancel()
            phase = .landed
            onLanded()
        } else if phase == .landed {
            onDismiss?()
        }
    }

    // MARK: The card

    /// The deck card. While forming, a blurred, rippling, high-contrast copy sits under it
    /// and the sharp card fades in over the last stretch. The filters only exist while
    /// forming; landed, it is just the card.
    ///
    /// The word leads and the definition follows: the word's masses are there from the
    /// start, the definition's come in over t 0.35→0.85, rising 8 pt as they focus.
    /// A word's definition comes from Wiktionary and may not be here yet. Arriving early,
    /// it fades up through the haze (0.3 s) and follows the word as above. Arriving late,
    /// the lead doesn't wait for it: forming holds at t = 0.9, where the word is already
    /// sharp, and the definition makes its own entrance under it (rise + focus, 0.3 s);
    /// the card lands once that entrance is done. After `definitionWait` it lands on the
    /// word alone, and a definition arriving later is dropped.
    ///
    /// Until a word's definition is there, placeholder lines stand in its slot so the
    /// pause reads as loading: they form with the card on the definition's schedule and
    /// shimmer, then crossfade into the text as it arrives (0.3 s). A card that stays
    /// (Search) keeps them after landing and takes a late definition the same way.
    private var card: some View {
        TimelineView(.animation(paused: phase != .forming && !awaitingDefinition)) { ctx in
            // Before the run starts the card is unformed (t = 0), never the finished face,
            // or the sharp text shows through while the card fades in.
            let forming = phase == .hidden || phase == .forming
            let t = switch phase {
            case .hidden: 0.0
            case .forming: tick(ctx.date)
            case .landed, .leaving: 1.0
            }
            // Formed, a late definition is simply shown; it crossfades in (see below).
            let definition = forming && clock.definitionAt == nil ? nil : job.body
            let arrived = forming ? clock.definitionArrival : 1
            let grain = smooth(0.55, 0.9, t)
            // One level for the definition in both layers. The sharp face is opaque and
            // fades in over the haze; if the two layers showed the definition on different
            // schedules, the face would cover the haze's copy before showing its own, and
            // the definition would appear, dip and reappear (it did: 1 → 0.45 → 1).
            let follow = reduceMotion || !forming ? 1 : arrived * smooth(0.35, 0.85, t)
            let loading = job.tag.kind != .word ? 0
                : forming ? (1 - arrived) * (reduceMotion ? 1 : smooth(0.35, 0.85, t))
                : job.body == nil ? 1 : 0
            let shimmer = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                Theme.card.clipShape(Theme.cardShape)
                if forming && !reduceMotion {
                    Self.haze(CardFace(title: job.title, definition: definition, definitionIn: follow,
                                       loading: loading, shimmer: shimmer),
                              t: t, ripple: ripple, paper: paper)
                }
                CardFace(title: job.title, definition: definition, definitionIn: follow,
                         loading: loading, shimmer: shimmer)
                    .opacity(forming ? (reduceMotion ? t : grain) : 1)
                    .blur(radius: forming && !reduceMotion ? mix(1.6, 0, grain) : 0)
            }
            .transaction { if forming { $0.animation = nil } }
            .animation(.strongEaseOut(0.3), value: job.body == nil)
            // Lands when the word is formed and any definition has finished coming in, so
            // landing never snaps a half-arrived definition to full.
            .onChange(of: phase == .forming && t >= 1 && (clock.definitionAt == nil || arrived >= 1)) { _, done in
                if done { land() }
            }
        }
        .compositingGroup()
    }

    /// Formed with its definition still on the way: the shimmer keeps running.
    private var awaitingDefinition: Bool {
        job.tag.kind == .word && job.body == nil && (phase == .landed || phase == .leaving)
    }

    /// Longest the card holds for a word's definition before landing without it.
    private let definitionWait = 1.5

    /// Advances the forming clock one frame and returns t (0…1). Holds at 0.9 (word sharp)
    /// while a word's definition is still on its way.
    private func tick(_ now: Date) -> Double {
        if clock.definitionAt == nil, job.body != nil { clock.definitionAt = clock.elapsed }
        let waiting = job.tag.kind == .word && clock.definitionAt == nil
            && clock.elapsed < duration + definitionWait
        clock.advance(to: now, formingCap: waiting ? 0.9 * duration : nil)
        return min(1, clock.formed / duration)
    }

    /// The haze's effect chain, shared with `FormingWarmup` so the warm-up builds exactly
    /// the render pipelines the first card will need.
    fileprivate static func haze(_ content: some View, t: Double, ripple: Double, paper: Double) -> some View {
        let hz = smooth(0, 0.25, t), form = smooth(0.05, 0.8, t)
        let blur = mix(16, 1.6, 1 - pow(1 - form, 2.2))     // falls fast, then crawls through small radii
        let k = mix(2.4, 1, form)
        let warp = 32 * ripple * pow(1 - smooth(0, 0.85, t), 1.5)
        let freq = 0.006 + 0.0018 * sin(t * 4.4)             // the water drifts rather than sitting still
        return content
            .distortionEffect(ShaderLibrary.generateRipple(.float(warp), .float(freq)),
                              maxSampleOffset: CGSize(width: 20, height: 20))
            .blur(radius: blur)
            .colorEffect(ShaderLibrary.paperContrast(.float(k), .float(paper)))
            .clipShape(Theme.cardShape)
            .opacity(hz * mix(0.7, 1, form))
    }
}

/// A pill's card is one button (activate: skip). A staying card is read as its word and
/// definition, its actions stay reachable, and escape dismisses it.
private struct StageAccessibility: ViewModifier {
    let stays: Bool
    let title: String
    let detail: String?
    let onActivate: () -> Void
    let onEscape: () -> Void

    func body(content: Content) -> some View {
        if stays {
            content
                .overlay {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ". "))
                        .allowsHitTesting(false)
                }
                .accessibilityAction(.escape, onEscape)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onActivate() }
        }
    }
}

/// Forming time that only moves while frames are being drawn. Each frame advances it by
/// that frame's interval, capped at 1/30 s, so a stalled frame pauses the forming rather
/// than skipping it (wall-clock time let a first-use stall swallow the first half).
/// Plain reference state: advanced from inside the TimelineView, it must not re-render.
private final class FrameClock {
    private var last: Date?
    /// All drawn time since forming began.
    private(set) var elapsed = 0.0
    /// Forming progress in seconds; stops at a cap while the card waits for its definition.
    private(set) var formed = 0.0
    /// `elapsed` when the definition was first there to show.
    var definitionAt: Double?

    /// 0…1 over the 0.3 s after the definition arrived.
    var definitionArrival: Double {
        definitionAt.map { smooth(0, 0.3, elapsed - $0) } ?? 0
    }

    func advance(to now: Date, formingCap: Double?) {
        let dt = last.map { min(max(0, now.timeIntervalSince($0)), 1.0 / 30) } ?? 0
        last = now
        elapsed += dt
        formed = min(formed + dt, max(formed, formingCap ?? .infinity))
    }
}

/// Draws the forming card's effect chain once, tiny and invisible, when Ask opens. The
/// first draw of that chain (ripple, a 16 pt blur, contrast, compositing) builds its GPU
/// pipelines, which stalled the first card on a cold device; compiling the shader
/// functions alone (`GenerateStage.prewarm`) did not cover it.
struct FormingWarmup: View {
    /// Once per launch: the pipelines stay built.
    private static var warmed = false
    @State private var done = FormingWarmup.warmed
    @State private var t = 0.15

    var body: some View {
        if !done {
            GenerateStage.haze(CardFace(title: "Aa", definition: "Aa").frame(width: 60, height: 84),
                               t: t, ripple: 0.5, paper: 0.918)
                .compositingGroup()
                .blur(radius: 4)
                .frame(width: 60, height: 84)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task {
                    await GenerateStage.prewarm()
                    // A few frames across the blur's range, then gone.
                    for step in [0.3, 0.5, 0.8] {
                        try? await Task.sleep(for: .milliseconds(120))
                        t = step
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    Self.warmed = true
                    done = true
                }
        }
    }
}

private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let u = min(1, max(0, (x - a) / (b - a)))
    return u * u * (3 - 2 * u)
}

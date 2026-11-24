import SwiftUI

// MARK: - Presets

/// Sheet presets. Every size pushes the page back the same way (`Backdrop`).
enum SheetSize {
    /// Fills the screen below the status bar.
    case large
    /// About two thirds of the screen.
    case tall
    /// About half the screen.
    case medium
    /// Hugs its content, up to half the screen.
    case small
}

extension EnvironmentValues {
    /// Closes the bottom sheet hosting this view.
    @Entry var sheetDismiss: @MainActor () -> Void = {}
    /// How far a parkable sheet has slid up to its parked spot: 0 open, 1 parked.
    @Entry var sheetParkProgress: CGFloat = 0
    /// The padding the sheet adds under its content (room for the home indicator),
    /// so content can sit its controls concentric with the bottom corners instead.
    @Entry var sheetBottomPadding: CGFloat = 0
}

/// Set by sheet content that scrolls (a long list) to turn off dragging the sheet
/// from its content, so the scroll and the sheet don't move together. The grabber still works.
struct SheetPanDisabledKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// What a parked sheet hands the panel underneath it: whether it has committed
/// open, and the pull-down that carries the sheet back with the finger.
struct SheetPark {
    var revealed: Bool
    var pull: (CGFloat) -> Void
    var release: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    var close: () -> Void
}

extension View {
    /// A floating bottom sheet. For `.large` and `.medium` the presenting view
    /// scales back, dims and rounds; every visual derives from the sheet's
    /// position, so dragging, releasing and interrupting stay in sync.
    func bottomSheet<Sheet: View>(isPresented: Binding<Bool>, size: SheetSize = .large,
                                  @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(BottomSheet(isPresented: isPresented, size: size, parked: .constant(false),
                             parkable: false, sheet: content, under: { _ in EmptyView() }))
    }

    /// A sheet that can also be swiped up, like a deck card: it slides to the top
    /// until only its bottom edge peeks under the status bar, and `under` (an Ask
    /// panel) rises with it. Pulling the panel down or tapping the peek brings it back.
    func bottomSheet<Sheet: View, Under: View>(isPresented: Binding<Bool>, size: SheetSize = .large,
                                               parked: Binding<Bool>,
                                               @ViewBuilder content: @escaping () -> Sheet,
                                               @ViewBuilder under: @escaping (SheetPark) -> Under) -> some View {
        modifier(BottomSheet(isPresented: isPresented, size: size, parked: parked,
                             parkable: true, sheet: content, under: under))
    }

    /// Item-driven variant. The sheet keeps showing the last item while it
    /// animates out, so its content never vanishes mid-exit.
    func bottomSheet<Item, Sheet: View>(item: Binding<Item?>, size: SheetSize = .large,
                                        @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(ItemBottomSheet(item: item, size: size, sheet: content))
    }
}

private struct ItemBottomSheet<Item, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let size: SheetSize
    let sheet: (Item) -> Sheet
    @State private var shown: Item?

    func body(content: Content) -> some View {
        content
            .bottomSheet(isPresented: Binding(get: { shown != nil && item != nil },
                                              set: { if !$0 { item = nil } }),
                         size: size) {
                if let shown { sheet(shown) }
            }
            // Keep the last item through the exit; replace it on the next open.
            .onChange(of: item != nil, initial: true) { _, has in
                if has { shown = item }
            }
    }
}

// MARK: - Header

/// What the top-left button does: close the sheet, or step back inside it.
enum SheetLeading {
    case close, back
}

/// The top-left sheet button. Swapping between X and back morphs the symbol.
struct SheetLeadingButton: View {
    var kind: SheetLeading = .close
    /// Defaults to closing the sheet.
    var action: (() -> Void)?
    @Environment(\.sheetDismiss) private var dismiss

    var body: some View {
        Button { (action ?? dismiss)() } label: {
            Image(systemName: kind == .close ? "xmark" : "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .sheetCircle()
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(kind == .close ? "Close" : "Back")
    }
}

/// A trailing text action for the header, e.g. "Done". Use only when the sheet
/// needs an explicit commit; most sheets apply changes immediately.
struct SheetTrailingButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Theme.control, in: Capsule())
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A trailing glyph action for the header (edit, confirm), in the same
/// circle as the leading X so both corners match.
struct SheetIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .sheetCircle()
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

extension View {
    /// The header's small control circle: 32pt to look at, 44pt to touch.
    func sheetCircle() -> some View {
        frame(width: 32, height: 32)
            .background(Theme.control, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// Standard header: leading X/back, optional centred title, optional trailing action.
struct SheetHeader<Trailing: View>: View {
    var leading: SheetLeading = .close
    var title: String?
    /// A quieter second line under the title, e.g. what is selected.
    var subtitle: String?
    var onLeading: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            if let title {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.ink3)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.2), value: subtitle)
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 64)
            }
            HStack {
                SheetLeadingButton(kind: leading, action: onLeading)
                Spacer()
                trailing()
            }
        }
        // Concentric with the sheet's 32pt corners: each 32pt circle is centred
        // 32pt in from the side and the top, so it sits 16pt from both edges.
        // 10 + the 6pt of touch area = 16 from the side; the sheet's 24pt
        // grabber strip - 14 + 6 = 16 from the top.
        .padding(.horizontal, 10)
        .padding(.top, -14)
        .padding(.bottom, 8)
    }
}

extension SheetHeader where Trailing == EmptyView {
    init(leading: SheetLeading = .close, title: String? = nil, subtitle: String? = nil,
         onLeading: (() -> Void)? = nil) {
        self.init(leading: leading, title: title, subtitle: subtitle, onLeading: onLeading) { EmptyView() }
    }
}

// MARK: - Confirm

extension View {
    /// A destructive confirmation: the whole page fogs over (`Backdrop`) and a card
    /// rises at the bottom of the screen, with Cancel and a red Delete side by side.
    /// Tapping around the card cancels.
    func sheetConfirm(isPresented: Binding<Bool>, title: String, message: String? = nil,
                      confirm: String, action: @escaping () -> Void) -> some View {
        modifier(SheetConfirm(isPresented: isPresented, title: title, message: message,
                              confirm: confirm, action: action))
    }
}

private struct SheetConfirm: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String?
    let confirm: String
    let action: () -> Void
    /// What the page shows. Kept through the exit, after the caller clears its state.
    @State private var hosted: ConfirmContent?
    @State private var removal: Task<Void, Never>?
    @State private var key = UUID()

    func body(content: Content) -> some View {
        content
            // Hoisted to the page, so the whole page fogs over behind the card, not
            // just this sheet.
            .pageOverlay(item: hosted) { item in
                ConfirmOverlay(item: item,
                               cancel: { isPresented = false },
                               confirm: { action(); isPresented = false })
            }
            .onChange(of: isPresented, initial: true) { _, shown in
                removal?.cancel()
                if shown {
                    hosted = ConfirmContent(id: key, title: title, message: message, confirm: confirm)
                } else if hosted != nil {
                    hosted?.shown = false
                    removal = Task {
                        // Past the card's 0.4s slide out.
                        try? await Task.sleep(for: .seconds(0.45))
                        if !Task.isCancelled { hosted = nil }
                    }
                }
            }
            .onChange(of: title) { _, t in if isPresented { hosted?.title = t } }
    }
}

private struct ConfirmContent: Identifiable, Equatable {
    let id: UUID
    var title: String
    var message: String?
    var confirm: String
    var shown = true
}

/// The confirmation card at the bottom of the screen, 8pt in from the display like a
/// sheet, so its corners stay concentric with the screen's. It rises and leaves like a
/// sheet too (drawer curve, by its own height), with the fog on the same curve. Tapping
/// around it cancels.
private struct ConfirmOverlay: View {
    let item: ConfirmContent
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var appeared = false
    @Environment(\.pageCover) private var pageCover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visible: Bool { appeared && item.shown }
    private static let inset: CGFloat = 8
    private static let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                if visible {
                    // Unhosted, it brings its own fog.
                    (pageCover == nil ? Theme.page.opacity(Backdrop.fog) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: cancel)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    card(bottom: max(8, geo.safeAreaInsets.bottom - Self.inset))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .animation(visible ? .drawerOpen : .drawerClose, value: visible)
        .onAppear { appeared = true }
        .onChange(of: visible, initial: true) { _, v in
            withAnimation(v ? .drawerOpen : .drawerClose) { pageCover?(v ? .standard : nil) }
        }
    }

    private func card(bottom: CGFloat) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(item.title).font(.headline).foregroundStyle(.ink)
                if let message = item.message {
                    Text(message).font(.subheadline).foregroundStyle(.ink3)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 10)
            .padding(.horizontal, 8)
            HStack(spacing: 10) {
                Button(action: cancel) {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.control, in: Self.buttonShape)
                        .contentShape(Self.buttonShape)
                }
                .buttonStyle(PressStyle())
                Button(action: confirm) {
                    Text(item.confirm)
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.red.opacity(0.14), in: Self.buttonShape)
                        .contentShape(Self.buttonShape)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding([.top, .horizontal], 8)
        .padding(.bottom, bottom)
        .background {
            Self.shape.fill(Theme.sheet)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        }
        .padding(Self.inset)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Buttons across the app are pills.
    private static let buttonShape = Capsule()
}

// MARK: - Edge fade

extension View {
    /// For a sheet's scroll view, with the sheet's header riding on top of it.
    /// Content scrolls up under the header, where a sheet-coloured veil (82%,
    /// eased) keeps it faintly visible, as in the reader's sheets; the veil
    /// grows in over the first 24pt of scroll. At the bottom, content fades out
    /// into the controls while there is more below.
    func sheetEdgeFade<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        modifier(SheetEdgeFade(header: header()))
    }

    /// The same, for a scroll view with no header above it.
    func sheetEdgeFade() -> some View {
        modifier(SheetEdgeFade(header: Optional<EmptyView>.none))
    }
}

private struct SheetEdgeFade<Header: View>: ViewModifier {
    let header: Header?
    /// How far the veil runs past the header, and the bottom fade's length.
    private let length: CGFloat = 24
    /// The veil's strength under the header: almost opaque, never solid.
    private static var veil: Double { 0.82 }

    /// The run over which rows thin out at the top edge, under the header.
    private static var edgeSoftening: CGFloat { 20 }
    @State private var scrolled: CGFloat = 0
    @State private var below = false
    @State private var headerHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: [CGFloat].self) { g in
                let y = g.contentOffset.y + g.contentInsets.top
                let hidden = g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom
                    - g.containerSize.height - y
                return [min(length, max(0, y)).rounded(), hidden > 1 ? 1 : 0]
            } action: { _, v in
                scrolled = v[0]
                withAnimation(.smooth(duration: 0.2)) { below = v[1] > 0 }
            }
            .mask {
                VStack(spacing: 0) {
                    // Rows thin out to nothing before the scroll view's top edge,
                    // so nothing is cut off in a hard line under the veil.
                    if header != nil {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.edgeSoftening)
                    }
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(below ? 0 : 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: length)
                }
                .ignoresSafeArea()
            }
            .overlay(alignment: .top) { veil.ignoresSafeArea(edges: .top) }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let header {
                    header.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                }
            }
    }

    /// One continuous eased ramp from the top, as the reader's sheet veil
    /// (`EdgeFade` with no solid band): strongest at the edge, easing to clear
    /// a little past the header, with no plateau to end in a line.
    private var veil: some View {
        let height = (header == nil ? 0 : headerHeight) + (header == nil ? length : 48)
        let peak = header == nil ? 1 : Self.veil
        let t = scrolled / length
        let amount = t * t * (3 - 2 * t)
        var stops: [Gradient.Stop] = []
        for i in 0...16 {
            let u = Double(i) / 16
            let eased = pow((1 - u) * (1 - u) * (1 + 2 * u), 1.6) * peak
            stops.append(.init(color: .black.opacity(eased), location: u))
        }
        return Theme.sheet
            .mask(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
            .frame(height: height)
            .opacity(amount)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Container

private struct BottomSheet<Sheet: View, Under: View>: ViewModifier {
    @Binding var isPresented: Bool
    let size: SheetSize
    @Binding var parked: Bool
    let parkable: Bool
    let sheet: () -> Sheet
    let under: (SheetPark) -> Under

    /// Sheet translation from its open position: 0 is open, `travel` is off screen.
    @State private var y: CGFloat = 2000
    @State private var sheetHeight: CGFloat = 0
    @State private var screen: CGSize = .zero
    @State private var insets = EdgeInsets()
    @State private var mounted = false
    /// Finger speed at release, handed to the close animation.
    @State private var releaseVelocity: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// On-screen keyboard height, from UIKit's notifications.
    @State private var keyboard: CGFloat = 0
    /// While parking or parked the sheet ignores the keyboard, so typing in the
    /// panel below can't lift it off the top of the screen.
    @State private var keyboardFree = false
    /// The content asked for its own scrolling to win over dragging the sheet.
    @State private var panDisabled = false
    /// Held from the start of a close to its end: the distance it covers and the keyboard
    /// height the sheet keeps its size for, so the keyboard leaving can't resize it mid-close.
    @State private var closing: (travel: CGFloat, keyboard: CGFloat)?
    /// How much of a parked sheet shows under the status bar: the deck card's peek.
    private let peek: CGFloat = 44
    /// Gap between the parked sheet and the panel under it.
    private let gap: CGFloat = 12

    /// Gap between the sheet and the screen's sides and bottom.
    private let inset: CGFloat = 8
    /// Concentric with the iPhone display corners at an 8pt inset.
    private let radius: CGFloat = 32

    /// The drawer curve, shared with everything else that rises from the bottom.
    private static var open: Animation { .drawerOpen }
    private static var close: Animation { .drawerClose }

    private var travel: CGFloat { max(1, sheetHeight > 0 ? sheetHeight + inset : screen.height) }
    /// The page's push derives from this. While closing it uses the distance the close
    /// set out to cover: the keyboard leaving mid-close re-measured the sheet, and the
    /// page jumped from shrunk to nearly full size.
    private var progress: CGFloat { mounted ? min(1, max(0, 1 - y / (closing?.travel ?? travel))) : 0 }

    /// How far the sheet slides up from open (keyboard down) to its parked spot.
    private var parkDistance: CGFloat { max(1, screen.height - inset - insets.top - peek) }
    /// 0 open, 1 parked. Everything in the park derives from this, as in the deck.
    private var parkProgress: CGFloat { parkable ? min(1, max(0, -y / parkDistance)) : 0 }

    func body(content: Content) -> some View {
        // The page keeps its own safe area. Stripping it and padding it back in
        // (`.safeAreaPadding`) turned the keyboard into padding the deck could not
        // ignore, so the card squashed whenever a field focused. Instead the fog reaches
        // the whole screen on its own, under the status bar too.
        content
            .modifier(Fogged(p: progress))
        .overlay {
            // The insets and screen size come from the window, not from SwiftUI geometry.
            // Geometry here includes the keyboard and the padding an outer bottom sheet
            // has already added, so nested sheets compounded the keyboard (188 → 377 →
            // 565pt) and pushed the page off screen.
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                    let window = Self.window
                    insets = window.insets
                    screen = window.size
                }
        }
        .overlay {
            if mounted { sheetLayer }
        }
        .onChange(of: isPresented) { _, show in show ? present() : dismiss() }
        .onChange(of: parked) { _, park in
            guard isPresented, mounted else { return }
            park ? self.park() : unpark()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard let end = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboard = max(0, Self.window.size.height - end.minY)
        }
    }

    private var sheetLayer: some View {
        let pp = parkProgress
        return ZStack(alignment: .bottom) {
            // Tapping the page behind closes the sheet.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }
                .accessibilityHidden(true)

            if parkable {
                // Parked, the page goes plain behind the panel, as it is behind the deck's Ask.
                Theme.page
                    .opacity(pp)
                    .allowsHitTesting(false)
                panelLayer(pp)
            }

            sheetBody
                .offset(y: reduceMotion ? 0 : y)
                .opacity(reduceMotion ? Double(progress) : 1)
                .ignoresSafeArea(keyboardFree ? .keyboard : [])
        }
        .ignoresSafeArea(.container)
    }

    /// Hangs off the sheet's bottom edge: laid out at its parked position and pushed
    /// down by however far the sheet still has to travel, so the sheet carries it.
    private func panelLayer(_ pp: CGFloat) -> some View {
        under(SheetPark(revealed: parked, pull: pullPark, release: releasePark,
                        close: { parked = false }))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, insets.top + peek + gap)
            .padding(.bottom, keyboard > 0 ? 0 : insets.bottom)
            .offset(y: max(0, parkDistance + y))
            // Fades in slightly behind the sheet so it reads as revealed, not pasted on.
            .opacity(min(1, max(0, (pp - 0.1) / 0.6)))
            .allowsHitTesting(parked)
            .accessibilityHidden(!parked)
    }

    private var sheetBody: some View {
        sheet()
            .environment(\.sheetDismiss) { isPresented = false }
            .environment(\.sheetParkProgress, parkProgress)
            .environment(\.sheetBottomPadding, bottomPadding)
            // Parked, the peek is one big button back to the sheet.
            .allowsHitTesting(!parked)
            .overlay {
                if parked {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { parked = false }
                        .accessibilityLabel("Back to search")
                        .accessibilityAddTraits(.isButton)
                }
            }
            // A UIKit pan, so it runs alongside the scroll views and text fields inside:
            // a SwiftUI drag here lost every touch to them.
            .gesture(SheetPan(enabled: parkable && !panDisabled, onChanged: drag, onEnded: release))
            .onPreferenceChange(SheetPanDisabledKey.self) { panDisabled = $0 }
            .frame(maxWidth: .infinity, maxHeight: contentMaxHeight, alignment: .top)
            // Small sheets take their content's ideal height (still capped above).
            .fixedSize(horizontal: false, vertical: size == .small)
            .padding(.top, 24) // room for the grabber
            .padding(.bottom, bottomPadding)
            .frame(maxHeight: size == .large ? .infinity : nil, alignment: .top)
            .background {
                // Runs on behind the keyboard so the sheet never floats above it.
                // The shadow keeps its edge against the fog, which takes the page to
                // about the sheet's own white in light mode. Same as the confirmation card.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.sheet)
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                    .ignoresSafeArea(.keyboard)
            }
            .overlay(alignment: .top) { grabber }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
            .padding(.top, size == .large ? insets.top + 10 : 0)
            .padding(.horizontal, inset)
            .padding(.bottom, inset)
    }

    private var bottomPadding: CGFloat { max(12, insets.bottom - inset) }

    /// Tall and medium are fixed heights; small hugs its content up to medium's cap.
    /// Riding the keyboard, each is also capped to the room above it, so the sheet
    /// stops short of the status bar instead of sliding up under it.
    private var contentMaxHeight: CGFloat? {
        let share: CGFloat
        switch size {
        case .large: return nil
        case .tall: share = 0.66
        case .medium, .small: share = 0.5
        }
        var height = screen.height * share
        let keyboard = closing?.keyboard ?? keyboard
        if keyboard > 0 && !keyboardFree {
            height = min(height, screen.height - keyboard - insets.top - inset * 2)
        }
        return max(200, height - 24 - bottomPadding)
    }

    /// The handle strip: drag down to dismiss, tracked 1:1, resistance upward.
    private var grabber: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { drag($0.translation.height) }
                    .onEnded { release($0.translation.height, $0.velocity.height) }
            )
            .accessibilityAction(named: "Close") { isPresented = false }
    }

    /// Open: down tracks toward dismissal 1:1; up tracks toward the park when the
    /// sheet can park, and meets friction when it can't. Parked: down brings it back.
    private func drag(_ t: CGFloat) {
        if parked { pullPark(t); return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            if t >= 0 {
                y = t
            } else if parkable {
                y = -t <= parkDistance ? t : -parkDistance - rubberBand(-t - parkDistance)
            } else {
                y = -rubberBand(-t)
            }
        }
    }

    private func release(_ t: CGFloat, _ v: CGFloat) {
        if parked { releasePark(t, v); return }
        if t > travel * 0.25 || (v > 600 && t > 0) {
            releaseVelocity = v
            isPresented = false
        } else if parkable, t < 0, -t > 110 || v < -600 {
            // Same commit distance and flick speed as a deck card's swipe up.
            releaseVelocity = v
            parked = true
        } else {
            withAnimation(.interpolatingSpring(duration: 0.4, bounce: 0,
                                               initialVelocity: relative(v, to: 0))) { y = 0 }
        }
    }

    // MARK: Parking

    /// Pulling the panel (or the peek) down carries the sheet with it 1:1; pulling
    /// up past the parked spot meets friction rather than a wall.
    private func pullPark(_ dy: CGFloat) {
        let base = -parkDistance
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { y = dy >= 0 ? min(0, base + dy) : base - rubberBand(-dy, limit: 60) }
    }

    /// The deck's rule: far enough or a downward flick, unless the finger was
    /// heading back up on release. The spring inherits the finger's speed.
    private func releasePark(_ dy: CGFloat, _ vy: CGFloat) {
        if vy > 700 || (dy > 110 && vy > -300) {
            releaseVelocity = vy
            parked = false
        } else {
            withAnimation(.interpolatingSpring(duration: 0.45, bounce: 0,
                                               initialVelocity: relative(vy, to: -parkDistance))) { y = -parkDistance }
        }
    }

    private func park() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if !keyboardFree {
            // Stop riding the keyboard without moving: the sheet's layout drops by the
            // keyboard's height, and the offset takes it back up in the same frame.
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                keyboardFree = true
                y -= keyboard
            }
        }
        let v = releaseVelocity
        releaseVelocity = 0
        withAnimation(.interpolatingSpring(duration: 0.45, bounce: 0,
                                           initialVelocity: relative(v, to: -parkDistance))) { y = -parkDistance }
    }

    private func unpark() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let v = releaseVelocity
        releaseVelocity = 0
        withAnimation(.interpolatingSpring(duration: 0.45, bounce: 0, initialVelocity: relative(v, to: 0)),
                      completionCriteria: .logicallyComplete) {
            y = 0
        } completion: {
            // Back to riding the keyboard once settled (the keyboard is down by now).
            if !parked { keyboardFree = false }
        }
    }

    private func present() {
        closing = nil
        y = max(screen.height, 1000)
        mounted = true
        // Let the sheet lay out off screen for a frame (and measure), then open.
        DispatchQueue.main.async {
            if y > travel { y = travel }
            withAnimation(Self.open) { y = 0 }
        }
    }

    private func dismiss() {
        // Before the keyboard starts to leave: the sheet keeps this size until it's gone.
        let target = travel
        closing = (target, keyboard)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let v = releaseVelocity
        releaseVelocity = 0
        // A flick carries its speed into the exit; a button close uses the drawer curve.
        let animation: Animation = v > 0
            ? .interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: relative(v, to: target))
            : Self.close
        if parked { parked = false }
        // `.removed`, not `.logicallyComplete`: a flick's spring is still settling when the
        // latter fires, and unmounting there snapped the last of the fog off.
        withAnimation(animation, completionCriteria: .removed) {
            y = target
        } completion: {
            if !isPresented {
                mounted = false
                keyboardFree = false
                closing = nil
            }
        }
    }

    /// The key window's safe area (never includes the keyboard) and full size.
    private static var window: (insets: EdgeInsets, size: CGSize) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        // At launch no window is key yet; the first one is the app's.
        guard let w = windows.first(where: \.isKeyWindow) ?? windows.first else { return (EdgeInsets(), .zero) }
        let i = w.safeAreaInsets
        return (EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right), w.bounds.size)
    }

    private func relative(_ velocity: CGFloat, to target: CGFloat) -> Double {
        let remaining = target - y
        guard abs(remaining) > 1 else { return 0 }
        return Double(velocity / remaining)
    }

    private func rubberBand(_ x: CGFloat, limit: CGFloat = 40) -> CGFloat {
        (1 - 1 / (x * 0.55 / limit + 1)) * limit
    }
}


/// Drags a parkable sheet from anywhere on it, like a deck card. It recognizes
/// alongside the content's own gestures, starts only on a vertical move, and
/// stands down while text is being selected.
private struct SheetPan: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.isEnabled = enabled
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        pan.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        // Window space: the sheet moves under the finger.
        let t = pan.translation(in: nil).y
        switch pan.state {
        case .changed: onChanged(t)
        case .ended, .cancelled: onEnded(t, pan.velocity(in: nil).y)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: nil)
            return abs(v.y) > abs(v.x)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // A long press in a text field is selecting text, not moving the sheet.
            let selecting = other is UILongPressGestureRecognizer && (other.state == .began || other.state == .changed)
            return !selecting
        }
    }
}

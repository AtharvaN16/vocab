import SwiftUI

// MARK: - Presets

/// Sheet presets. Larger sheets push the page back; small ones only dim it.
enum SheetSize {
    /// Fills the screen below the status bar.
    case large
    /// About half the screen.
    case medium
    /// Hugs its content, up to half the screen.
    case small

    var pushesBack: Bool { self != .small }
}

extension EnvironmentValues {
    /// Closes the bottom sheet hosting this view.
    @Entry var sheetDismiss: @MainActor () -> Void = {}
}

extension View {
    /// A floating bottom sheet. For `.large` and `.medium` the presenting view
    /// scales back, dims and rounds; every visual derives from the sheet's
    /// position, so dragging, releasing and interrupting stay in sync.
    func bottomSheet<Sheet: View>(isPresented: Binding<Bool>, size: SheetSize = .large,
                                  @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(BottomSheet(isPresented: isPresented, size: size, sheet: content))
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

// MARK: - Container

private struct BottomSheet<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let size: SheetSize
    let sheet: () -> Sheet

    /// Sheet translation from its open position: 0 is open, `travel` is off screen.
    @State private var y: CGFloat = 2000
    @State private var sheetHeight: CGFloat = 0
    @State private var screen: CGSize = .zero
    @State private var insets = EdgeInsets()
    @State private var mounted = false
    /// Finger speed at release, handed to the close animation.
    @State private var releaseVelocity: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Gap between the sheet and the screen's sides and bottom.
    private let inset: CGFloat = 8
    /// Concentric with the iPhone display corners at an 8pt inset.
    private let radius: CGFloat = 32

    /// iOS drawer curve (Ionic), as used by Vaul. Exits run a little faster.
    private static var open: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.5) }
    private static var close: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.4) }

    /// The screen's centre in the page's own coordinates (the page sits inside the
    /// safe area), so it scales back about the middle of the display.
    private var screenCentre: UnitPoint {
        let h = screen.height - insets.top - insets.bottom
        guard h > 0 else { return .center }
        return UnitPoint(x: 0.5, y: (screen.height / 2 - insets.top) / h)
    }

    private var travel: CGFloat { max(1, sheetHeight > 0 ? sheetHeight + inset : screen.height) }
    private var progress: CGFloat { mounted ? min(1, max(0, 1 - y / travel)) : 0 }

    func body(content: Content) -> some View {
        let p = progress
        let push = size.pushesBack && !reduceMotion
        ZStack {
            Color.black.ignoresSafeArea()
            // The page keeps its own safe area. Stripping it and padding it back in
            // (`.safeAreaPadding`) turned the keyboard into padding the deck could not
            // ignore, so the card squashed whenever a field focused. Instead the dim,
            // the mask and the scale reach the whole screen, so the background under
            // the status bar still scales and rounds with the page.
            content
                .overlay {
                    Color.black.opacity((size.pushesBack ? 0.2 : 0.12) * p)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .mask {
                    RoundedRectangle(cornerRadius: push ? 14 * p : 0, style: .continuous)
                        .ignoresSafeArea()
                }
                .scaleEffect(push ? 1 - 0.07 * p : 1, anchor: screenCentre)
        }
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
    }

    private var sheetLayer: some View {
        ZStack(alignment: .bottom) {
            // Tapping the page behind closes the sheet.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }
                .accessibilityHidden(true)

            sheetBody
                .offset(y: reduceMotion ? 0 : y)
                .opacity(reduceMotion ? Double(progress) : 1)
        }
        .ignoresSafeArea(.container)
    }

    private var sheetBody: some View {
        sheet()
            .environment(\.sheetDismiss) { isPresented = false }
            .frame(maxWidth: .infinity, maxHeight: contentMaxHeight, alignment: .top)
            // Small sheets take their content's ideal height (still capped above).
            .fixedSize(horizontal: false, vertical: size == .small)
            .padding(.top, 24) // room for the grabber
            .padding(.bottom, max(12, insets.bottom - inset))
            .frame(maxHeight: size == .large ? .infinity : nil, alignment: .top)
            .background {
                // Runs on behind the keyboard so the sheet never floats above it.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.sheet)
                    .ignoresSafeArea(.keyboard)
            }
            .overlay(alignment: .top) { grabber }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
            .padding(.top, size == .large ? insets.top + 10 : 0)
            .padding(.horizontal, inset)
            .padding(.bottom, inset)
    }

    /// Medium is a fixed height; small hugs its content up to the same cap.
    private var contentMaxHeight: CGFloat? {
        switch size {
        case .large: nil
        case .medium, .small: max(200, screen.height * 0.5 - 24 - max(12, insets.bottom - inset))
        }
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
                    .onChanged { value in
                        let t = value.translation.height
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) { y = t >= 0 ? t : -rubberBand(-t) }
                    }
                    .onEnded { value in
                        let t = value.translation.height
                        let v = value.velocity.height
                        if t > travel * 0.25 || (v > 600 && t > 0) {
                            releaseVelocity = v
                            isPresented = false
                        } else {
                            withAnimation(.interpolatingSpring(duration: 0.4, bounce: 0,
                                                               initialVelocity: relative(v, to: 0))) { y = 0 }
                        }
                    }
            )
            .accessibilityAction(named: "Close") { isPresented = false }
    }

    private func present() {
        y = max(screen.height, 1000)
        mounted = true
        // Let the sheet lay out off screen for a frame (and measure), then open.
        DispatchQueue.main.async {
            if y > travel { y = travel }
            withAnimation(Self.open) { y = 0 }
        }
    }

    private func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let v = releaseVelocity
        releaseVelocity = 0
        // A flick carries its speed into the exit; a button close uses the drawer curve.
        let animation: Animation = v > 0
            ? .interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: relative(v, to: travel))
            : Self.close
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            y = travel
        } completion: {
            if !isPresented { mounted = false }
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

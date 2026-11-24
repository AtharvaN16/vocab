import SwiftUI

/// A short confirmation dropped from the top of the screen ("Word saved").
///
/// It drops in from above the top edge (spring 0.35s, bounce 0.12) out of a light blur,
/// holds 1.8s, and goes back up the way it came, quicker and with no bounce. A tap or a
/// flick up sends it off early. A second toast while one is showing swaps the text in
/// place and restarts the hold, so two never stack. With Reduce Motion it only fades.
@Observable @MainActor
final class Toaster {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    private(set) var current: Toast?
    private var runner: Task<Void, Never>?

    static let enter = Animation.spring(duration: 0.35, bounce: 0.12)
    static let exit = Animation.spring(duration: 0.3, bounce: 0)
    private let hold: Duration = .seconds(1.8)

    /// Shows `text` after `delay` seconds (to land after whatever caused it).
    func show(_ text: String, after delay: Double = 0) {
        runner?.cancel()
        runner = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            if current == nil {
                withAnimation(Self.enter) { current = Toast(text: text) }
            } else {
                current?.text = text
            }
            AccessibilityNotification.Announcement(text).post()
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        runner?.cancel()
        withAnimation(Self.exit) { current = nil }
    }
}

extension View {
    /// Hosts the toaster's toast at the top of this view, over everything in it.
    func toastHost(_ toaster: Toaster) -> some View {
        overlay(alignment: .top) {
            if let toast = toaster.current {
                ToastView(text: toast.text) { toaster.dismiss() }
                    .id(toast.id)
                    .transition(.toast)
            }
        }
    }
}

private struct ToastView: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .contentTransition(.opacity)
        }
        .font(.subheadline.weight(.semibold))
        // Inverted against the page: a dark toast in light mode, a light one in dark mode.
        .foregroundStyle(Theme.page)
        .padding(.horizontal, 18)
        .frame(height: 44)
        // The long-press row's corner, so it reads as one of the app's own surfaces.
        .background(Color.ink, in: Theme.cardActionShape)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.top, 8)
        .contentShape(Theme.cardActionShape)
        .onTapGesture(perform: onDismiss)
        .gesture(DragGesture(minimumDistance: 8).onEnded { v in
            if v.translation.height < 0 { onDismiss() }
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private extension AnyTransition {
    /// Down from above the top edge, out of a light blur; back up the same way.
    static var toast: AnyTransition {
        .modifier(active: ToastIn(shown: false), identity: ToastIn(shown: true))
    }
}

private struct ToastIn: ViewModifier {
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .offset(y: shown || reduceMotion ? 0 : -110)
    }
}

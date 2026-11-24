import SwiftUI

// MARK: - The backdrop

/// The one backdrop in the app. Whatever an overlay covers (a sheet, a forming card,
/// a confirmation) fades into the page and goes slightly soft: fog. Nothing else in the
/// app darkens, frosts, shrinks or blurs what sits behind an overlay.
///
/// It always applies to the whole page behind the overlay, never to a single panel:
/// sheets wrap the page they're presented from, and overlays that live deep in a view
/// (a pill's card in Ask, a delete confirmation in a sheet) are hoisted to the page's
/// `PageOverlayHost` with `pageOverlay(item:)`.
enum Backdrop {
    /// How much of the page colour lies over it: white in light mode, black in dark.
    static let fog: Double = 0.7
    /// A light blur under the fog, so the page's text stops competing with the overlay.
    static let blur: CGFloat = 2

    /// How far the page recedes. `standard` behind sheets and passing cards: fog and a
    /// light blur. `deep` where the overlay is all there is to look at (a word formed from
    /// Search, with its actions): solid page colour, white or black, nothing behind at all.
    /// Cheapest of all, and nothing to blur when nothing shows.
    enum Depth: Comparable {
        case standard, deep
        var fog: Double { self == .deep ? 1 : Backdrop.fog }
        var blur: CGFloat { self == .deep ? 0 : Backdrop.blur }
    }
}

extension Animation {
    /// iOS drawer curve (Ionic), as used by Vaul: anything that rises from the bottom
    /// (sheets, confirmations) and the fog behind it. Exits run a little faster.
    static var drawerOpen: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.5) }
    static var drawerClose: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.4) }
}

/// Fogs the page by `p` (0 at rest, 1 fully behind an overlay). Both the fog and the blur
/// are linear in `p`, so dragging, releasing and interrupting stay in step with the
/// overlay that drives it. Nothing moves, so Reduce Motion needs no variant.
struct Fogged: ViewModifier {
    var p: CGFloat
    var depth: Backdrop.Depth = .standard

    func body(content: Content) -> some View {
        // The fog is a full-screen layer beside the page, not an overlay sized to it: the
        // page's frame stops at the safe area, and an overlay stretched to the screen by
        // measuring it left the strip under the home indicator unfogged, with the bottom
        // of an open sheet showing through brighter.
        ZStack {
            // At rest the zero-radius blur is dropped and costs nothing.
            content.blur(radius: depth.blur * p)
            Theme.page.opacity(depth.fog * p)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        // The blur only draws the page's own frame; what the page paints past it (its
        // background under the status bar and home indicator) is filled with page colour,
        // not the black window.
        .background { Theme.page.ignoresSafeArea() }
    }
}

extension View {
    /// The standard backdrop for a view sitting straight on the plain page, when nothing
    /// else on the page would change: fading toward the page colour is exactly the fog
    /// over it, and it blurs by the same amount. Cheaper than fogging the whole screen.
    func backdropFaded(_ p: Double) -> some View {
        opacity(1 - Backdrop.fog * p)
            .blur(radius: Backdrop.blur * p)
    }
}

// MARK: - Page overlays

/// Overlays shown over the whole page, in front of everything, with the page fogged
/// behind them while any of them covers it.
@Observable @MainActor
final class PageOverlays {
    struct Item: Identifiable {
        let id: UUID
        var view: AnyView
        var covering: Backdrop.Depth?
    }

    private(set) var items: [Item] = []

    /// The deepest fog any overlay asks for; nil when none covers the page.
    var covering: Backdrop.Depth? { items.compactMap(\.covering).max() }

    func show(_ id: UUID, _ view: AnyView) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].view = view }
        else { items.append(Item(id: id, view: view)) }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func cover(_ id: UUID, _ depth: Backdrop.Depth?) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].covering != depth else { return }
        items[i].covering = depth
    }
}

extension EnvironmentValues {
    /// Given to a page overlay: report how deeply it covers the page right now (nil when it
    /// doesn't), so the page fogs over while it does. Call it inside the overlay's own
    /// `withAnimation` so the fog shares its curve. Nil when the overlay isn't hosted
    /// (draw your own fog).
    @Entry var pageCover: (@MainActor (Backdrop.Depth?) -> Void)? = nil
}

/// The page that overlays are hoisted to. Apply once, at the root of a full-screen page.
private struct PageOverlayHost: ViewModifier {
    @State private var overlays = PageOverlays()
    /// Kept through the fade out, so the fog clears from the depth it was at.
    @State private var depth = Backdrop.Depth.standard

    func body(content: Content) -> some View {
        let covering = overlays.covering
        ZStack {
            content
                // No curve of its own: each overlay reports covering inside its own
                // animation, so the fog moves with whatever brings that overlay in.
                .modifier(Fogged(p: covering == nil ? 0 : 1, depth: covering ?? depth))
            ForEach(overlays.items) { item in
                item.view
                    .environment(\.pageCover) { [overlays] d in overlays.cover(item.id, d) }
                    .transition(.opacity)
            }
        }
        .onChange(of: covering) { _, d in if let d { depth = d } }
        .environment(overlays)
    }
}

/// Hoists an overlay to the page's host. Without a host it falls back to a plain overlay.
private struct PageOverlayPresenter<Item: Identifiable & Equatable, Overlay: View>: ViewModifier {
    let item: Item?
    let overlay: (Item) -> Overlay
    @Environment(PageOverlays.self) private var host: PageOverlays?
    @State private var key = UUID()

    func body(content: Content) -> some View {
        content
            .overlay {
                if host == nil, let item { overlay(item).id(item.id) }
            }
            // On any change, not just a new item: a card's definition arrives after it opens.
            .onChange(of: item, initial: true) { sync() }
            .onDisappear { host?.remove(key) }
    }

    private func sync() {
        guard let host else { return }
        if let item { host.show(key, AnyView(overlay(item).id(item.id))) }
        else { host.remove(key) }
    }
}

extension View {
    /// The root of a full-screen page: overlays hoisted with `pageOverlay` show here,
    /// over everything, and fog the whole page while they cover it.
    func pageOverlayHost() -> some View {
        modifier(PageOverlayHost())
    }

    /// Shows `content` over the whole page while `item` is set, however deep this view is.
    /// The overlay reports when it covers the page through `\.pageCover`.
    func pageOverlay<Item: Identifiable & Equatable, Overlay: View>(
        item: Item?, @ViewBuilder content: @escaping (Item) -> Overlay) -> some View {
        modifier(PageOverlayPresenter(item: item, overlay: content))
    }
}

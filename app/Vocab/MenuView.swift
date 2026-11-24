import SwiftUI
import SwiftData

/// Opened from the deck's menu button. One sheet with two pages: the menu
/// itself (Collections, then the settings, all chosen in place) and the
/// Collections page it steps into, where picking All words or a collection
/// opens it on the deck (which studies it). The deck is home until then.
/// Rows match Save to's filled rows; changes apply immediately.
struct MenuView: View {
    @Binding var selected: DeckScope?
    /// Opens straight on the Collections page.
    var startOnCollections = false

    @Environment(\.modelContext) private var context
    @Environment(\.sheetDismiss) private var dismiss
    @Query(sort: WordCollection.userOrder) private var collections: [WordCollection]
    @Query private var allWords: [Word]

    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("groqKey") private var groqKey = ""
    @AppStorage("groqModel") private var groqModel = GroqExplainer.defaultModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("accent") private var accentRaw = Accent.ink.rawValue

    private enum Page { case menu, collections, editCollections }
    @State private var page = Page.menu
    /// Bumps on every choice: drives the haptic.
    @State private var picks = 0
    /// Bumps when holding a row opens the editor: drives its heavier haptic.
    @State private var holds = 0
    @Namespace private var segment

    var body: some View {
        ZStack(alignment: .top) {
            switch page {
            case .menu: menu.transition(.blurFade)
            case .collections: collectionsPage.transition(.blurFade)
            case .editCollections:
                CollectionEditor { page = .collections }.transition(.blurFade)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.3), value: page)
        .sensoryFeedback(.selection, trigger: picks)
        .sensoryFeedback(.impact(weight: .medium), trigger: holds)
        .onAppear { if startOnCollections { page = .collections } }
        .task { WordCollection.ensureDefaults(in: context) }
    }

    static let rowShape = AddToCollectionView.rowShape
    /// Rounder than the rows: the tiles are near-square.
    static let tileShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    // MARK: Menu

    private var menu: some View {
        sheetPage {
            Button { page = .collections } label: {
                MenuRow(systemImage: "rectangle.stack", title: "Collections", count: collections.count) {
                    chevron
                }
                .background(Theme.row, in: Self.rowShape)
            }
            .buttonStyle(PressStyle(pressedScale: 0.97))

            section("Appearance") { appearancePicker }

            section("Accent", footer: "Colours the search button on the home screen.") { accentPicker }

            section("AI", footer: "Automatic uses Apple's on-device model when it's available, then Groq (debug builds with a key), then plain dictionary templates.") {
                ForEach(Engine.allCases) { engineRow($0) }
            }

            section("Dictionary", footer: "Until then, search looks words up live on Wiktionary. Saved words always work offline.") {
                MenuRow(systemImage: "arrow.down.circle", title: "Offline dictionary") {
                    Text("Not in PoC").font(.body).foregroundStyle(.ink4)
                }
                .background(Theme.row, in: Self.rowShape)
                .opacity(0.6)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Not available yet")
            }

            #if DEBUG
            section("Testing only", footer: GroqExplainer.bundledKey.isEmpty
                    ? "Debug builds only. Or put GROQ_API_KEY in app/.env. Models: console.groq.com/docs/models."
                    : "Using the key from app/.env. A key typed here overrides it. Models: console.groq.com/docs/models.") {
                field { SecureField("Groq API key", text: $groqKey) }
                field {
                    TextField("Model", text: $groqModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            #endif

            Text("Definitions from Wiktionary, available under CC BY-SA 4.0.")
                .font(.footnote).foregroundStyle(.ink4)
                .padding(.horizontal, 16)
        } header: {
            SheetHeader()
        }
    }

    // MARK: Collections

    /// The built-in two as tiles side by side (All words, Favorites), then the
    /// user's collections as rows with their colour dots. Tap any to open it on
    /// the deck. Edit (top right), or holding a row, opens the same editor as Save to's.
    private var collectionsPage: some View {
        sheetPage(spacing: 8) {
            HStack(spacing: 8) {
                tile(systemImage: "rectangle.stack", title: "All words", count: allWords.count) {
                    show(.all)
                }
                if let favorites = collections.first(where: \.isFavorites) {
                    tile(systemImage: "heart", title: favorites.name, count: favorites.words.count) {
                        show(.collection(favorites))
                    }
                }
            }
            // A little more air between the built-in tiles and the user's own.
            .padding(.bottom, 12)
            ForEach(collections.filter { !$0.isFavorites }) { c in
                HoldButton(onTap: { show(.collection(c)) }, onHold: editFromHold) {
                    MenuRow(title: c.name, count: c.words.count) {
                        CollectionDot(color: c.color)
                    } trailing: { chevron }
                    .background(Theme.row, in: Self.rowShape)
                }
                .accessibilityLabel("\(c.name), \(c.words.count) words")
                .accessibilityAction(named: "Edit collections", editFromHold)
            }
        } header: {
            SheetHeader(leading: .back, title: "Collections", onLeading: { page = .menu }) {
                SheetIconButton(systemImage: "pencil", label: "Edit collections") { page = .editCollections }
            }
        }
    }

    private func check(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(on ? AnyShapeStyle(Color.ink) : AnyShapeStyle(Color.ink4))
            .contentTransition(.identity)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold)).foregroundStyle(.ink4)
    }

    /// A squarish built-in tile: icon on top, name and count at the bottom.
    private func tile(systemImage: String, title: String, count: Int,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: systemImage)
                    .font(.title3).foregroundStyle(.ink3)
                Spacer(minLength: 12)
                Text(title).font(.headline).foregroundStyle(.ink).lineLimit(1)
                Text("\(count) \(count == 1 ? "word" : "words")")
                    .font(.subheadline).foregroundStyle(.ink3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 112)
            .background(Theme.row, in: Self.tileShape)
            .contentShape(Self.tileShape)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressStyle(pressedScale: 0.97))
    }

    private func editFromHold() {
        holds += 1
        page = .editCollections
    }

    private func show(_ scope: DeckScope) {
        selected = scope
        dismiss()
    }

    // MARK: Layout

    /// A sheet page: a scrolling column with the header riding on top.
    private func sheetPage<Content: View, Header: View>(spacing: CGFloat = 28,
                                                   @ViewBuilder _ content: () -> Content,
                                                   @ViewBuilder header: () -> Header) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .sheetEdgeFade(header: header)
    }

    /// A small label over a stack of rows, with optional fine print under them.
    /// Labels and fine print line up with the text inside the rows.
    private func section<Content: View>(_ title: String, footer: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.labelFont).foregroundStyle(.ink3)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) { content() }
            if let footer {
                Text(footer)
                    .font(.footnote).foregroundStyle(.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Appearance

    /// Three pills on a grey track; the chosen one is raised on the sheet's colour
    /// and slides between them.
    private var appearancePicker: some View {
        HStack(spacing: 0) {
            ForEach(Appearance.allCases) { a in
                let on = appearanceRaw == a.rawValue
                Button {
                    guard !on else { return }
                    picks += 1
                    withAnimation(.snappy(duration: 0.3)) { appearanceRaw = a.rawValue }
                } label: {
                    Text(a.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? .ink : .ink3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Theme.sheet)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: segment)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(pressedScale: 0.97))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.row, in: Capsule())
    }

    // MARK: Accent

    /// Two rows of swatches on a grey card, each in its own mode's tone; the chosen
    /// one carries a check in its glyph colour, as the search button would.
    private var accentPicker: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: 14) {
                ForEach(Accent.allCases) { a in
                    let on = accentRaw == a.rawValue
                    Button {
                        guard !on else { return }
                        picks += 1
                        withAnimation(.snappy(duration: 0.3)) { accentRaw = a.rawValue }
                    } label: {
                        Circle()
                            .fill(a.fill)
                            .frame(width: 44, height: 44)
                            // A faint edge so Grey, close to this card, still reads as a swatch.
                            .overlay { Circle().strokeBorder(Color.ink.opacity(0.14), lineWidth: 1) }
                            .overlay {
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(a.glyph)
                                        .transition(.blurReplace)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(a.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text((Accent(rawValue: accentRaw) ?? .ink).title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ink3)
                .contentTransition(.opacity)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Theme.row, in: Self.rowShape)
    }

    // MARK: AI

    private func engineRow(_ e: Engine) -> some View {
        let on = engineRaw == e.rawValue
        return Button {
            guard !on else { return }
            picks += 1
            engineRaw = e.rawValue
        } label: {
            MenuRow(systemImage: e.symbol, title: e.shortTitle, subtitle: subtitle(e)) {
                check(on)
            }
            .background(Theme.row, in: Self.rowShape)
            // As in Save to: the check reads the moment the finger lifts.
            .transaction { $0.animation = nil }
        }
        .buttonStyle(PressStyle(pressedScale: 0.97))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func subtitle(_ e: Engine) -> String {
        switch e {
        case .automatic: "The best one available"
        case .apple: AppleExplainer.isAvailable ? "Apple Intelligence · Available" : "Apple Intelligence · Unavailable"
        case .groq: "Cloud · testing only"
        case .templates: "Dictionary text, no AI"
        }
    }

    // MARK: Testing

    private func field<F: View>(@ViewBuilder _ f: () -> F) -> some View {
        f()
            .font(.body)
            .foregroundStyle(.ink)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Theme.row, in: Self.rowShape)
    }
}

/// Tap or hold, with the same press scale as `PressStyle`'s rows. A Button can't
/// carry both: its tap would still fire when a hold is released.
private struct HoldButton<Label: View>: View {
    let onTap: () -> Void
    let onHold: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var pressing = false

    var body: some View {
        label()
            .scaleEffect(pressing ? 0.97 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: pressing)
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 12, perform: onHold) {
                pressing = $0
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onTap)
    }
}

/// A filled menu row: icon slot, title with a count beside it or a quieter line
/// under it, and a trailing accessory. Same metrics as Save to's collection rows.
private struct MenuRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var count: Int?
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            icon().frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.ink)
                    if let count {
                        Text("\(count)").font(.body).foregroundStyle(.ink3)
                    }
                }
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.ink3)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .padding(.vertical, subtitle == nil ? 0 : 6)
        .contentShape(Rectangle())
    }
}

private extension MenuRow where Icon == MenuSymbol {
    init(systemImage: String, title: String, subtitle: String? = nil, count: Int? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, subtitle: subtitle, count: count,
                  icon: { MenuSymbol(name: systemImage) }, trailing: trailing)
    }
}

/// A row's SF Symbol, in faded ink.
private struct MenuSymbol: View {
    let name: String
    var body: some View {
        Image(systemName: name).font(.body).foregroundStyle(.ink3)
    }
}

private extension Engine {
    var shortTitle: String {
        switch self {
        case .automatic: "Automatic"
        case .apple: "On-device"
        case .groq: "Groq"
        case .templates: "Templates"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "sparkles"
        case .apple: "iphone"
        case .groq: "cloud"
        case .templates: "text.book.closed"
        }
    }
}

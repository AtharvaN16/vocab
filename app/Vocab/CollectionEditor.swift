import SwiftUI
import SwiftData

/// The collections editor, shared by Save to (pull a card down) and the menu's
/// Collections page: an editable list where collections can be renamed (tap the
/// name), recoloured (tap the dot: swatches replace New collection at the
/// bottom), deleted, and dragged into a new order. Favorites is built in and
/// can't be changed, so it isn't listed.
///
/// Brings its own header and bottom bar, so it fills the sheet page it is on.
struct CollectionEditor: View {
    /// When editing from Save to, a new collection also gets this word.
    var word: Word?
    /// The header's checkmark: back to the page that opened the editor.
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: WordCollection.userOrder) private var collections: [WordCollection]

    private enum Step { case edit, name }
    @State private var step = Step.edit
    @State private var newName = ""
    /// The collection whose name is being edited in place, if any.
    @State private var renaming: WordCollection?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @State private var pendingDelete: WordCollection?
    /// Edit-mode order while dragging; written back to `order` on release.
    @State private var editOrder: [WordCollection] = []
    @State private var dragging: WordCollection?
    @State private var dragStart = 0
    /// The slot the lifted row would drop into.
    @State private var dragTarget = 0
    @State private var dragY: CGFloat = 0
    @FocusState private var nameFocused: Bool
    /// Bumps when a collection is made: drives the haptic.
    @State private var creates = 0
    /// The collection whose colour the swatch bar is choosing, if open.
    @State private var recoloring: WordCollection?
    /// Bumps on every colour pick: drives the haptic.
    @State private var recolors = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The header rides on the list so rows scroll up under its veil.
                switch step {
                case .edit: editList.transition(.blurFade)
                case .name: VStack(spacing: 0) { header; nameField }.transition(.blurFade)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            bottomBar
        }
        .animation(.smooth(duration: 0.3), value: step)
        .sensoryFeedback(.selection, trigger: creates)
        .sensoryFeedback(.selection, trigger: recolors)
        .animation(.smooth(duration: 0.3), value: recoloring?.persistentModelID)
        // An unchanged name just closes when the field loses focus; a changed
        // one waits for Done or Cancel at the bottom.
        .onChange(of: renameFocused) { _, focused in
            if !focused && !renameChanged { renaming = nil }
        }
        .onChange(of: collections.map(\.persistentModelID), initial: true) { syncEditOrder() }
        .animation(.smooth(duration: 0.25), value: renameChanged)
        .sheetConfirm(isPresented: Binding(get: { pendingDelete != nil },
                                           set: { if !$0 { pendingDelete = nil } }),
                      title: "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
                      message: "Its words stay in your library.",
                      confirm: "Delete") {
            if let c = pendingDelete {
                if isRecoloring(c) { recoloring = nil }
                withAnimation(.smooth(duration: 0.3)) { context.delete(c) }
            }
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        switch step {
        case .edit:
            SheetHeader(title: "Edit collections") {
                SheetIconButton(systemImage: "checkmark", label: "Done editing") {
                    commitRename()
                    onDone()
                }
            }
        case .name:
            SheetHeader(leading: .back, title: "New collection", onLeading: backToEdit) {
                SheetTrailingButton(title: "Save", action: create)
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.4 : 1)
            }
        }
    }

    // MARK: Bottom bar

    /// Cancel and Done while a name has changed; the swatches while a dot is
    /// tapped; New collection otherwise.
    @ViewBuilder private var bottomBar: some View {
        switch step {
        case .edit:
            if renameChanged {
                HStack(spacing: 12) {
                    Button(action: cancelRename) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundStyle(.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Theme.control, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    Button(action: commitRename) {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(Theme.page)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.ink, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.blurFade)
            } else if let c = recoloring {
                swatchBar(for: c)
                    .id(c.persistentModelID)
                    .transition(.blurFade)
            } else {
                // A raised pill, same width as the rows above.
                Button(action: startNaming) {
                    Label("New collection", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Capsule())
                }
                .buttonStyle(RaisedButtonStyle(shape: Capsule()))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.blurFade)
            }
        case .name:
            EmptyView()
        }
    }

    // MARK: Colour

    /// The palette in a sideways scroll, each swatch the same two circles as the
    /// row's dot; the collection's current colour is ringed in ink.
    private func swatchBar(for c: WordCollection) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CollectionColor.allCases) { color in
                        let on = c.color == color
                        Button {
                            guard !on else { return }
                            recolors += 1
                            withAnimation(.snappy(duration: 0.3)) { c.color = color }
                        } label: {
                            CollectionDot(color: color, size: 44)
                                .padding(4)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.ink, lineWidth: 2)
                                        .opacity(on ? 1 : 0)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressStyle())
                        .id(color)
                        .accessibilityLabel(color.title)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(c.color, anchor: .center) }
        }
        .frame(height: 56)
        .padding(.top, 8)
    }

    private func isRecoloring(_ c: WordCollection) -> Bool {
        recoloring?.persistentModelID == c.persistentModelID
    }

    /// Tapping a row's dot opens the swatches for it; tapping it again closes them.
    private func toggleRecolor(_ c: WordCollection) {
        commitRename()
        recoloring = isRecoloring(c) ? nil : c
    }

    // MARK: Editing

    /// Full-width rows: dot drag handle on the left, the colour dot (tap to
    /// recolour), the name (dashed underline: tap to edit in place), trash on
    /// the right. Reordering is a custom drag so the handle can sit inside the row.
    private var editList: some View {
        ScrollView {
            VStack(spacing: Self.rowGap) {
                // The array never changes mid-drag: the lifted row follows the
                // finger by offset and the others shift a slot by offset, so each
                // row (title included) moves as one piece. The array reorders on
                // release, in the same frame the offsets reset.
                ForEach(Array(editOrder.enumerated()), id: \.element.persistentModelID) { i, c in
                    let lifted = dragging?.persistentModelID == c.persistentModelID
                    editRow(c)
                        .offset(y: lifted ? dragY : shift(for: i))
                        .scaleEffect(lifted ? 1.02 : 1)
                        .shadow(color: .black.opacity(lifted ? 0.15 : 0), radius: 12, y: 4)
                        .zIndex(lifted ? 1 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .sheetEdgeFade { header }
        .scrollDisabled(dragging != nil)
    }

    static let rowShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    private static let rowHeight: CGFloat = 60
    private static let rowGap: CGFloat = 8
    private static var rowPitch: CGFloat { rowHeight + rowGap }

    private func editRow(_ c: WordCollection) -> some View {
        let editing = renaming?.persistentModelID == c.persistentModelID
        return HStack(spacing: 12) {
            dragHandle(for: c)
            colorButton(for: c)
            if editing {
                TextField("Name", text: $renameText)
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .focused($renameFocused)
                    .submitLabel(.done)
                    .onSubmit(commitRename)
            } else {
                Button { beginRename(c) } label: {
                    Text(c.name)
                        .font(.headline)
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) { DashedUnderline() }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits the name")
            }
            Spacer(minLength: 8)
            Button { pendingDelete = c } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.ink3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(c.name)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: Self.rowHeight)
        .background(Theme.row, in: Self.rowShape)
    }

    /// The row's colour dot; ringed in ink while its swatches are open.
    private func colorButton(for c: WordCollection) -> some View {
        let on = isRecoloring(c)
        return Button { toggleRecolor(c) } label: {
            CollectionDot(color: c.color)
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(Color.ink, lineWidth: 1.5)
                        .opacity(on ? 1 : 0)
                }
                .frame(width: 28, height: Self.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Colour: \(c.color.title)")
        .accessibilityHint(on ? "Closes the colours" : "Shows colours to choose from")
    }

    /// Six-dot grip. Dragging it lifts the row and the others slide aside.
    private func dragHandle(for c: WordCollection) -> some View {
        GripDots()
            .foregroundStyle(.ink3)
            .frame(width: 24, height: Self.rowHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragging == nil {
                            commitRename()
                            withAnimation(.smooth(duration: 0.15)) { dragging = c }
                            dragStart = index(of: c)
                            dragTarget = dragStart
                        }
                        // 1:1 with the finger, never animated.
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { dragY = value.translation.height }
                        let slot = dragStart + Int((dragY / Self.rowPitch).rounded())
                        let target = min(max(slot, 0), editOrder.count - 1)
                        if target != dragTarget {
                            withAnimation(.smooth(duration: 0.2)) { dragTarget = target }
                        }
                    }
                    .onEnded { _ in drop() }
            )
            .accessibilityLabel("Reorder \(c.name)")
            .accessibilityAdjustableAction { direction in
                let i = index(of: c)
                let target = direction == .increment ? i + 1 : i - 1
                guard target >= 0, target < editOrder.count else { return }
                editOrder.move(fromOffsets: [i], toOffset: target > i ? target + 1 : target)
                saveEditOrder()
            }
    }

    private func index(of c: WordCollection) -> Int {
        editOrder.firstIndex { $0.persistentModelID == c.persistentModelID } ?? 0
    }

    /// How far a resting row slides to make room for the lifted one.
    private func shift(for i: Int) -> CGFloat {
        guard dragging != nil else { return 0 }
        if dragStart < dragTarget, i > dragStart, i <= dragTarget { return -Self.rowPitch }
        if dragTarget < dragStart, i >= dragTarget, i < dragStart { return Self.rowPitch }
        return 0
    }

    /// Reorders the array and rebases the lifted row's offset in one frame
    /// (nothing jumps), then settles it into its slot.
    private func drop() {
        guard dragging != nil else { return }
        let from = dragStart, to = dragTarget
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if to != from {
                editOrder.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
            }
            dragY -= CGFloat(to - from) * Self.rowPitch
            dragStart = to
        }
        saveEditOrder()
        withAnimation(.smooth(duration: 0.25)) {
            dragY = 0
        } completion: {
            withAnimation(.smooth(duration: 0.15)) { dragging = nil }
        }
    }

    /// From 1: Favorites sits at 0 or below, so it stays first everywhere else.
    private func saveEditOrder() {
        for (i, c) in editOrder.enumerated() { c.order = i + 1 }
    }

    private func syncEditOrder() {
        guard dragging == nil else { return }
        editOrder = collections.filter { !$0.isFavorites }
    }

    private func beginRename(_ c: WordCollection) {
        commitRename()
        recoloring = nil
        renameText = c.name
        renaming = c
        renameFocused = true
    }

    private var renameChanged: Bool {
        guard let c = renaming else { return false }
        return renameText.trimmingCharacters(in: .whitespaces) != c.name
    }

    private func cancelRename() {
        renaming = nil
        renameFocused = false
    }

    /// Saves the in-place name; an empty name keeps the old one.
    private func commitRename() {
        guard let c = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { c.name = name }
        renaming = nil
        renameFocused = false
    }

    // MARK: Naming

    private var nameField: some View {
        TextField("", text: $newName, prompt: Text("Collection name").foregroundStyle(.ink4))
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit(create)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 16)
    }

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    private func startNaming() {
        recoloring = nil
        step = .name
        nameFocused = true
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        let c = WordCollection(name: trimmedName, order: WordCollection.nextOrder(in: context),
                               color: WordCollection.nextColor(among: collections.filter { !$0.isFavorites }))
        context.insert(c)
        word?.collections.append(c)
        creates += 1
        backToEdit()
    }

    /// Naming returns to the list.
    private func backToEdit() {
        nameFocused = false
        newName = ""
        step = .edit
    }
}

/// A 1pt dashed line under a tappable title.
private struct DashedUnderline: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: g.size.width, y: 0.5))
            }
            .stroke(Color.ink4, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
    }
}

/// Six dots in two columns: the drag grip.
private struct GripDots: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 4, height: 4)
                    Circle().frame(width: 4, height: 4)
                }
            }
        }
    }
}

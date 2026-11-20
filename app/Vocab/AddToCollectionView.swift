import SwiftUI
import SwiftData

/// Opened by pulling a deck card down. Ported from the old app's "Save to"
/// modal: a list of collections, with a wide Done pill at the bottom while
/// the word is saved. New collections are made from Edit.
///
/// Edit (top right) switches to an editable list where collections can be
/// renamed (tap), deleted, and dragged into a new order. Favorites is built in:
/// it is pinned first and can't be renamed, moved or deleted.
struct AddToCollectionView: View {
    let word: Word

    @Environment(\.modelContext) private var context
    @Environment(\.sheetDismiss) private var dismiss
    @Query(sort: WordCollection.userOrder) private var collections: [WordCollection]

    private enum Step { case pick, edit, name }
    @State private var step = Step.pick
    @State private var newName = ""
    /// Bumps on every toggle: drives the haptic.
    @State private var toggles = 0
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

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                switch step {
                case .pick: grid.transition(.blurFade)
                case .edit: editList.transition(.blurFade)
                case .name: nameField.transition(.blurFade)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            bottomBar
        }
        .animation(.smooth(duration: 0.3), value: step)
        .animation(.smooth(duration: 0.3), value: isSaved)
        .sensoryFeedback(.selection, trigger: toggles)
        .task { WordCollection.ensureFavorites(in: context) }
        // An unchanged name just closes when the field loses focus; a changed
        // one waits for Done or Cancel at the bottom.
        .onChange(of: renameFocused) { _, focused in
            if !focused && !renameChanged { renaming = nil }
        }
        .onChange(of: collections.map(\.persistentModelID), initial: true) { syncEditOrder() }
        .animation(.smooth(duration: 0.25), value: renameChanged)
        .confirmationDialog("Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete collection", role: .destructive) {
                if let c = pendingDelete, !c.isFavorites {
                    withAnimation(.smooth(duration: 0.3)) { context.delete(c) }
                }
                pendingDelete = nil
            }
        } message: {
            Text("Its words stay in your library.")
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        switch step {
        case .pick:
            SheetHeader(title: "Save to") {
                SheetIconButton(systemImage: "pencil", label: "Edit collections") { step = .edit }
            }
        case .edit:
            SheetHeader(title: "Edit collections") {
                SheetIconButton(systemImage: "checkmark", label: "Done editing") {
                    commitRename()
                    step = .pick
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

    // MARK: Picker

    /// Filled rounded rows: icon, name with its word count beside it, check.
    private var grid: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(collections) { c in
                    let selected = contains(c)
                    Button { toggle(c) } label: {
                        CollectionRow(collection: c) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? AnyShapeStyle(Color.ink) : AnyShapeStyle(Color.ink4))
                                // Checking animates; unchecking is instant.
                                .contentTransition(selected ? .symbolEffect(.replace) : .identity)
                        }
                        .background(Theme.control, in: Self.rowShape)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    static let rowShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    /// Picking: Done while the word is in any collection, nothing otherwise.
    /// Editing: the dashed New collection button.
    @ViewBuilder private var bottomBar: some View {
        switch step {
        case .pick:
            if isSaved {
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(Theme.page)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.ink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.blurFade)
            }
        case .edit:
            if renameChanged {
                HStack(spacing: 12) {
                    Button(action: cancelRename) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundStyle(.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Theme.control, in: Self.rowShape)
                            .contentShape(Self.rowShape)
                    }
                    .buttonStyle(PressStyle())
                    Button(action: commitRename) {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(Theme.page)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.ink, in: Self.rowShape)
                            .contentShape(Self.rowShape)
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.blurFade)
            } else {
                // A filled button inside a dashed outline, a few points out.
                Button(action: startNaming) {
                    Label("New collection", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(.ink3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.ink4.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.blurFade)
            }
        case .name:
            EmptyView()
        }
    }

    // MARK: Editing

    /// Full-width rows: dot drag handle on the left, the name (dashed
    /// underline: tap to edit in place), trash on the right. Favorites is
    /// built in: greyed out, pinned first, no handle and no trash.
    /// Reordering is a custom drag so the handle can sit inside the row.
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
        .scrollDisabled(dragging != nil)
    }

    private static let rowHeight: CGFloat = 60
    private static let rowGap: CGFloat = 8
    private static var rowPitch: CGFloat { rowHeight + rowGap }

    private func editRow(_ c: WordCollection) -> some View {
        let editing = renaming?.persistentModelID == c.persistentModelID
        return HStack(spacing: 12) {
            if c.isFavorites {
                Image(systemName: "heart.fill")
                    .font(.body).foregroundStyle(.ink3)
                    .frame(width: 24)
            } else {
                dragHandle(for: c)
            }
            if editing {
                TextField("Name", text: $renameText)
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .focused($renameFocused)
                    .submitLabel(.done)
                    .onSubmit(commitRename)
            } else if c.isFavorites {
                Text(c.name).font(.headline).foregroundStyle(.ink)
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
            // Favorites is built in: no delete, so no trash.
            if !c.isFavorites {
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
        }
        .opacity(c.isFavorites ? 0.3 : 1)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: Self.rowHeight)
        .background(Theme.control.opacity(c.isFavorites ? 0.5 : 1), in: Self.rowShape)
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
                        let target = min(max(slot, firstMovable), editOrder.count - 1)
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
                guard target >= firstMovable, target < editOrder.count else { return }
                editOrder.move(fromOffsets: [i], toOffset: target > i ? target + 1 : target)
                saveEditOrder()
            }
    }

    /// Favorites holds slot 0 when present.
    private var firstMovable: Int { editOrder.first?.isFavorites == true ? 1 : 0 }

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

    private func saveEditOrder() {
        for (i, c) in editOrder.enumerated() { c.order = i }
    }

    private func syncEditOrder() {
        guard dragging == nil else { return }
        editOrder = collections
    }

    private func beginRename(_ c: WordCollection) {
        commitRename()
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

    // MARK: Actions

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    private func contains(_ c: WordCollection) -> Bool {
        word.collections.contains { $0.persistentModelID == c.persistentModelID }
    }

    private func toggle(_ c: WordCollection) {
        if contains(c) { word.collections.removeAll { $0.persistentModelID == c.persistentModelID } }
        else { word.collections.append(c) }
        toggles += 1
    }

    private func startNaming() {
        step = .name
        nameFocused = true
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        let c = WordCollection(name: trimmedName, order: WordCollection.nextOrder(in: context))
        context.insert(c)
        word.collections.append(c)
        toggles += 1
        backToEdit()
    }

    private var isSaved: Bool { collections.contains(where: contains) }

    /// New collections are made from Edit, so naming returns there.
    private func backToEdit() {
        nameFocused = false
        newName = ""
        step = .edit
    }
}

/// One collection: icon slot, name in semibold with its word count beside it
/// in faded ink, then a trailing control.
private struct CollectionRow<Trailing: View>: View {
    let collection: WordCollection
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            // Same-width icon slot on every row so the names line up.
            Image(systemName: collection.isFavorites ? "heart.fill" : "rectangle.stack")
                .font(.body).foregroundStyle(.ink3)
                .frame(width: 24)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(collection.name).font(.headline).foregroundStyle(.ink)
                Text("\(collection.words.count)").font(.body).foregroundStyle(.ink3)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .contentShape(Rectangle())
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

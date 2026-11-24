import SwiftUI
import SwiftData

/// Opened by pulling a deck card down. Ported from the old app's "Save to"
/// modal: a list of collections, with a wide Done pill at the bottom while
/// the word is saved. New collections are made from Edit.
///
/// Edit (top right) opens the shared `CollectionEditor`, the same one the
/// menu's Collections page uses.
struct AddToCollectionView: View {
    let word: Word

    @Environment(\.modelContext) private var context
    @Environment(\.sheetDismiss) private var dismiss
    @Query(sort: WordCollection.userOrder) private var collections: [WordCollection]

    private enum Step { case pick, edit }
    @State private var step = Step.pick
    /// Bumps on every toggle: drives the haptic.
    @State private var toggles = 0

    var body: some View {
        ZStack(alignment: .top) {
            switch step {
            case .pick:
                VStack(spacing: 0) {
                    grid.frame(maxHeight: .infinity, alignment: .top)
                    doneBar
                        // Only the Done button eases in and out; the rows update instantly.
                        .animation(.smooth(duration: 0.3), value: isSaved)
                }
                .transition(.blurFade)
            case .edit:
                CollectionEditor(word: word) { step = .pick }
                    .transition(.blurFade)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.3), value: step)
        .sensoryFeedback(.selection, trigger: toggles)
        .task {
            WordCollection.ensureDefaults(in: context)
            #if DEBUG
            // -autoToggle: toggles the first collection repeatedly so -hitchLog can
            // measure what one selection costs on device.
            if ProcessInfo.processInfo.arguments.contains("-autoToggle") {
                try? await Task.sleep(for: .seconds(1.5))
                for _ in 0..<8 {
                    guard let c = collections.first else { break }
                    HitchMonitor.shared.mark()
                    let t0 = CACurrentMediaTime()
                    toggle(c)
                    print(String(format: "TOGGLE sync=%.2fms", (CACurrentMediaTime() - t0) * 1000))
                    try? await Task.sleep(for: .milliseconds(700))
                }
            }
            #endif
        }
    }

    private var header: some View {
        SheetHeader(title: "Save to") {
            SheetIconButton(systemImage: "pencil", label: "Edit collections") { step = .edit }
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
                                // Instant both ways: a selection should read the moment
                                // the finger lifts. The haptic and press carry the feel.
                                .contentTransition(.identity)
                        }
                        .background(Theme.row, in: Self.rowShape)
                        // The press spring runs in the same update as the toggle
                        // (release fires both), so it was easing the check and the
                        // count. Strip it here: only the row's scale animates.
                        .transaction { $0.animation = nil }
                    }
                    .buttonStyle(PressStyle(pressedScale: 0.97))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .sheetEdgeFade { header }
    }

    static let rowShape = CollectionEditor.rowShape

    /// Done while the word is in any collection, nothing otherwise.
    @ViewBuilder private var doneBar: some View {
        if isSaved {
            // A raised pill, like New collection.
            Button { dismiss() } label: {
                Text("Done")
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
    }

    // MARK: Actions

    private func contains(_ c: WordCollection) -> Bool {
        word.collections.contains { $0.persistentModelID == c.persistentModelID }
    }

    private func toggle(_ c: WordCollection) {
        if contains(c) { word.collections.removeAll { $0.persistentModelID == c.persistentModelID } }
        else { word.collections.append(c) }
        toggles += 1
    }

    private var isSaved: Bool { collections.contains(where: contains) }
}

/// One collection: heart or colour dot, name in semibold with its word count beside it
/// in faded ink, then a trailing control.
private struct CollectionRow<Trailing: View>: View {
    let collection: WordCollection
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            // Same-width icon slot on every row so the names line up.
            Group {
                if collection.isFavorites {
                    Image(systemName: "heart").font(.body).foregroundStyle(.ink3)
                } else {
                    CollectionDot(color: collection.color)
                }
            }
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

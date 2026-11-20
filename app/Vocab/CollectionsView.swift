import SwiftUI
import SwiftData

struct CollectionsView: View {
    @Binding var selected: WordCollection?
    var onStudy: (WordCollection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: WordCollection.userOrder) private var collections: [WordCollection]
    @Query private var words: [Word]

    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Button { selected = nil; dismiss() } label: {
                    row("All words", count: words.count, isSelected: selected == nil)
                }
                Section("Collections") {
                    ForEach(collections) { c in
                        HStack {
                            Button { selected = c; dismiss() } label: {
                                row(c.name, count: c.words.count, isSelected: selected?.persistentModelID == c.persistentModelID)
                            }
                            Button("Study") { onStudy(c) }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(Theme.control, in: Capsule())
                                .buttonStyle(.borderless)
                                .disabled(c.words.isEmpty)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            if selected?.persistentModelID == collections[i].persistentModelID { selected = nil }
                            context.delete(collections[i])
                        }
                    }
                    Button { naming = true } label: { Label("New collection", systemImage: "plus") }
                }
                Section("Words in this view") {
                    ForEach(visibleWords) { w in
                        WordRow(word: w, collections: collections)
                    }
                    .onDelete { offsets in
                        let list = visibleWords
                        for i in offsets { context.delete(list[i]) }
                    }
                }
            }
            .foregroundStyle(.ink)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .alert("New collection", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { context.insert(WordCollection(name: name, order: WordCollection.nextOrder(in: context))) }
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
    }

    private var visibleWords: [Word] {
        guard let selected else { return words.sorted { $0.text < $1.text } }
        return selected.words.sorted { $0.text < $1.text }
    }

    private func row(_ title: String, count: Int, isSelected: Bool) -> some View {
        HStack {
            Text(title).fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)").foregroundStyle(.ink3)
            if isSelected { Image(systemName: "checkmark").foregroundStyle(.ink3) }
        }
        .contentShape(Rectangle())
    }
}

/// A word with a menu to toggle its collections.
struct WordRow: View {
    let word: Word
    let collections: [WordCollection]

    var body: some View {
        Menu {
            ForEach(collections) { c in
                let member = word.collections.contains { $0.persistentModelID == c.persistentModelID }
                Button {
                    if member { word.collections.removeAll { $0.persistentModelID == c.persistentModelID } }
                    else { word.collections.append(c) }
                } label: {
                    Label(c.name, systemImage: member ? "checkmark" : "")
                }
            }
        } label: {
            HStack {
                Text(word.text)
                Spacer()
                Text(word.reps == 0 ? "new" : "due \(word.due.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.ink3)
            }
            .contentShape(Rectangle())
        }
    }
}

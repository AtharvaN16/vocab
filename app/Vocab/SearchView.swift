import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var saved: [Word]
    @Query(sort: \WordCollection.createdAt) private var collections: [WordCollection]

    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var selected: String?
    @State private var senses: [Sense] = []
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search any word", text: $query)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { open(query) }
                }
                .padding(.horizontal, 16).frame(height: 50)
                .background(Theme.control, in: Capsule())
                Button("Cancel") { dismiss() }.foregroundStyle(.primary)
            }
            .padding(20)

            if let selected {
                result(for: selected)
            } else {
                List(suggestions, id: \.self) { s in
                    Button(s) { open(s) }.foregroundStyle(.primary)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .background(Theme.page.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: query) { selected = nil }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            suggestions = (try? await Wiktionary.suggestions(for: query)) ?? []
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                query = "petrichor"
                try? await Task.sleep(for: .milliseconds(50))
                open("petrichor")
            }
            #endif
        }
    }

    @ViewBuilder
    private func result(for word: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(word).font(.system(size: 40, weight: .bold))
                    Spacer()
                    addControl(word)
                }
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary) }
                ForEach(Array(senses.enumerated()), id: \.offset) { _, s in SenseView(sense: s) }
                if !senses.isEmpty {
                    Text("From Wiktionary, CC BY-SA 4.0").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func addControl(_ word: String) -> some View {
        if saved.contains(where: { $0.text == word }) {
            Label("Saved", systemImage: "checkmark").font(.headline).foregroundStyle(.secondary)
        } else if !senses.isEmpty {
            Menu {
                Button("Just add") { add(word, to: nil) }
                ForEach(collections) { c in
                    Button("Add to \(c.name)") { add(word, to: c) }
                }
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.headline).padding(.horizontal, 18).frame(height: 44)
                    .background(Theme.control, in: Capsule())
            } primaryAction: {
                add(word, to: nil)
            }
            .foregroundStyle(.primary)
        }
    }

    private func open(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        selected = w
        senses = []
        error = nil
        loading = true
        focused = false
        Task {
            do { senses = try await Wiktionary.lookup(w) }
            catch { self.error = "Couldn't find “\(w)”. \(error.localizedDescription)" }
            loading = false
        }
    }

    private func add(_ text: String, to collection: WordCollection?) {
        let word = Word(text: text, senses: senses)
        context.insert(word)
        if let collection { word.collections.append(collection) }
        try? context.save()
    }
}

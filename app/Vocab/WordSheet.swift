import SwiftUI
import SwiftData

/// A word picked in Search, shown in the pushback sheet: the word with its
/// pronunciation, the AI's reason if it suggested the word, the first senses
/// from Wiktionary, and Add.
struct WordSheet: View {
    let pick: SearchPick
    /// Runs a question about this word back in Search.
    var onAsk: ((String) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.sheetDismiss) private var dismiss
    @Query private var saved: [Word]
    @Query(sort: WordCollection.userOrder) private var collections: [WordCollection]

    @State private var senses: [Sense] = []
    @State private var loading = true
    @State private var error: String?
    @State private var adds = 0

    private var isSaved: Bool { saved.contains { $0.text.lowercased() == pick.text.lowercased() } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        Text(pick.text)
                            .font(Theme.wordFont)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                        Button { Speaker.say(pick.text) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(Theme.control, in: Circle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Pronounce \(pick.text)")
                        Spacer(minLength: 0)
                    }

                    if let note = pick.note {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "sparkle").font(.footnote.weight(.semibold))
                            Text(note)
                        }
                        .font(.callout)
                        .foregroundStyle(.ink3)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if loading {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                    } else if let error {
                        Text(error).font(.callout).foregroundStyle(.ink3)
                    }
                    ForEach(Array(senses.prefix(3).enumerated()), id: \.offset) { _, s in SenseView(sense: s) }
                    if !senses.isEmpty {
                        Text("From Wiktionary · CC BY-SA 4.0")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.ink4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .animation(.easeOut(duration: 0.2), value: loading)
            }
            .scrollBounceBehavior(.basedOnSize)

            actions
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .sensoryFeedback(.success, trigger: adds)
        .task(id: pick.text) { await load() }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            // Words the AI suggested already have their reason; plain lookups can ask.
            if pick.note == nil, let onAsk {
                Button {
                    dismiss()
                    onAsk("How do I use “\(pick.text)” well, and what are its closest alternatives?")
                } label: {
                    Label("Ask about it", systemImage: "sparkle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.control, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }

            if isSaved {
                Label("Saved", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.ink3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.control, in: Capsule())
                    .transition(.opacity)
            } else {
                Menu {
                    Button("Just add") { add(to: nil) }
                    ForEach(collections) { c in
                        Button("Add to \(c.name)") { add(to: c) }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(Theme.page)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.ink, in: Capsule())
                } primaryAction: {
                    add(to: nil)
                }
                .disabled(senses.isEmpty)
                .opacity(senses.isEmpty ? 0.4 : 1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isSaved)
    }

    private func load() async {
        loading = true
        error = nil
        do { senses = try await Wiktionary.lookup(pick.text) }
        catch { self.error = "“\(pick.text)” isn’t in Wiktionary, so it can’t be added yet." }
        loading = false
    }

    private func add(to collection: WordCollection?) {
        guard !senses.isEmpty, !isSaved else { return }
        let word = Word(text: pick.text, senses: senses)
        context.insert(word)
        if let collection { word.collections.append(collection) }
        try? context.save()
        adds += 1
    }
}

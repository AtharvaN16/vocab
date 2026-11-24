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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        Text(pick.text)
                            .font(Theme.wordFont)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                        Button { Speaker.say(pick.text) } label: {
                            Image(systemName: "speaker.wave.2")
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
            .sheetEdgeFade { SheetHeader() }

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

/// A word tapped in Search, formed in front of you as the deck card it would become,
/// Ask AI and Add under it and Back near the bottom of the screen. Its definition comes from Wiktionary while the
/// card is still soft. Add sends the card up to the deck; Ask AI hands the word to the
/// Ask panel as the card blurs out; Back (or a tap around it) drops it back the way it
/// came, and Search comes back up ready for the next word.
struct SearchWordStage: View {
    let pick: SearchPick
    /// Asks a question about the word in the Ask panel under Search.
    let onAsk: (String) -> Void
    /// The card has left: clear the pick.
    let onDone: () -> Void
    /// The word was saved and its card is on its way up.
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query private var saved: [Word]
    @Query(sort: WordCollection.userOrder) private var collections: [WordCollection]

    @State private var job: GenerateJob
    @State private var senses: [Sense] = []
    @State private var exit: StageExit?
    /// Read once, so adding doesn't swap Add for Saved while the actions fade.
    @State private var wasSaved = false
    @State private var adds = 0

    init(pick: SearchPick, onAsk: @escaping (String) -> Void, onDone: @escaping () -> Void,
         onSaved: @escaping () -> Void = {}) {
        self.pick = pick
        self.onAsk = onAsk
        self.onDone = onDone
        self.onSaved = onSaved
        _job = State(initialValue: GenerateJob(tag: PillTag(kind: .word, payload: pick.text), hostWord: ""))
    }

    var body: some View {
        GenerateStage(job: job, actions: AnyView(actions), actionsHeight: 56,
                      back: AnyView(backButton), exit: exit,
                      onDismiss: { exit = .drop },
                      onLanded: {}, onDone: onDone)
            .sensoryFeedback(.success, trigger: adds)
            .onAppear { wasSaved = saved.contains { $0.text.lowercased() == pick.text.lowercased() } }
            .task { await load() }
    }

    /// Closes the card; Search comes back up for the next word.
    private var backButton: some View {
        Button { exit = .drop } label: {
            Text("Back")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 28)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    /// Ask AI and Add side by side, in the deck card's long-press row style.
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                exit = .fade
                onAsk("How do I use “\(pick.text)” well, and what are its closest alternatives?")
            } label: {
                // The app's solid button grey: no see-through tint over the fog.
                row("Ask AI", systemImage: "sparkle", ink: .ink, fill: Theme.control)
            }
            .buttonStyle(PressStyle(pressedScale: 0.97))

            if wasSaved {
                row("Saved", systemImage: "checkmark", ink: .ink3, fill: Color.ink.opacity(0.16))
            } else {
                Menu {
                    Button("Just add") { add(to: nil) }
                    ForEach(collections) { c in
                        Button("Add to \(c.name)") { add(to: c) }
                    }
                } label: {
                    row("Add", systemImage: "plus", ink: Theme.page, fill: .ink)
                } primaryAction: {
                    add(to: nil)
                }
                .disabled(senses.isEmpty)
                .opacity(senses.isEmpty ? 0.4 : 1)
            }
        }
    }

    private func row(_ title: String, systemImage: String, ink: Color, fill: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill, in: Theme.cardActionShape)
        .contentShape(Theme.cardActionShape)
    }

    private func load() async {
        do {
            senses = try await Wiktionary.lookup(pick.text)
            job.body = SenseRanker.primary(senses, tags: nil)?.definition ?? senses.first?.definition
                ?? "No definition found."
        } catch {
            // Said on the card, so it lands now instead of waiting out the definition.
            job.body = "Not in Wiktionary, so it can’t be added yet."
        }
    }

    private func add(to collection: WordCollection?) {
        guard !senses.isEmpty, exit == nil else { return }
        let word = Word(text: pick.text, senses: senses)
        context.insert(word)
        if let collection { word.collections.append(collection) }
        try? context.save()
        adds += 1
        exit = .toDeck
        onSaved()
    }
}

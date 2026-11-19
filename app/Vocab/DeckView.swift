import SwiftUI
import SwiftData

struct DeckView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Word.createdAt, order: .reverse) private var allWords: [Word]

    @State private var collection: WordCollection?
    @State private var shuffledOrder: [String]?
    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var showSearch = false
    @State private var showCollections = false
    @State private var askWord: Word?
    @State private var studyCollection: WordCollection?

    private var words: [Word] {
        var base = allWords
        if let collection {
            let id = collection.persistentModelID
            base = base.filter { $0.collections.contains { $0.persistentModelID == id } }
        }
        if let order = shuffledOrder {
            let pos = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            base.sort { (pos[$0.text] ?? .max) < (pos[$1.text] ?? .max) }
        }
        return base
    }

    var body: some View {
        let words = self.words
        let i = min(index, max(words.count - 1, 0))
        VStack(spacing: 18) {
            Text(caption(count: words.count, i: i))
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .contentTransition(.numericText())

            GeometryReader { geo in
                ZStack {
                    gestureHints
                    if words.isEmpty {
                        emptyCard
                    } else {
                        behindCard(words: words, i: i, width: geo.size.width)
                        SwipeCard(offset: $offset, allowed: allowed(words: words, i: i),
                                  flyOff: [.left, .right]) { dir in
                            handle(dir, words: words, i: i)
                        } content: {
                            CardFace(word: words[i])
                        }
                        .id(words[i].text)
                    }
                }
            }

            bottomBar
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .background(Theme.page.ignoresSafeArea())
        .sheet(isPresented: $showSearch) { SearchView() }
        .sheet(item: $askWord) { AskView(word: $0) }
        .sheet(isPresented: $showCollections) {
            CollectionsView(selected: $collection) { c in
                showCollections = false
                studyCollection = c
            }
        }
        .fullScreenCover(item: $studyCollection) { StudyView(collection: $0) }
        .onChange(of: collection) { index = 0; shuffledOrder = nil }
        .task { await debugHooks() }
    }

    // MARK: Pieces

    private func caption(count: Int, i: Int) -> String {
        let name = collection?.name ?? "All words"
        return count == 0 ? name : "\(name) · \(i + 1) of \(count)"
    }

    /// Labels uncovered as the card is pulled vertically; opacity is derived
    /// from the drag offset so they can never drift from the gesture.
    private var gestureHints: some View {
        let pull = offset.height
        return VStack {
            Label("Search", systemImage: "magnifyingglass")
                .opacity(Double(min(1, max(0, pull / 60))))
            Spacer()
            Label("Ask AI", systemImage: "sparkles")
                .opacity(Double(min(1, max(0, -pull / 60))))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func behindCard(words: [Word], i: Int, width: CGFloat) -> some View {
        let dx = offset.width
        let neighbor = dx < 0 ? i + 1 : i - 1
        if dx != 0, words.indices.contains(neighbor) {
            let progress = min(1, abs(dx) / width)
            CardFace(word: words[neighbor])
                .scaleEffect(0.92 + 0.08 * progress)
                .opacity(Double(progress))
        }
    }

    private var emptyCard: some View {
        SwipeCard(offset: $offset, allowed: [.down], flyOff: []) { _ in
            showSearch = true
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text("No words yet").font(.system(size: 40, weight: .bold))
                Text("Pull down or tap + to search for a word worth keeping.")
                    .font(.system(.title3, design: .serif)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: Theme.cardShape)
        }
    }

    private var bottomBar: some View {
        HStack {
            CircleButton(systemImage: "line.3.horizontal", label: "Collections") { showCollections = true }
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0)) {
                    shuffledOrder = words.map(\.text).shuffled()
                    index = 0
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 28).frame(height: 64)
                    .background(Theme.control, in: Capsule())
            }
            .buttonStyle(PressStyle())
            Spacer()
            CircleButton(systemImage: "plus", label: "Add word") { showSearch = true }
        }
        .padding(.bottom, 8)
    }

    // MARK: Behaviour

    private func allowed(words: [Word], i: Int) -> Set<SwipeDirection> {
        var set: Set<SwipeDirection> = [.up, .down]
        if i < words.count - 1 { set.insert(.left) }
        if i > 0 { set.insert(.right) }
        return set
    }

    private func handle(_ dir: SwipeDirection, words: [Word], i: Int) {
        switch dir {
        case .left, .right:
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                index = dir == .left ? i + 1 : i - 1
                offset = .zero
            }
        case .up: askWord = words[i]
        case .down: showSearch = true
        }
    }

    private func debugHooks() async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-seedDemo"), allWords.isEmpty { await DemoSeed.run(context) }
        if let i = args.firstIndex(of: "-demo"), let screen = args[safe: i + 1] {
            try? await Task.sleep(for: .milliseconds(600))
            switch screen {
            case "search": showSearch = true
            case "ask": askWord = words.first
            case "study":
                studyCollection = try? context.fetch(FetchDescriptor<WordCollection>()).first
            case "collections": showCollections = true
            default: break
            }
        }
        #endif
    }
}

#if DEBUG
enum DemoSeed {
    static func run(_ context: ModelContext) async {
        let literary = WordCollection(name: "Literary")
        context.insert(literary)
        let words = ["lambent", "tacit", "belie", "susurrus", "crepuscular", "ineffable"]
        for (n, text) in words.enumerated() {
            guard let senses = try? await Wiktionary.lookup(text) else { continue }
            let w = Word(text: text, senses: senses, createdAt: .now.addingTimeInterval(Double(-n)))
            context.insert(w)
            w.collections.append(literary)
        }
        try? context.save()
    }
}
#endif

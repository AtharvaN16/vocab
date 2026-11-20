import SwiftUI
import SwiftData

struct DeckView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Word.createdAt, order: .reverse) private var allWords: [Word]
    @Query(filter: #Predicate<WordCollection> { $0.isFavorites }) private var favorites: [WordCollection]

    @State private var collection: WordCollection?
    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var showSearch = false
    /// A word picked in Search, open in the pushback sheet over it.
    @State private var searchPick: SearchPick?
    /// A question the word sheet sends back to Search.
    @State private var searchAsk: String?
    @State private var collectWord: Word?
    @State private var showCollections = false
    /// Ask AI is open: the card is parked at the top and the panel sits under it.
    @State private var askOpen = false
    @State private var studyCollection: WordCollection?
    @State private var detailWord: Word?
    @Namespace private var cardZoom
    @State private var safeTop: CGFloat = 0
    @State private var cardArea: CGRect = .zero
    /// Bumped when a pull on the Ask panel closes it, for the haptic.
    @State private var askPullCloses = 0
    /// Cards flicked away that are still flying off screen. They are drawn over the
    /// deck and ignore touches, so the next card is live the moment the finger lifts.
    @State private var flying: [FlyingCard] = []
    /// Which neighbour lies under the top card (see `trackUnderSide`).
    @State private var underSide: SwipeDirection?
    /// How far the card under the finger had come into focus when the last throw began.
    @State private var riseFrom: CGFloat = 1
    /// Fast swiping: this drag began within `quickWindow` of the last throw, or
    /// while a card was still flying. Its motion drops blur and fades (see `flip`).
    @State private var quick = false
    @State private var quickUntil: CFTimeInterval = 0
    /// Whether the last throw's rise was the simple one.
    @State private var riseSimple = false
    /// Held back after a delete so the deleted card's copy has mostly gone before the
    /// next card comes into focus: never two cards at different heights at once.
    @State private var riseDelay: Double = 0
    /// The word the hidden Ask panel was last built for (see `panelWord`).
    @State private var panelHold: Word?
    /// A long press lifted the card to show the delete button under it.
    @State private var deleteOpen = false
    /// The delete button is drawn under the card. It stays until the card has come
    /// back to rest, so it is covered rather than popping out mid return.
    @State private var deleteShown = false
    /// A deleted card's copy, dissolving where it was lifted (see `.vanish`).
    @State private var vanishing: VanishingCard?
    /// Bumped each time a word is favorited, to launch the heart (see `HeartBurst`).
    @State private var hearts = 0
    /// One heart per favorite, each with its own timeline, so a second favorite never
    /// yanks a heart that is still in flight back to the row.
    @State private var bursts: [UUID] = []
    /// Favorite was tapped and the card is holding for the heart's pop; the rows are done.
    @State private var rowsDone = false
    /// A completed delete: the rows stay fully revealed (not tied to the card, which has
    /// gone) and `rowsGone` fades them out with the card's copy, on its curve.
    @State private var rowsLeaving = false
    @State private var rowsGone = false
    /// Centre of the Favorite row's heart icon, from the row's centre. The burst starts here.
    @State private var heartIconX: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    private static let rowSpace = "actionRow"
    /// How long the lifted card waits after a favorite: until the heart's pop peaks, so
    /// you see the cause before the card covers it. It then descends as the heart rises.
    private let heartHold = 0.25

    /// How much of the card stays visible below the status bar while Ask AI is open.
    private let askPeek: CGFloat = 44
    /// Space between the parked card and the top of the Ask sheet.
    private let askGap: CGFloat = 12
    private let deleteHeight: CGFloat = 56
    /// Between the rows, and between the top row and the lifted card.
    private let rowGap: CGFloat = 12
    /// How far a long press lifts the card: the Favorite and Delete rows and their gaps.
    private var deleteLift: CGFloat { deleteHeight * 2 + rowGap * 2 }

    private var words: [Word] {
        var base = allWords
        if let collection {
            let id = collection.persistentModelID
            base = base.filter { $0.collections.contains { $0.persistentModelID == id } }
        }
        return base
    }

    var body: some View {
        let words = self.words
        let i = min(index, max(words.count - 1, 0))
        ZStack(alignment: .top) {
            deck(words: words, i: i)
                // The keyboard is for the Ask panel; the card must not resize under it.
                .ignoresSafeArea(.keyboard)
            if !words.isEmpty {
                askPanel(word: panelWord(words: words, i: i))
                    .task(id: words[i].persistentModelID) { await syncPanelWhenIdle(words[i]) }
            }
            if showSearch {
                SearchView(onClose: closeSearch, pick: $searchPick, askRequest: $searchAsk)
                    // The deck stays still; Search fades over it. Exits run faster than entrances.
                    .transition(.asymmetric(insertion: .opacity.animation(.strongEaseOut(0.25)),
                                            removal: .opacity.animation(.strongEaseOut(0.18))))
                    .zIndex(1)
            }
        }
        .background(Theme.page.ignoresSafeArea())
        .bottomSheet(item: $searchPick, size: .medium) { pick in
            WordSheet(pick: pick) { searchAsk = $0 }
        }
        .bottomSheet(item: $collectWord, size: .medium) { AddToCollectionView(word: $0) }
        .sheet(isPresented: $showCollections) {
            CollectionsView(selected: $collection) { c in
                showCollections = false
                studyCollection = c
            }
        }
        .fullScreenCover(item: $detailWord) { word in
            WordDetailView(word: word)
                .navigationTransition(.zoom(sourceID: word.text, in: cardZoom))
        }
        .fullScreenCover(item: $studyCollection) { StudyView(collection: $0) }
        .onChange(of: collection) { index = 0 }
        .task {
            WordCollection.ensureFavorites(in: context)
            await debugHooks()
        }
    }

    private func deck(words: [Word], i: Int) -> some View {
        VStack(spacing: 18) {
            Text(caption(count: words.count, i: i))
                .font(.footnote.weight(.medium)).foregroundStyle(.ink3)
                .contentTransition(.numericText())

            GeometryReader { geo in
                ZStack {
                    gestureHints
                    // While the card is lifted, a tap anywhere around it puts it back.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: closeDelete)
                        .allowsHitTesting(deleteOpen)
                        .accessibilityHidden(true)
                    if words.isEmpty {
                        emptyCard.frame(height: cardHeight(geo.size))
                    } else {
                        let width = geo.size.width
                        behindCard(words: words, i: i, width: width)
                            .frame(height: cardHeight(geo.size))
                        if deleteShown {
                            deleteButton(words[i])
                                .frame(height: cardHeight(geo.size), alignment: .bottom)
                                // Leaving, they fade over the next card instead of under it.
                                .zIndex(rowsLeaving ? 1 : 0)
                        }
                        SwipeCard(offset: $offset, allowed: allowed(words: words, i: i),
                                  flyOff: [], handOff: [.left, .right],
                                  park: [.up: askParkDistance],
                                  parked: askOpen || deleteOpen,
                                  onUnpark: unpark,
                                  onTap: { tapCard(words[i]) },
                                  onLongPress: openDelete,
                                  onHandOff: { dir, v in flip(dir, velocity: v, words: words, i: i, width: width) }) { dir in
                            handle(dir, words: words, i: i)
                        } content: {
                            CardFace(word: words[i])
                            .matchedTransitionSource(id: words[i].text, in: cardZoom) {
                                $0.background(Theme.card).clipShape(Theme.cardShape)
                            }
                        }
                        .accessibilityHint(askOpen ? "Closes Ask AI" : deleteOpen ? "Hides delete" : "Shows all definitions")
                        .accessibilityAction(named: "Delete") { openDelete() }
                        .frame(height: cardHeight(geo.size))
                        // After a throw the new top card arrives already risen to where the
                        // card under the finger was, and finishes coming into focus on the
                        // throw's own spring. The old top card is replaced by its thrown copy.
                        .id(words[i].text)
                        // Outside `.id`, or SwiftUI ignores it when the id changes.
                        .transition(.asymmetric(insertion: .rise(from: riseFrom, simple: riseSimple, delay: riseDelay), removal: .identity))
                        ForEach(flying) { card in
                            CardFace(word: card.word)
                                .frame(height: cardHeight(geo.size))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .offset(x: card.to)
                                // Starts moving in the release frame: inserted and animated in one update.
                                .transition(.asymmetric(insertion: .thrown(from: card.from - card.to, fades: !card.simple), removal: .identity))
                        }
                        vanishingCard(height: cardHeight(geo.size))
                        // Starts on the Favorite row's centre and flies over everything.
                        ZStack {
                            ForEach(bursts, id: \.self) { _ in
                                HeartBurst(iconX: heartIconX, travel: cardArea.maxY + 120, lead: heartHold)
                                    // Its keyframes are the whole entrance and exit.
                                    .transition(.identity)
                            }
                        }
                            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: hearts)
                            .frame(height: deleteHeight)
                            .padding(.bottom, deleteHeight + rowGap)
                            .frame(height: cardHeight(geo.size), alignment: .bottom)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardArea = $0 }
            .onChange(of: offset) { old, new in
                // Latched once per drag, so the look never switches mid-gesture.
                if old == .zero && new != .zero {
                    quick = CACurrentMediaTime() < quickUntil || !flying.isEmpty
                }
                trackUnderSide(new)
                if new == .zero && !deleteOpen && !rowsLeaving { deleteShown = false }
            }

            bottomBar
                .opacity(1 - askProgress)
                .allowsHitTesting(!askOpen && !deleteOpen)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { safeTop = $0 }
    }

    // MARK: Pieces

    /// Shorter than the available space; the gaps above and below reveal the pull hints.
    private func cardHeight(_ size: CGSize) -> CGFloat {
        min(size.height, size.width * 1.4)
    }

    /// How far the card slides up so only its bottom `askPeek` points show under the status bar.
    private var askParkDistance: CGFloat {
        let cardBottom = cardArea.minY + (cardArea.height + cardHeight(cardArea.size)) / 2
        return max(0, cardBottom - safeTop - askPeek)
    }

    /// 0 with the card at rest, 1 when parked. Everything in the Ask choreography
    /// derives from this, so dragging, releasing and interrupting stay in sync.
    private var askProgress: Double {
        if deleteShown { return 0 }
        guard askParkDistance > 0 else { return askOpen ? 1 : 0 }
        return Double(min(1, max(0, -offset.height / askParkDistance)))
    }

    /// Hangs off the card's bottom edge: it is laid out at its open position and
    /// pushed down by however far the card still has to travel, so the card carries it.
    private func askPanel(word: Word) -> some View {
        let p = askProgress
        return AskPanel(word: word, revealed: askOpen, onPull: pullAsk, onPullEnd: releaseAsk, onClose: closeAsk)
            .equatable()
            .sensoryFeedback(.impact(weight: .light), trigger: askPullCloses)
            .padding(.top, askPeek + askGap)
            .offset(y: askParkDistance + offset.height)
            // Fades in slightly behind the card so it reads as revealed, not pasted on.
            .opacity(min(1, max(0, (p - 0.1) / 0.6)))
            .allowsHitTesting(askOpen)
            .accessibilityHidden(!askOpen)
    }

    // MARK: Delete

    struct VanishingCard: Identifiable {
        let id = UUID()
        let title: String
        let definition: String?
        let y: CGFloat
    }

    /// Favorite over Delete, lying under the card's bottom edge and uncovered as the
    /// card lifts: Delete first, then Favorite. Each row's focus (opacity, blur, scale)
    /// is derived from the card's offset, so it stays in step whether the card is
    /// springing, being dragged back, or interrupted.
    private func deleteButton(_ word: Word) -> some View {
        let favorite = word.collections.contains { $0.isFavorites }
        return VStack(spacing: rowGap) {
            actionRow(favorite ? "Favorited" : "Favorite", systemImage: favorite ? "heart.fill" : "heart",
                      // Delete's tint treatment in grey, tinted with the ink itself (.gray barely
                      // shifts a light page). It stays tinted once favorited: the filled heart says it.
                      ink: .ink, fill: Color.ink.opacity(0.16),
                      row: 1) { toggleFavorite(word) }
                .accessibilityLabel(favorite ? "Remove \(word.text) from Favorites" : "Add \(word.text) to Favorites")
            HoldToDelete(height: deleteHeight) { delete(word) }
                .modifier(rowReveal(row: 0))
                .accessibilityLabel("Delete \(word.text)")
        }
        // Leaves with the deleted card's copy: same fade, blur and slight sink.
        .opacity(rowsGone ? 0 : 1)
        .blur(radius: rowsGone ? 8 : 0)
        .scaleEffect(rowsGone ? 0.94 : 1)
        .allowsHitTesting(deleteOpen && !rowsDone)
        .accessibilityHidden(!deleteOpen)
    }

    private func actionRow(_ title: String, systemImage: String, ink: Color, fill: Color,
                           row: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .contentTransition(.symbolEffect(.replace))
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.rowSpace)).midX } action: { x in
                        if row == 1 { heartIconX = x - rowWidth / 2 }
                    }
                Text(title)
            }
                .font(.body.weight(.semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .frame(height: deleteHeight)
                .background(fill, in: Theme.actionShape)
                .contentShape(Theme.actionShape)
                .coordinateSpace(.named(Self.rowSpace))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        }
        .buttonStyle(PressStyle(pressedScale: 0.97))
        .modifier(rowReveal(row: row))
    }

    /// `row` counts up from the card's bottom edge, the order the lift uncovers them.
    private func rowReveal(row: Int) -> RowReveal {
        if rowsLeaving { return RowReveal(p: 1) }
        let start = CGFloat(row) * (deleteHeight + rowGap)
        return RowReveal(p: min(1, max(0, (-offset.height - start) / (deleteHeight + rowGap))))
    }

    /// Fills the heart, then puts the card back; the change shows as it slides over.
    private func toggleFavorite(_ word: Word) {
        WordCollection.ensureFavorites(in: context)
        guard let fav = favorites.first ?? (try? context.fetch(FetchDescriptor<WordCollection>(
            predicate: #Predicate { $0.isFavorites })))?.first else { return }
        let adding = !word.collections.contains { $0.isFavorites }
        // Its own transaction: the tint flips on a short curve, together with the pop.
        withAnimation(.strongEaseOut(0.2)) {
            if adding {
                word.collections.append(fav)
                hearts += 1
                let id = UUID()
                bursts.append(id)
                Task {
                    try? await Task.sleep(for: .seconds(HeartBurst.length(lead: heartHold) + 0.1))
                    bursts.removeAll { $0 == id }
                }
            } else {
                word.collections.removeAll { $0.isFavorites }
            }
        }
        try? context.save()
        // Unfavoriting has nothing to watch: the card goes home at once.
        guard adding else { closeDelete(); return }
        rowsDone = true
        Task {
            try? await Task.sleep(for: .seconds(heartHold))
            rowsDone = false
            closeDelete(gentle: true) // no-op if a tap on the card already sent it home
        }
    }

    @ViewBuilder
    private func vanishingCard(height: CGFloat) -> some View {
        if let v = vanishing {
            CardFace(title: v.title, definition: v.definition)
                .frame(height: height)
                .offset(y: v.y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(v.id)
                .transition(.asymmetric(insertion: .vanish, removal: .identity))
        }
    }

    private func tapCard(_ word: Word) {
        if askOpen { closeAsk() } else if deleteOpen { closeDelete() } else { openDetail(word) }
    }

    private func unpark() {
        if deleteOpen { deleteOpen = false; return }
        askOpen = false
        dismissKeyboard()
    }

    private func openDelete() {
        guard !askOpen, !deleteOpen else { return }
        underSide = nil
        deleteShown = true
        deleteOpen = true
        withAnimation(.spring(duration: 0.3, bounce: 0)) { offset = CGSize(width: 0, height: -deleteLift) }
    }

    /// A plain dismiss is as quick as the lift. After a favorite (`gentle`) the card
    /// settles home unhurried, like Ask's return, so the heart's moment can breathe.
    private func closeDelete() { closeDelete(gentle: false) }

    private func closeDelete(gentle: Bool) {
        guard deleteOpen else { return }
        deleteOpen = false
        withAnimation(.spring(duration: gentle ? 0.45 : 0.3, bounce: 0)) { offset = .zero }
    }

    /// The card dissolves where it was lifted while the next one comes into focus
    /// under it, at rest. The button goes with the card.
    private func delete(_ word: Word) {
        let copy = VanishingCard(title: word.text,
                                 definition: SenseRanker.primary(word.senses, tags: word.details?.senseTags)?.definition,
                                 y: offset.height)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            deleteOpen = false
            rowsLeaving = true
            offset = .zero
            riseFrom = 0
            // The delete's own look, whatever the last swipe was.
            riseSimple = false
            riseDelay = 0.06
            if panelHold == word { panelHold = nil }
        }
        withAnimation(.strongEaseOut(0.22), completionCriteria: .logicallyComplete) {
            vanishing = copy
            rowsGone = true
            context.delete(word)
            try? context.save()
        } completion: {
            if vanishing?.id == copy.id { vanishing = nil }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                deleteShown = false
                rowsLeaving = false
                rowsGone = false
                riseDelay = 0
            }
        }
    }

    /// The zoom lifts the card off the deck, so nothing may be lying under it.
    private func openDetail(_ word: Word) {
        underSide = nil
        detailWord = word
    }

    private func openSearch() {
        withAnimation(.strongEaseOut(0.25)) { showSearch = true }
    }

    private func closeSearch() {
        dismissKeyboard()
        withAnimation(.strongEaseOut(0.18)) { showSearch = false }
    }

    private func closeAsk() {
        dismissKeyboard()
        askOpen = false
        withAnimation(.spring(duration: 0.45, bounce: 0)) { offset = .zero }
    }

    /// Dragging the Ask panel down carries the card with it 1:1; pulling up past
    /// the parked spot meets friction rather than a wall.
    private func pullAsk(_ dy: CGFloat) {
        let base = -askParkDistance
        let y = dy >= 0 ? min(0, base + dy) : base - rubberBand(-dy, limit: 60)
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { offset = CGSize(width: 0, height: y) }
    }

    /// Same commit rule as the parked card: far enough or a downward flick, unless
    /// the finger was heading back up on release. The spring inherits the finger's speed.
    private func releaseAsk(_ dy: CGFloat, _ vy: CGFloat) {
        let home = vy > 700 || (dy > 110 && vy > -300)
        let target: CGFloat = home ? 0 : -askParkDistance
        if home {
            askPullCloses += 1
            dismissKeyboard()
            askOpen = false
        }
        let remaining = target - offset.height
        let v = abs(remaining) > 1 ? Double(vy / remaining) : 0
        withAnimation(.interpolatingSpring(duration: 0.45, bounce: 0, initialVelocity: v)) {
            offset = CGSize(width: 0, height: target)
        }
    }

    private func rubberBand(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        (1 - 1 / (x * 0.55 / limit + 1)) * limit
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func caption(count: Int, i: Int) -> String {
        let name = collection?.name ?? "All words"
        return count == 0 ? name : "\(name) · \(i + 1) of \(count)"
    }

    /// Labels uncovered as the card is pulled vertically; opacity is derived
    /// from the drag offset so they can never drift from the gesture.
    private var gestureHints: some View {
        let pull = offset.height
        return VStack {
            Label("Add to collection", systemImage: "rectangle.stack.badge.plus")
                .opacity(Double(min(1, max(0, pull / 60))))
            Spacer()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.ink3)
        .padding(.vertical, 2)
    }

    // MARK: Moving between cards
    //
    // Both directions are mirror images. The top card follows the finger, solid,
    // and is thrown the way it was swiped; on release it fades out much faster
    // than it travels, so it never ghosts over the card beneath. The card you are
    // moving to lies underneath and comes into focus (blur, opacity, scale) as it
    // clears. Both start in the release frame: the throw travels on a spring
    // carrying the finger's speed; its fade and the rise run on short curves.

    struct FlyingCard: Identifiable {
        let id = UUID()
        let word: Word
        /// Where the finger let go of it, and where it lands just off screen.
        let from: CGFloat
        let to: CGFloat
        /// Thrown while swiping fast: flies off without fading.
        var simple = false
    }

    /// A drag starting this soon after a throw counts as fast swiping.
    private let quickWindow: CFTimeInterval = 0.4

    /// How far a thrown card travels to sit just off the edge of the screen.
    private func travel(_ width: CGFloat) -> CGFloat { width + 32 }

    /// The card you are swiping toward, under the top one. After a cancelled swipe
    /// it fades out as the top card covers it (`underCard` is invisible at rest, so
    /// it costs nothing there); while a thrown card is still leaving, only a live
    /// drag shows it.
    @ViewBuilder
    private func behindCard(words: [Word], i: Int, width: CGFloat) -> some View {
        let dx = offset.width
        if let side = underSide, dx != 0 || flying.isEmpty {
            let neighbor = side == .left ? i + 1 : i - 1
            if words.indices.contains(neighbor) {
                CardFace(word: words[neighbor])
                    .underCard(abs(dx) / width, simple: quick)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    // At release the new top card takes its place in the same frame.
                    .transition(.identity)
            }
        }
    }

    /// The word the Ask panel shows. Rebuilding it is the heaviest thing on this
    /// screen (36–79 ms on an iPhone 11 Pro), so while it is hidden it keeps the
    /// word it was built for and catches up once the deck has been still for a
    /// moment (`syncPanelWhenIdle`). Opening Ask always shows the current word.
    private func panelWord(words: [Word], i: Int) -> Word {
        if askOpen || (offset.height != 0 && !deleteShown) { return words[i] }
        return panelHold.flatMap { held in words.first { $0 == held } } ?? words[i]
    }

    /// Rebuilds the hidden Ask panel for the current card after 0.6 s without a
    /// drag or a card in flight, so the cost never lands while you are swiping.
    private func syncPanelWhenIdle(_ word: Word) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            if offset == .zero && flying.isEmpty {
                panelHold = word
                return
            }
        }
    }

    /// Remembers which neighbour lies under the top card: the side of the last
    /// horizontal drag. A vertical move clears it, so nothing shows under the card
    /// while it slides up for Ask or down for collections.
    private func trackUnderSide(_ offset: CGSize) {
        if offset.width != 0 {
            underSide = offset.width < 0 ? .left : .right
        } else if offset.height != 0 {
            underSide = nil
        }
    }

    /// Takes over a committed horizontal swipe at the finger's position and speed.
    /// The thrown card becomes an overlay that ignores touches, and the card under
    /// it is the deck at once, so you can keep flicking without waiting.
    private func flip(_ dir: SwipeDirection, velocity: CGFloat, words: [Word], i: Int, width: CGFloat) {
        #if DEBUG
        HitchMonitor.shared.mark()
        #endif
        let next = dir == .left ? i + 1 : i - 1
        let card = FlyingCard(word: words[i], from: offset.width,
                              to: dir == .left ? -travel(width) : travel(width), simple: quick)
        quickUntil = CACurrentMediaTime() + quickWindow
        // The throw's travel; its fade and the rise carry their own short curves.
        let spring = Animation.interpolatingSpring(duration: 0.3, bounce: 0,
                                                   initialVelocity: relative(velocity, from: card.from, to: card.to))
        // Not animated: nothing on screen should travel back toward rest.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            offset = .zero
            riseFrom = abs(card.from) / width
            riseSimple = card.simple
        }
        withAnimation(spring, completionCriteria: .logicallyComplete) {
            if panelHold == nil { panelHold = words[i] }
            index = next
            // Flicking straight back: drop the copy of this word still on its way out.
            flying.removeAll { $0.word == words[next] }
            flying.append(card)
        } completion: {
            flying.removeAll { $0.id == card.id }
        }
    }

    /// SwiftUI spring velocity is relative to the distance still to travel.
    private func relative(_ velocity: CGFloat, from current: CGFloat, to target: CGFloat) -> Double {
        let remaining = target - current
        guard abs(remaining) > 1 else { return 0 }
        return Double(velocity / remaining)
    }

    private var emptyCard: some View {
        SwipeCard(offset: $offset, allowed: [], flyOff: []) { _ in
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text("No words yet").font(.system(size: 40, weight: .bold))
                Text("Tap search to find a word worth keeping.")
                    .font(.title3).foregroundStyle(.ink3)
                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: Theme.cardShape)
        }
    }

    private var bottomBar: some View {
        HStack {
            // Unframed, but it keeps the circle's 64 pt touch target.
            Button { showCollections = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Collections")
            Spacer()
            // Adding a word starts in Search.
            CircleButton(systemImage: "plus", label: "Add word") { openSearch() }
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
        case .left, .right: break // handed off to flip(_:velocity:words:i:width:)
        case .up: askOpen = true
        case .down:
            collectWord = words[i]
        }
    }

    private func debugHooks() async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-hitchLog") { HitchMonitor.shared.start() }
        if args.contains("-layerDump") { LayerCensus.start() }
        if args.contains("-seedDemo"), allWords.isEmpty { await DemoSeed.run(context) }
        if let i = args.firstIndex(of: "-demo"), let screen = args[safe: i + 1] {
            try? await Task.sleep(for: .milliseconds(600))
            switch screen {
            case "search": openSearch()
            case "ask":
                askOpen = true
                withAnimation(.spring(duration: 0.45, bounce: 0)) { offset = CGSize(width: 0, height: -askParkDistance) }
            case "study":
                studyCollection = try? context.fetch(FetchDescriptor<WordCollection>()).first
            case "collections": showCollections = true
            case "collect": collectWord = words.first
            case "detail": detailWord = words.first
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

/// Comes into focus as the lifting card uncovers it: soft, faint and slightly small to sharp.
private struct RowReveal: ViewModifier {
    let p: CGFloat
    func body(content: Content) -> some View {
        content
            .opacity(p)
            .blur(radius: 4 * (1 - p))
            .scaleEffect(0.96 + 0.04 * p)
    }
}

/// The like burst: a soft heart blooms out of the Favorite row's icon, then floats up
/// past the descending card and off the top of the screen, fading and softening as it
/// goes. Keyframes, because the bloom and the float are different motions. Each favorite
/// gets its own heart (see `bursts`). Reduce Motion keeps the bloom and fade, without the float.
private struct HeartBurst: View {
    /// The row's heart icon, measured from the row's centre (`heartIconX`). Applied
    /// outside the keyframes so the heart stays on the icon if the label reflows.
    let iconX: CGFloat
    /// How far up it travels: enough to clear the top of the screen.
    let travel: CGFloat
    /// When the card starts down; the flight leaves a beat after so the two cross.
    let lead: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Starts at the row icon's size (17 pt body glyph in a 60 pt heart): it grows out
    /// of the icon rather than appearing over it.
    private static let iconScale: CGFloat = 0.3
    private static let flight = 1.15
    static func length(lead: Double) -> Double { lead + 0.05 + flight }

    /// Plays once, as soon as it is on screen.
    @State private var go = false

    struct Values {
        var scale: CGFloat = HeartBurst.iconScale
        var x: CGFloat = 0
        var y: CGFloat = 0
        var opacity: Double = 0
        var blur: CGFloat = 0
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 60, weight: .semibold))
            .foregroundStyle(.ink2)
            .keyframeAnimator(initialValue: Values(), trigger: go) { heart, v in
                heart
                    .scaleEffect(v.scale)
                    .blur(radius: v.blur)
                    .opacity(v.opacity)
                    .offset(x: v.x, y: v.y)
            } keyframes: { _ in
                // Timeline (s): 0 the heart blooms out of the icon (fades and sharpens in,
                // no flash) · `lead` card starts down · lead+0.05 the heart floats up past it,
                // easing in and out, fading over the last half · ~1.5 gone.
                let fly = !reduceMotion
                let liftOff = lead + 0.05
                let flight = Self.flight
                // Ease-out entrances: a critically damped spring starts fast, where a
                // cubic keyframe from rest would start slow and hide the first frames.
                let appear = Spring(duration: 0.22, bounce: 0)
                KeyframeTrack(\.scale) {
                    LinearKeyframe(Self.iconScale, duration: 0.001)
                    // Sized to the step, so the bloom settles exactly at lift-off.
                    SpringKeyframe(1.0, duration: liftOff, spring: .init(duration: liftOff, bounce: 0.15))
                    CubicKeyframe(fly ? 0.85 : 1.0, duration: flight)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.001)
                    SpringKeyframe(1, duration: 0.22, spring: appear)
                    LinearKeyframe(1, duration: liftOff + flight * 0.45 - 0.22)
                    CubicKeyframe(0, duration: flight * 0.55)
                }
                KeyframeTrack(\.blur) {
                    LinearKeyframe(4, duration: 0.001)
                    SpringKeyframe(0, duration: 0.22, spring: appear)
                    LinearKeyframe(0, duration: liftOff + flight * 0.45 - 0.22)
                    CubicKeyframe(3, duration: flight * 0.55)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: liftOff)
                    // A slight drift toward centre as it rises: an arc, not a lift on rails.
                    CubicKeyframe(fly ? -iconX * 0.6 : 0, duration: flight)
                }
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: liftOff)
                    // Floats: eases off the mark and keeps a steady, moderate speed out.
                    CubicKeyframe(fly ? -travel : 0, duration: flight,
                                  startVelocity: 0, endVelocity: fly ? -travel * 1.1 : 0)
                }
            }
            .offset(x: iconX)
            .onAppear { go = true }
    }
}

/// Delete needs a hold: a solid red fills in from the left, linearly over the hold,
/// with the rumble and ticks of `FillHaptics` building under it, and a firm thud when
/// it completes. Letting go early drains it quickly (slow where you are deciding, fast
/// where the app answers). A tap just flickers the fill, which hints at the hold.
private struct HoldToDelete: View {
    let height: CGFloat
    let onDelete: () -> Void

    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var done = 0
    private static let hold = 1.0

    var body: some View {
        label(ink: .red)
            .background(Color.red.opacity(0.14), in: Theme.actionShape)
            .overlay {
                label(ink: .white)
                    .background(Color.red, in: Theme.actionShape)
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: progress, anchor: .leading)
                    }
            }
            .contentShape(Theme.actionShape)
            .scaleEffect(pressing ? 0.97 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: pressing)
            .sensoryFeedback(.impact(weight: .heavy), trigger: done)
            .onLongPressGesture(minimumDuration: Self.hold, maximumDistance: 12) {
                FillHaptics.shared.stop()
                done += 1
                onDelete()
            } onPressingChanged: { isDown in
                pressing = isDown
                if isDown {
                    withAnimation(.linear(duration: Self.hold)) { progress = 1 }
                    FillHaptics.shared.start(duration: Self.hold)
                } else {
                    withAnimation(.strongEaseOut(0.2)) { progress = 0 }
                    FillHaptics.shared.stop()
                }
            }
            .onDisappear { FillHaptics.shared.stop() }
            .accessibilityElement(children: .ignore)
            .accessibilityHint("Hold to delete")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Delete") { onDelete() }
    }

    private func label(ink: Color) -> some View {
        Label("Hold to delete", systemImage: "trash")
            .font(.body.weight(.semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

/// Hosts AskView so it re-renders only when its word or open state changes. Its
/// callbacks are fresh closures on every deck render, which SwiftUI cannot compare,
/// so without this every frame of a card drag rebuilt the whole Ask panel.
private struct AskPanel: View, Equatable {
    let word: Word
    let revealed: Bool
    let onPull: (CGFloat) -> Void
    let onPullEnd: (CGFloat, CGFloat) -> Void
    let onClose: () -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.word == b.word && a.revealed == b.revealed
    }

    var body: some View {
        AskView(word: word, onPull: onPull, onPullEnd: onPullEnd, onClose: onClose, revealed: revealed)
            .id(word.text)
    }
}

// Built from SwiftUI's own effects so SwiftUI interpolates them itself: a custom
// Animatable modifier would run our code on the main thread every frame.
private extension AnyTransition {
    /// A card thrown off the deck, placed at its landing spot just off screen.
    /// It starts at the release point (`from`, relative to that spot) and travels
    /// on the throw's spring, but fades out on its own short curve so it never
    /// lies half-transparent over the card coming up.
    /// When swiping fast (`fades: false`) it only travels, the cheapest motion there is.
    static func thrown(from offset: CGFloat, fades: Bool = true) -> AnyTransition {
        let travel = AnyTransition.modifier(active: _OffsetEffect(offset: CGSize(width: offset, height: 0)),
                                            identity: _OffsetEffect(offset: .zero))
        guard fades else { return travel }
        return travel
            .combined(with: AnyTransition.modifier(active: _OpacityEffect(opacity: 1),
                                                   identity: _OpacityEffect(opacity: 0))
                .animation(.strongEaseOut(0.15)))
    }

    /// A deleted card going: it softens, fades and sinks slightly into the deck.
    /// Inserted already visible; its identity is the gone state, so inserting it
    /// with an animation plays the exit.
    static var vanish: AnyTransition {
        let s = CGSize(width: 0.94, height: 0.94)
        return AnyTransition.modifier(active: _ScaleEffect(scale: CGSize(width: 1, height: 1)),
                                      identity: _ScaleEffect(scale: s))
            .combined(with: .modifier(active: _OpacityEffect(opacity: 1), identity: _OpacityEffect(opacity: 0)))
            .combined(with: .modifier(active: _BlurEffect(radius: 0, opaque: false),
                                      identity: _BlurEffect(radius: 8, opaque: false)))
    }

    /// The new top card finishing its rise into focus (see `underCard`), from where
    /// it was under the finger. Quick, so fast swiping never meets a soft card.
    /// When swiping fast (`simple`) there is no blur: only the scale and veil.
    /// `delay` (deletes only) holds the whole rise back, veil included.
    static func rise(from revealed: CGFloat, simple: Bool = false, delay: Double = 0) -> AnyTransition {
        let p = min(1, max(0, revealed))
        let s = 0.94 + 0.06 * p
        let grow = AnyTransition.modifier(active: _ScaleEffect(scale: CGSize(width: s, height: s)),
                                          identity: _ScaleEffect(scale: CGSize(width: 1, height: 1)))
        // The veil lifts across the outgoing card's exit: no curve of its own, so it
        // rides the throw's spring (the transaction's) and reaches zero exactly as
        // that card reaches the screen edge, in both the full and the fast throw.
        var veil = AnyTransition.modifier(active: Veil(amount: Veil.amount(revealed: p)), identity: Veil(amount: 0))
        let rise = Animation.strongEaseOut(0.18).delay(delay)
        // A delete has no throw to ride, so the veil takes the rise's delayed curve.
        if delay > 0 { veil = veil.animation(rise) }
        // Each part carries its own curve; nothing wraps the combination, so none overrides another.
        if simple { return grow.animation(rise).combined(with: veil) }
        let focus = AnyTransition.modifier(active: _BlurEffect(radius: 4 * (1 - p), opaque: false),
                                           identity: _BlurEffect(radius: 0, opaque: false))
        return grow.animation(rise)
            .combined(with: focus.animation(rise))
            .combined(with: veil)
    }
}

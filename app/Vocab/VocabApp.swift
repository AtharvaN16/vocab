import SwiftUI
import SwiftData

@main
struct VocabApp: App {
    var body: some Scene {
        WindowGroup {
            DeckView()
        }
        .modelContainer(for: [Word.self, WordCollection.self])
    }
}

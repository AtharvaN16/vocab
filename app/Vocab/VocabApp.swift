import SwiftUI
import SwiftData

@main
struct VocabApp: App {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            DeckView()
                .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme)
        }
        .modelContainer(for: [Word.self, WordCollection.self])
    }
}

import SwiftUI

struct SettingsView: View {
    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("groqKey") private var groqKey = ""
    @AppStorage("groqModel") private var groqModel = GroqExplainer.defaultModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                Button {} label: {
                    LabeledContent("Download offline dictionary", value: "Not in PoC")
                }
                .disabled(true)
            } header: {
                Text("Dictionary")
            } footer: {
                Text("Until then, search looks words up live on Wiktionary. Saved words always work offline.")
            }

            Section {
                Picker("Engine", selection: $engineRaw) {
                    ForEach(Engine.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("Apple Intelligence", value: AppleExplainer.isAvailable ? "Available" : "Unavailable")
            } header: {
                Text("AI mode")
            } footer: {
                Text("Automatic uses Apple's on-device model when available, then Groq (debug builds with a key), then plain dictionary templates.")
            }

            #if DEBUG
            Section {
                SecureField("Groq API key", text: $groqKey)
                TextField("Model", text: $groqModel)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Testing only")
            } footer: {
                Text(GroqExplainer.bundledKey.isEmpty
                     ? "Debug builds only. Or put GROQ_API_KEY in app/.env. Models: console.groq.com/docs/models."
                     : "Using the key from app/.env. A key typed here overrides it. Models: console.groq.com/docs/models.")
            }
            #endif

            Section("Credits") {
                Text("Definitions from Wiktionary, available under CC BY-SA 4.0.")
                    .font(.footnote).foregroundStyle(.ink3)
            }
        }
        .navigationTitle("Settings")
    }
}

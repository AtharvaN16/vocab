import SwiftUI

struct SettingsView: View {
    @AppStorage("engine") private var engineRaw = Engine.automatic.rawValue
    @AppStorage("openCodeKey") private var openCodeKey = ""
    @AppStorage("openCodeModel") private var openCodeModel = "big-pickle"

    var body: some View {
        Form {
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
                Text("Automatic uses Apple's on-device model when available, then OpenCode (debug builds with a key), then plain dictionary templates.")
            }

            #if DEBUG
            Section {
                SecureField("OpenCode Zen API key", text: $openCodeKey)
                TextField("Model", text: $openCodeModel)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Testing only")
            } footer: {
                Text("Debug builds only. Free models change often: check opencode.ai/zen/v1/models.")
            }
            #endif

            Section("Credits") {
                Text("Definitions from Wiktionary, available under CC BY-SA 4.0.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

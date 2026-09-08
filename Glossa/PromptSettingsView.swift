import SwiftUI

struct PromptSettingsView: View {
    @AppStorage(PromptTemplate.storageKey) private var prompt = PromptTemplate.defaultValue
    @State private var sampleText = "serendipity"

    var body: some View {
        Form {
            Section {
                TextEditor(text: $prompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 150)
                    .accessibilityLabel("Dictionary prompt")
                    .autocorrectionDisabled()

                if !prompt.contains(PromptTemplate.placeholder) {
                    Label("Include {{text}} to insert the selected word or phrase.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Your prompt")
            } footer: {
                Text("Use {{text}} for the selected text. Choose your language, detail, and Markdown layout. Changes are saved on this Mac.")
            }

            Section {
                TextField("Sample text", text: $sampleText)
                ScrollView {
                    Text(verbatim: PromptTemplate.render(prompt, text: sampleText))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
            } header: {
                Text("Prompt preview")
            } footer: {
                Text("This is the assembled prompt. No AI request is sent.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 520)
    }
}

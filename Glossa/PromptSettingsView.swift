import AppKit
import SwiftUI

struct PromptSettingsView: View {
    let model: LookupController
    @AppStorage(PromptTemplate.storageKey) private var prompt = PromptTemplate.defaultValue
    @State private var sampleText = "serendipity"

    var body: some View {
        Form {
            Section("Lookup") {
                ShortcutRecorder(model: model)
            }
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
        .frame(width: 540, height: 680)
    }
}

private struct ShortcutRecorder: View {
    let model: LookupController
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        LabeledContent("Global shortcut", value: model.shortcut.label)
        Button(monitor == nil ? "Change Shortcut…" : "Cancel Recording") {
            if monitor == nil { begin() } else { end() }
        }
        .onDisappear { end() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in end() }
        if monitor != nil {
            Text("Press a key with Option, Control, or Command. Escape cancels.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error = message ?? model.shortcutError {
            Text(verbatim: error).foregroundStyle(.orange)
        }
    }

    private func begin() {
        message = nil
        model.suspendShortcut()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 {
                    end()
                } else if let shortcut = LookupShortcut.from(event) {
                    model.setShortcut(shortcut)
                    end()
                } else {
                    message = "Use a character key with Option, Control, or Command."
                }
            }
            return nil
        }
        if monitor == nil { model.resumeShortcut() }
    }

    private func end() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        model.resumeShortcut()
    }
}

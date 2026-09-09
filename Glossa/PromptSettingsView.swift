import AppKit
import ApplicationServices
import SwiftUI

struct PromptSettingsView: View {
    let model: LookupController

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.settings.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).padding()
            }
            TabView {
                LookupSettingsView(model: model)
                    .tabItem { Label("Lookup", systemImage: "keyboard") }
                APISettingsView(settings: model.settings)
                    .tabItem { Label("AI Providers", systemImage: "sparkles") }
                TranslationFlowsView(settings: model.settings)
                    .tabItem { Label("Translation Flows", systemImage: "character.bubble") }
            }
        }
        .frame(width: 620, height: 620)
    }
}

private struct LookupSettingsView: View {
    let model: LookupController
    @State private var hasAccess = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                ShortcutRecorder(model: model)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Select text in your reading app, then press this shortcut. Click the shortcut to change it.")
            }
            Section {
                LabeledContent("Selected-text access") {
                    Label(hasAccess ? "Allowed" : "Not allowed",
                          systemImage: hasAccess ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(hasAccess ? .secondary : Color.orange)
                }
                LabeledContent("Accessibility") {
                    Button(hasAccess ? "Open System Settings…" : "Allow Access…") {
                        if hasAccess {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        } else { model.requestAccessibility() }
                        hasAccess = AXIsProcessTrusted()
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Allow Glossa in System Settings → Privacy & Security → Accessibility. If direct selection access is unavailable, Glossa copies the selection and attempts to restore your clipboard. Access is only used when you look up text.")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccess = AXIsProcessTrusted()
        }
    }
}

private struct TranslationFlowsView: View {
    @Bindable var settings: LookupSettings
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Form {
            Section {
                if settings.flows.isEmpty {
                    ContentUnavailableView("No Translation Flows", systemImage: "character.bubble",
                                           description: Text("Add a language pair, then choose its AI and prompt."))
                }
                ForEach($settings.flows) { $flow in
                    let id = flow.id
                    TranslationFlowEditor(flow: $flow, settings: settings,
                        isExpanded: Binding(get: { expanded.contains(id) }, set: { value in
                            if value { expanded.insert(id) } else { expanded.remove(id) }
                        }), remove: {
                            expanded.remove(id)
                            settings.flows.removeAll { $0.id == id }
                        })
                }
                Button("Add Flow", systemImage: "plus") {
                    let flow = TranslationFlow(source: .english)
                    settings.flows.append(flow)
                    expanded.insert(flow.id)
                }
            } header: {
                Text("Translation Flows")
            } footer: {
                Text("Glossa matches the detected source language. Auto-detect flows handle other or uncertain languages. If several flows match, choose one in the result panel. Changes are saved automatically.")
            }
        }
        .formStyle(.grouped)
        .disabled(!settings.canEdit)
    }
}

private struct TranslationFlowEditor: View {
    @Binding var flow: TranslationFlow
    let settings: LookupSettings
    @Binding var isExpanded: Bool
    let remove: () -> Void
    @State private var sampleText = "serendipity"
    @State private var confirmsDelete = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Picker("From", selection: $flow.source) {
                ForEach(FlowLanguage.allCases) { Text($0.name).tag($0) }
            }
            Picker("To", selection: $flow.target) {
                ForEach(FlowLanguage.allCases.filter { $0 != .automatic }) { Text($0.name).tag($0) }
            }
            Picker("AI provider", selection: $flow.provider) {
                ForEach(AIProvider.allCases) { Text(settings.providerName($0)).tag($0) }
            }
            .onChange(of: flow.provider) { _, _ in flow.model = "" }
            TextField("Model override", text: $flow.model,
                      prompt: Text("Default: \(settings.configuration(for: flow.provider).model)"))
                .autocorrectionDisabled()
            Text("Leave the model blank to use the provider’s default.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt").font(.headline)
                TextEditor(text: $flow.prompt)
                    .font(.body.monospaced())
                    .frame(height: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                    .accessibilityLabel("Prompt for \(flow.title)")
                    .autocorrectionDisabled()
                Text("Use {{text}}, {{sourceLanguage}}, and {{targetLanguage}}. The target language controls the response language; your prompt controls the content and Markdown layout.")
                    .font(.caption).foregroundStyle(.secondary)
                if !flow.prompt.contains(PromptTemplate.placeholder) {
                    Label("Include {{text}} before using this flow.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 8)
            DisclosureGroup("Prompt Preview") {
                TextField("Sample text", text: $sampleText)
                Text(verbatim: flow.render(text: sampleText))
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Preview only. No AI request is sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Delete Flow…", role: .destructive) { confirmsDelete = true }
                .padding(.top, 8)
                .alert("Delete this flow?", isPresented: $confirmsDelete) {
                    Button("Delete", role: .destructive, action: remove)
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("\(flow.title) and its prompt will be removed. Your AI provider settings will be kept.")
                }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(flow.title)
                Text(settings.providerName(flow.provider))
                    .font(.caption).foregroundStyle(.secondary)
                if !flow.prompt.contains(PromptTemplate.placeholder) {
                    Label("Prompt needs {{text}}", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ShortcutRecorder: View {
    let model: LookupController
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        LabeledContent("Global shortcut") {
            Button(monitor == nil ? model.shortcut.label : "Cancel Recording") {
                if monitor == nil { begin() } else { end() }
            }
            .monospaced()
            .help("Click to record a shortcut. Escape cancels recording.")
            .accessibilityLabel(monitor == nil ? "Record global shortcut" : "Cancel shortcut recording")
            .accessibilityValue(model.shortcut.label)
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

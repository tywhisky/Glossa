import AppKit
import ApplicationServices
import SwiftUI

struct PromptSettingsView: View {
    let model: LookupController
    @State private var pane = SettingsPane.lookup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.settings.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).padding()
            }
            HStack(spacing: 8) {
                ForEach(SettingsPane.allCases) { item in
                    Button {
                        pane = item
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(pane == item ? Color.accentColor : .secondary)
                    .background(pane == item ? Color.accentColor.opacity(0.12) : .clear,
                                in: .rect(cornerRadius: 8))
                    .accessibilityAddTraits(pane == item ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")
            .padding(12)

            Divider()

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(SettingsPane.allCases) { item in
                        Group {
                            switch item {
                            case .lookup: LookupSettingsView(model: model)
                            case .providers: APISettingsView(settings: model.settings)
                            case .flows: TranslationFlowsView(settings: model.settings)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: CGFloat(item.rawValue - pane.rawValue) * geometry.size.width
                                * (layoutDirection == .rightToLeft ? -1 : 1))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: pane)
                        .disabled(pane != item)
                        .allowsHitTesting(pane == item)
                        .accessibilityHidden(pane != item)
                    }
                }
            }
            .clipped()
        }
        .frame(minWidth: 620, idealWidth: 620, minHeight: 520, idealHeight: 560)
        .disclosureGroupStyle(SettingsDisclosureGroupStyle())
    }
}

private enum SettingsPane: Int, CaseIterable, Identifiable {
    case lookup, providers, flows

    var id: Self { self }

    var title: String {
        switch self {
        case .lookup: "Lookup"
        case .providers: "AI Providers"
        case .flows: "Translation Flows"
        }
    }

    var systemImage: String {
        switch self {
        case .lookup: "keyboard"
        case .providers: "sparkles"
        case .flows: "character.bubble"
        }
    }
}

private struct SettingsDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsDisclosureGroup(configuration: configuration)
    }
}

private struct SettingsDisclosureGroup: View {
    let configuration: DisclosureGroupStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Toggles this settings section")

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 18)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }
}

private struct LookupSettingsView: View {
    let model: LookupController
    @State private var hasAccess = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                ShortcutRecorder(model: model, purpose: .selection)
                ShortcutRecorder(model: model, purpose: .manual)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Selected Text looks up the current selection. Type or Paste opens the manual input panel. Click a shortcut to change it.")
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
    @State private var editingMode: LookupMode = .dictionary
    @State private var previewMode: LookupMode?
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
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt").font(.headline)
                Picker("Prompt type", selection: $editingMode) {
                    ForEach(LookupMode.allCases) { mode in
                        Text(mode.name).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Prompt type")
                TextEditor(text: $flow[editingMode])
                    .font(.body.monospaced())
                    .frame(height: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                    .accessibilityLabel("\(editingMode.name) prompt for \(flow.title)")
                    .autocorrectionDisabled()
                Text("Use {{text}}, {{sourceLanguage}}, and {{targetLanguage}}. The target language controls the response language; your prompt controls the content and Markdown layout.")
                    .font(.caption).foregroundStyle(.secondary)
                if !flow[editingMode].contains(PromptTemplate.placeholder) {
                    Label("Include {{text}} before using this mode.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 8)
            DisclosureGroup("Prompt Preview") {
                TextField("Sample text", text: $sampleText)
                Picker("Mode", selection: $previewMode) {
                    Text("Automatic · \(flow.resolvedMode(text: sampleText).name)").tag(nil as LookupMode?)
                    ForEach(LookupMode.allCases) { mode in
                        Text(mode.name).tag(Optional(mode))
                    }
                }
                Text(verbatim: flow.render(text: sampleText, mode: previewMode))
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Preview only. No AI request is sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disclosureGroupStyle(SettingsDisclosureGroupStyle())
            Button("Delete Flow", role: .destructive) { confirmsDelete = true }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                if LookupMode.allCases.contains(where: { !flow[$0].contains(PromptTemplate.placeholder) }) {
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
    let purpose: ShortcutPurpose
    @State private var monitor: Any?
    @State private var message: String?

    private var shortcut: LookupShortcut {
        purpose == .selection ? model.shortcut : model.manualShortcut
    }

    private var error: String? {
        purpose == .selection ? model.shortcutError : model.manualShortcutError
    }

    var body: some View {
        LabeledContent(purpose.title) {
            Button(monitor == nil ? shortcut.label : "Cancel Recording") {
                if monitor == nil { begin() } else { end() }
            }
            .monospaced()
            .help("Click to record a shortcut. Escape cancels recording.")
            .accessibilityLabel(monitor == nil ? "Record \(purpose.title) shortcut" : "Cancel shortcut recording")
            .accessibilityValue(shortcut.label)
        }
        .onDisappear { end() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in end() }
        if monitor != nil {
            Text("Press a key with Option, Control, or Command. Escape cancels.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error = message ?? self.error {
            Text(verbatim: error).foregroundStyle(.orange)
        }
    }

    private func begin() {
        message = nil
        model.suspendShortcuts()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 {
                    end()
                } else if let shortcut = LookupShortcut.from(event) {
                    if purpose == .selection { model.setShortcut(shortcut) }
                    else { model.setManualShortcut(shortcut) }
                    end()
                } else {
                    message = "Use a character key with Option, Control, or Command."
                }
            }
            return nil
        }
        if monitor == nil { model.resumeShortcuts() }
    }

    private func end() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        model.resumeShortcuts()
    }
}

private enum ShortcutPurpose {
    case selection, manual

    var title: String { self == .selection ? "Selected Text" : "Type or Paste" }
}

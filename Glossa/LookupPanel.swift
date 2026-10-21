import AppKit
import SwiftUI

enum PanelPlacement {
    static func appKitFrame(from accessibilityFrame: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: accessibilityFrame.minX, y: primaryScreenTop - accessibilityFrame.maxY,
               width: accessibilityFrame.width, height: accessibilityFrame.height)
    }

    static func frame(in visibleFrame: CGRect, preferredHeight: CGFloat = 420) -> CGRect {
        let width = min(400, max(1, visibleFrame.width - 32))
        let availableHeight = max(1, visibleFrame.height - 32)
        let height = min(max(1, preferredHeight), availableHeight)
        return CGRect(x: visibleFrame.maxX - width - 16, y: visibleFrame.maxY - height - 16, width: width, height: height)
    }

    static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        screens.indices.filter { screens[$0].intersects(window) }.max { left, right in
            let a = screens[left].intersection(window)
            let b = screens[right].intersection(window)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
    }
}

@MainActor
final class LookupPanelController: NSObject, NSWindowDelegate {
    private var panel: ResultPanel?
    private var globalMouseMonitor: Any?
    private var localMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var isTrackingMenu = false
    private var visibleFrame: CGRect?
    private let escape = GlobalHotKey(id: 2)
    private weak var model: LookupController?

    func show(model: LookupController, windowFrame: CGRect?, focusesInput: Bool) -> String? {
        self.model = model
        let screens = NSScreen.screens
        guard let primary = screens.first else { return "No screen is available." }
        var screen = screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? primary
        if let windowFrame {
            let window = PanelPlacement.appKitFrame(from: windowFrame, primaryScreenTop: primary.frame.maxY)
            if let index = PanelPlacement.screenIndex(for: window, screens: screens.map(\.frame)) { screen = screens[index] }
        }

        if panel == nil {
            let window = ResultPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            window.level = .floating
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovable = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: LookupPanelView(model: model) { [weak self] height in
                self?.resize(to: height)
            })
            panel = window
            installDismissal()
        }
        visibleFrame = screen.visibleFrame
        if let panel {
            let frame = PanelPlacement.frame(in: screen.visibleFrame)
            let start = frame.offsetBy(dx: 0, dy: 8)
            panel.setFrame(start, display: true)
            panel.alphaValue = 0
            if focusesInput {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        }
        escape.onPress = { [weak model] in model?.dismiss() }
        let status = escape.register(.escape)
        return status == noErr ? nil : "Escape is unavailable (error \(status)). Click outside to close."
    }

    func dismiss() {
        escape.stop()
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers.removeAll()
        isTrackingMenu = false
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMouseMonitor = nil
        localMonitor = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.delegate = nil
        panel = nil
        visibleFrame = nil
    }

    private func resize(to preferredHeight: CGFloat) {
        guard let panel, let visibleFrame else { return }
        let frame = PanelPlacement.frame(in: visibleFrame, preferredHeight: preferredHeight)
        guard abs(frame.height - panel.frame.height) > 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) { model?.dismiss() }

    private func installDismissal() {
        // Native menus have their own windows and must receive Escape themselves.
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isTrackingMenu = true
                    self?.escape.stop()
                }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isTrackingMenu = false
                    let status = self.escape.register(.escape)
                    self.model?.dismissalError = status == noErr ? nil : "Escape is unavailable (error \(status)). Click outside to close."
                }
            }
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isTrackingMenu else { return }
                self.model?.dismiss()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, !self.isTrackingMenu else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.model?.dismiss(); return true }
                } else if event.window !== self.panel {
                    self.model?.dismiss()
                }
                return false
            }
            return consumed ? nil : event
        }
    }
}

final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LookupPanelView: View {
    let model: LookupController
    let preferredHeightChanged: (CGFloat) -> Void
    @State private var input = ""
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                panelContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            if !model.text.isEmpty {
                queryOptions
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                    .onDisappear { footerHeight = 0 }
            }
        }
        .onChange(of: contentHeight + footerHeight) { _, height in
            preferredHeightChanged(height)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45))
        }
        .clipShape(.rect(cornerRadius: 16))
        .defaultFocus($isInputFocused, true)
        .onChange(of: model.manualFocusRequest) { _, _ in
            if !isInputFocused { isInputFocused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Glossa lookup")
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader
            if !model.text.isEmpty {
                Text(verbatim: model.text)
                    .font(model.activeMode == .dictionary ? .system(.title2, design: .serif) : .body)
                    .textSelection(.enabled)
                if model.speech.owner == .lookup, let error = model.speech.error {
                    Text(verbatim: error).font(.caption).foregroundStyle(.orange)
                }
            }
            if let failure = model.failure {
                Label(failure.localizedDescription, systemImage: "exclamationmark.circle")
                if failure == .permission {
                    Button("Allow Accessibility Access…") { model.requestAccessibility() }
                    Text("After allowing access in System Settings, return to your reading app and press the shortcut again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.isReadingSelection {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading selection…")
                    Spacer()
                    Button("Stop") { model.cancelLookup() }
                }
            } else if !model.text.isEmpty {
                Divider()
                if let previous = model.wordbook.previous(term: model.text, sourceLanguage: model.lookupSourceLanguage),
                   previous.id != model.savedEntryID {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("You saved this on \(previous.createdAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "bookmark.fill")
                            .font(.caption).foregroundStyle(.secondary)
                        if !previous.meaningMarkdown.isEmpty {
                            Text(verbatim: previous.meaningMarkdown).font(.callout)
                        } else if !previous.context.isEmpty {
                            Text(verbatim: previous.context).font(.callout).lineLimit(3)
                        }
                    }
                }
                if !model.answer.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.activeMode == .translation ? "Translation" : "Definition")
                            .font(.caption).foregroundStyle(.secondary)
                        // ponytail: inline Markdown plus line breaks; add block layout when needed.
                        Text((try? AttributedString(markdown: model.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                             ?? AttributedString(model.answer))
                            .textSelection(.enabled)
                    }
                }
                if model.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Looking up…").foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { model.cancelLookup() }
                    }
                }
                if let error = model.lookupError {
                    Text(verbatim: error).foregroundStyle(.secondary)
                }
                if let error = model.wordbookError {
                    Text(verbatim: error).font(.caption).foregroundStyle(.orange)
                }
                if model.savedEntryID != nil {
                    HStack {
                        Label("Saved to Wordbook", systemImage: "checkmark")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Wordbook") { model.showWordbook() }.controlSize(.small)
                    }
                }
            } else {
                TextField("Type or paste a word, phrase, or sentence", text: $input, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit { model.submit(input) }
                HStack {
                    Button("Look Up") { model.submit(input) }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    PasteButton(payloadType: String.self) { values in
                        if let first = values.first { input = first }
                    }
                    .labelStyle(.titleAndIcon)
                }
                Text("Up to 2,000 characters. Looking up sends this text and the matched flow’s prompt to its AI provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.dismissalError {
                Text(verbatim: error).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            if model.text.isEmpty {
                Text("Look up text").font(.headline)
            } else {
                Text("Original").font(.caption).foregroundStyle(.secondary)
                SpeechControls(speech: model.speech, text: model.text,
                               sourceLanguage: model.lookupSourceLanguage, owner: .lookup, compact: true)
            }
            Spacer(minLength: 0)
            panelActions
        }
    }

    private var flowSummary: String {
        guard let flow = model.settings.flows.first(where: { $0.id == model.activeFlowID }) else {
            return "Choose a Translation Flow"
        }
        let source = FlowLanguage(rawValue: model.lookupSourceLanguage)?.name ?? flow.source.name
        return "\(source) → \(flow.target.name) · \(model.settings.providerName(flow.provider))"
    }

    private var modeSummary: String {
        let mode = model.activeMode ?? model.selectedMode
        let selection = model.selectedMode == nil ? "Auto" : "Manual"
        return mode.map { "\($0.name) · \(selection)" } ?? "Automatic"
    }

    private var queryOptions: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Menu {
                    Picker("Flow", selection: Binding(get: { model.selectedFlowID }, set: { model.selectFlow($0) })) {
                        Text("Automatic").tag(nil as UUID?)
                        ForEach(model.settings.flows) { flow in
                            Text("\(flow.title) · \(model.settings.providerName(flow.provider))").tag(Optional(flow.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if model.settings.flows.isEmpty {
                        Button("Add a Translation Flow…", action: showSettings)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: flowSummary)
                            .lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .help("\(flowSummary)\nChange translation flow")
                .accessibilityLabel("Translation flow")
                .accessibilityValue("\(flowSummary), \(model.selectedFlowID == nil ? "Automatic flow" : "Manual flow")")

                Menu {
                    Picker("Mode", selection: Binding(get: { model.selectedMode }, set: { model.selectMode($0) })) {
                        Text("Automatic").tag(nil as LookupMode?)
                        ForEach(LookupMode.allCases) { mode in
                            Text(mode.name).tag(Optional(mode))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: modeSummary)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .fixedSize()
                .help("\(modeSummary)\nChange query mode")
                .accessibilityLabel("Query mode")
                .accessibilityValue(modeSummary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Preserve the full SwiftUI labels instead of native menu button titles.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var panelActions: some View {
        HStack(spacing: 6) {
            if !model.text.isEmpty {
                Button(model.savedEntryID == nil ? "Save to Wordbook" : "Saved to Wordbook",
                       systemImage: model.savedEntryID == nil ? "bookmark" : "bookmark.fill") { model.saveToWordbook() }
                    .disabled(model.isLoading || model.isSavingEntry || model.answer.isEmpty || model.lookupError != nil || model.savedEntryID != nil)
                    .help("Save this AI lookup to your wordbook")
            }
            Menu {
                if !model.text.isEmpty {
                    Button("Retry", systemImage: "arrow.clockwise") { model.retry() }
                        .disabled(model.isLoading)
                    Button("New Lookup", systemImage: "square.and.pencil") {
                        input = ""
                        model.showManualEntry()
                    }
                    Divider()
                }
                Button("Settings…", systemImage: "gearshape", action: showSettings)
            } label: {
                Label("More Actions", systemImage: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }

    private func showSettings() {
        model.dismiss()
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}

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
        // The flow picker's menu has its own window and must receive Escape itself.
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
    @FocusState private var isInputFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    if !model.text.isEmpty {
                        Text(verbatim: model.text)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    panelActions
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
                    HStack(spacing: 12) {
                        Picker("Mode", selection: Binding(get: { model.selectedMode }, set: { model.selectMode($0) })) {
                            Text(model.selectedMode == nil ? (model.activeMode.map { "Auto · \($0.name)" } ?? "Auto") : "Auto")
                                .tag(nil as LookupMode?)
                            ForEach(LookupMode.allCases) { mode in
                                Text(mode.name).tag(Optional(mode))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("Mode")
                        .fixedSize()
                        Menu {
                            Picker("Flow", selection: Binding(get: { model.selectedFlowID }, set: { model.selectFlow($0) })) {
                                Text("Automatic").tag(nil as UUID?)
                                ForEach(model.settings.flows) { flow in
                                    Text("\(flow.title) · \(flow.provider.name)").tag(Optional(flow.id))
                                }
                            }
                            .labelsHidden()
                        } label: {
                            Text(model.selectedFlowID == nil ? "Flow: Auto" : "Flow: Manual")
                        }
                        .fixedSize()
                        .accessibilityLabel("Flow")
                        .accessibilityValue(model.selectedFlowID == nil ? "Automatic" : "Manual")
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)
                    if let flow = model.settings.flows.first(where: { $0.id == model.activeFlowID }) {
                        Text("\(flow.title) · \(model.settings.providerName(flow.provider))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
                        // ponytail: inline Markdown plus line breaks; add block layout when needed.
                        Text((try? AttributedString(markdown: model.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                             ?? AttributedString(model.answer))
                            .textSelection(.enabled)
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
                    Text("Look up text").font(.headline)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { preferredHeightChanged($0) }
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

    private var panelActions: some View {
        HStack(spacing: 6) {
            if !model.text.isEmpty {
                Button(model.savedEntryID == nil ? "Save to Wordbook" : "Saved to Wordbook",
                       systemImage: model.savedEntryID == nil ? "bookmark" : "bookmark.fill") { model.saveToWordbook() }
                    .disabled(model.isLoading || model.isSavingEntry || model.answer.isEmpty || model.lookupError != nil || model.savedEntryID != nil)
                    .help("Save this AI lookup to your wordbook")
                Button("Retry", systemImage: "arrow.clockwise") { model.retry() }
                    .disabled(model.isLoading)
                    .help("Retry")
                Button("New Lookup", systemImage: "square.and.pencil") {
                    input = ""
                    model.showManualEntry()
                }
                .help("New Lookup")
            }
            Button("Settings", systemImage: "gearshape", action: showSettings)
                .help("Settings")
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

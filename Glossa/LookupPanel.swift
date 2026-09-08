import AppKit
import SwiftUI

enum PanelPlacement {
    static func appKitFrame(from accessibilityFrame: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: accessibilityFrame.minX, y: primaryScreenTop - accessibilityFrame.maxY,
               width: accessibilityFrame.width, height: accessibilityFrame.height)
    }

    static func frame(in visibleFrame: CGRect) -> CGRect {
        let width = min(400, max(1, visibleFrame.width - 32))
        let height = min(420, max(1, visibleFrame.height - 32))
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
    private let escape = GlobalHotKey(id: 2)
    private weak var model: LookupController?

    func show(model: LookupController, windowFrame: CGRect?) -> String? {
        self.model = model
        let screens = NSScreen.screens
        guard let primary = screens.first else { return "No screen is available." }
        var screen = screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? primary
        if let windowFrame {
            let window = PanelPlacement.appKitFrame(from: windowFrame, primaryScreenTop: primary.frame.maxY)
            if let index = PanelPlacement.screenIndex(for: window, screens: screens.map(\.frame)) { screen = screens[index] }
        }

        if panel == nil {
            let window = ResultPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: true)
            window.title = "Glossa"
            window.level = .floating
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: LookupPanelView(model: model))
            panel = window
            installDismissal()
        }
        panel?.setFrame(PanelPlacement.frame(in: screen.visibleFrame), display: true)
        panel?.orderFrontRegardless()
        escape.onPress = { [weak model] in model?.dismiss() }
        let status = escape.register(.escape)
        return status == noErr ? nil : "Escape is unavailable (error \(status)). Click outside or use the close button."
    }

    func dismiss() {
        escape.stop()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMouseMonitor = nil
        localMonitor = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.delegate = nil
        panel = nil
    }

    func windowWillClose(_ notification: Notification) { model?.dismiss() }

    private func installDismissal() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.dismiss() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
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

private final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LookupPanelView: View {
    let model: LookupController
    @State private var input = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let failure = model.failure {
                    Label(failure.localizedDescription, systemImage: "exclamationmark.circle")
                    if failure == .permission {
                        Button("Allow Accessibility Access…") { model.requestAccessibility() }
                        Text("After allowing access in System Settings, return to your reading app and press the shortcut again.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.text.isEmpty {
                    Text(verbatim: model.text)
                        .font(.title2)
                        .textSelection(.enabled)
                    Divider()
                    Label("Interaction preview", systemImage: "info.circle")
                        .font(.headline)
                    Text("AI lookup is not connected yet. This panel is a preview, not a translation of your selection.")
                        .foregroundStyle(.secondary)
                    Text("**Example layout**\n\nA concise definition, followed by usage notes and an example sentence.")
                        .textSelection(.enabled)
                } else {
                    Text("Look up text").font(.headline)
                    TextField("Type or paste a word, phrase, or sentence", text: $input, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.submit(input) }
                    HStack {
                        Button("Preview") { model.submit(input) }
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        PasteButton(payloadType: String.self) { values in
                            if let first = values.first { input = first }
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    Text("Up to 2,000 characters. Nothing is sent to an AI provider yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.dismissalError {
                    Text(verbatim: error).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

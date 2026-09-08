import AppKit
@preconcurrency import ApplicationServices
import Observation

@MainActor @Observable
final class LookupController {
    private(set) var shortcut = LookupShortcut.load()
    private(set) var shortcutError: String?
    private(set) var text = ""
    private(set) var failure: SelectionFailure?
    private(set) var dismissalError: String?

    @ObservationIgnored private let hotKey = GlobalHotKey(id: 1)
    @ObservationIgnored private let reader = SelectedTextReader()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var panel: LookupPanelController?

    func start() {
        hotKey.onPress = { [weak self] in self?.lookUpSelection() }
        setShortcut(shortcut)
    }

    func stop() {
        dismiss()
        hotKey.stop()
    }

    func suspendShortcut() { hotKey.stop() }

    func resumeShortcut() {
        let status = hotKey.register(shortcut)
        if status != noErr {
            shortcutError = "Could not register \(shortcut.label) (error \(status)). Choose another shortcut."
        }
    }

    func setShortcut(_ candidate: LookupShortcut) {
        guard candidate.isValid else {
            shortcutError = "Use a key with Option, Control, or Command. Escape is reserved for closing the panel."
            return
        }
        let status = hotKey.register(candidate)
        guard status == noErr else {
            shortcutError = "Could not register \(candidate.label) (error \(status)). Choose another shortcut."
            return
        }
        shortcut = candidate
        shortcutError = nil
        // Encoding this fixed, primitive value cannot fail.
        if let data = try? JSONEncoder().encode(candidate) {
            UserDefaults.standard.set(data, forKey: LookupShortcut.storageKey)
        }
    }

    func lookUpSelection() {
        task?.cancel()
        guard let source = NSWorkspace.shared.frontmostApplication,
              source.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            showManualEntry()
            return
        }
        let processID = source.processIdentifier
        task = Task { [weak self, reader] in
            let selection = await reader.read(from: processID)
            guard !Task.isCancelled, let self,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return }
            self.text = selection.text ?? ""
            self.failure = selection.failure
            self.show(windowFrame: selection.windowFrame)
        }
    }

    func showManualEntry() {
        task?.cancel()
        text = ""
        failure = nil
        show(windowFrame: nil)
    }

    func submit(_ input: String) {
        task?.cancel()
        do {
            text = try LookupInput.validated(input)
            failure = nil
        } catch let error as SelectionFailure {
            text = ""
            failure = error
        } catch {
            text = ""
            failure = .unavailable
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func dismiss() {
        task?.cancel()
        task = nil
        panel?.dismiss()
        panel = nil
        text = ""
        failure = nil
        dismissalError = nil
    }

    private func show(windowFrame: CGRect?) {
        if panel == nil { panel = LookupPanelController() }
        dismissalError = panel?.show(model: self, windowFrame: windowFrame)
    }
}

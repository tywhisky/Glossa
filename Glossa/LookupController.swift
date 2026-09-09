import AppKit
@preconcurrency import ApplicationServices
import Observation

@MainActor @Observable
final class LookupController {
    let settings: LookupSettings
    private(set) var selectedFlowID: UUID?
    private(set) var activeFlowID: UUID?
    private(set) var shortcut = LookupShortcut.load()
    private(set) var shortcutError: String?
    private(set) var text = ""
    private(set) var failure: SelectionFailure?
    var dismissalError: String?
    private(set) var answer = ""
    private(set) var isLoading = false
    private(set) var isReadingSelection = false
    private(set) var lookupError: String?

    typealias Lookup = @Sendable (PreparedLookup, @escaping @Sendable (String) async -> Void) async throws -> Void
    @ObservationIgnored private let lookup: Lookup
    @ObservationIgnored private var generation = UUID()

    @ObservationIgnored private let hotKey = GlobalHotKey(id: 1)
    @ObservationIgnored private let reader = SelectedTextReader()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var panel: LookupPanelController?

    init(settings: LookupSettings = LookupSettings(), lookup: @escaping Lookup = ChatCompletionsClient.lookup) {
        self.settings = settings
        self.lookup = lookup
    }

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
            shortcutError = "Use a key with Option, Control, or Command. Escape and Command+C are reserved."
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
        selectedFlowID = nil
        resetLookup()
        guard let source = NSWorkspace.shared.frontmostApplication,
              source.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            showManualEntry()
            return
        }
        let processID = source.processIdentifier
        text = ""
        failure = nil
        isReadingSelection = true
        show(windowFrame: nil)
        task = Task { [weak self, reader] in
            let selection = await reader.read(from: processID)
            guard !Task.isCancelled, let self,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return }
            self.text = selection.text ?? ""
            self.isReadingSelection = false
            self.failure = selection.failure
            self.show(windowFrame: selection.windowFrame)
            if let text = selection.text { self.submit(text) }
        }
    }

    func showManualEntry() {
        selectedFlowID = nil
        resetLookup()
        text = ""
        failure = nil
        show(windowFrame: nil)
    }

    func submit(_ input: String) {
        resetLookup()
        do {
            text = try LookupInput.validated(input)
            failure = nil
            guard settings.canEdit else { lookupError = settings.error; return }
            let flow: TranslationFlow?
            if let selectedFlowID {
                flow = settings.flows.first { $0.id == selectedFlowID }
            } else {
                flow = TranslationFlow.match(in: settings.flows, language: FlowLanguage.detect(text))
            }
            guard let flow else {
                lookupError = settings.flows.isEmpty
                    ? "Add a translation flow in Settings to start looking up."
                    : "Choose a flow below. No single flow matches this text."
                return
            }
            activeFlowID = flow.id
            let query = try PreparedLookup(text: text, flow: flow, configuration: settings.configuration(for: flow.provider))
            isLoading = true
            let id = generation
            task = Task { [weak self, lookup] in
                do {
                    try await lookup(query) { [weak self] answer in
                        await self?.receive(answer, generation: id)
                    }
                } catch {
                    guard let self, self.generation == id, !Task.isCancelled else { return }
                    // Do not display arbitrary transport errors that may contain URLs or request data.
                    self.lookupError = (error as? APIError)?.localizedDescription
                        ?? "Could not reach the provider. Check your connection or try again."
                }
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.isLoading = false
                self.task = nil
            }
        } catch let error as SelectionFailure {
            text = ""
            failure = error
        } catch let error as APIError {
            lookupError = error.localizedDescription
        } catch {
            text = ""
            failure = .unavailable
        }
    }

    func selectFlow(_ id: UUID?) {
        selectedFlowID = id
        if !text.isEmpty { submit(text) }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), !CGPreflightPostEventAccess() {
            CGRequestPostEventAccess()
        }
    }

    func dismiss() {
        selectedFlowID = nil
        resetLookup()
        panel?.dismiss()
        panel = nil
        text = ""
        failure = nil
        dismissalError = nil
    }

    func cancelLookup() {
        task?.cancel()
        task = nil
        generation = UUID()
        isLoading = false
        isReadingSelection = false
        lookupError = "Stopped."
    }

    private func receive(_ answer: String, generation: UUID) {
        guard self.generation == generation else { return }
        self.answer = answer
    }

    private func resetLookup() {
        cancelLookup()
        activeFlowID = nil
        answer = ""
        lookupError = nil
    }

    private func show(windowFrame: CGRect?) {
        if panel == nil { panel = LookupPanelController() }
        dismissalError = panel?.show(model: self, windowFrame: windowFrame)
    }
}

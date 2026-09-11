import AppKit
@preconcurrency import ApplicationServices
import Observation

@MainActor @Observable
final class LookupController {
    let settings: LookupSettings
    let wordbook = WordbookStore()
    private(set) var savedEntryID: UUID?
    private(set) var isSavingEntry = false
    private(set) var wordbookError: String?
    private(set) var lookupSourceLanguage = "auto"
    private(set) var lookupTargetLanguage = ""
    @ObservationIgnored private var sourceApplication: String?
    @ObservationIgnored private let wordbookWindow = WordbookWindowController()
    private(set) var selectedFlowID: UUID?
    private(set) var activeFlowID: UUID?
    private(set) var selectedMode: LookupMode?
    private(set) var activeMode: LookupMode?
    private(set) var shortcut = LookupShortcut.load()
    private(set) var shortcutError: String?
    private(set) var manualShortcut = LookupShortcut.load(storageKey: LookupShortcut.manualStorageKey,
                                                           fallback: .manualDefault)
    private(set) var manualShortcutError: String?
    private(set) var text = ""
    private(set) var failure: SelectionFailure?
    var dismissalError: String?
    private(set) var answer = ""
    private(set) var isLoading = false
    private(set) var isReadingSelection = false
    private(set) var lookupError: String?
    private(set) var manualFocusRequest = 0

    typealias Lookup = @Sendable (PreparedLookup, @escaping @Sendable (String) async -> Void) async throws -> Void
    @ObservationIgnored private let lookup: Lookup
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cache = LookupResultCache()

    @ObservationIgnored private let hotKey = GlobalHotKey(id: 1)
    @ObservationIgnored private let manualHotKey = GlobalHotKey(id: 3)
    @ObservationIgnored private let reader = SelectedTextReader()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var panel: LookupPanelController?

    init(settings: LookupSettings = LookupSettings(), lookup: @escaping Lookup = ChatCompletionsClient.lookup) {
        self.settings = settings
        self.lookup = lookup
        if manualShortcut == shortcut {
            manualShortcut = shortcut == .manualDefault ? .alternateManualDefault : .manualDefault
        }
    }

    func start() {
        hotKey.onPress = { [weak self] in self?.lookUpSelection() }
        manualHotKey.onPress = { [weak self] in self?.showManualEntry() }
        resumeShortcuts()
    }

    func stop() {
        dismiss()
        hotKey.stop()
        manualHotKey.stop()
    }

    func suspendShortcuts() {
        hotKey.stop()
        manualHotKey.stop()
    }

    func resumeShortcuts() {
        let status = hotKey.register(shortcut)
        if status != noErr {
            shortcutError = "Could not register \(shortcut.label) (error \(status)). Choose another shortcut."
        }
        let manualStatus = manualHotKey.register(manualShortcut)
        if manualStatus != noErr {
            manualShortcutError = "Could not register \(manualShortcut.label) (error \(manualStatus)). Choose another shortcut."
        }
    }

    func setShortcut(_ candidate: LookupShortcut) {
        guard candidate.isValid else {
            shortcutError = "Use a key with Option, Control, or Command. Escape and Command+C are reserved."
            return
        }
        guard candidate != manualShortcut else {
            shortcutError = "Choose a different shortcut from Type or Paste Text."
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

    func setManualShortcut(_ candidate: LookupShortcut) {
        guard candidate.isValid else {
            manualShortcutError = "Use a key with Option, Control, or Command. Escape and Command+C are reserved."
            return
        }
        guard candidate != shortcut else {
            manualShortcutError = "Choose a different shortcut from Selected Text Lookup."
            return
        }
        let status = manualHotKey.register(candidate)
        guard status == noErr else {
            manualShortcutError = "Could not register \(candidate.label) (error \(status)). Choose another shortcut."
            return
        }
        manualShortcut = candidate
        manualShortcutError = nil
        if let data = try? JSONEncoder().encode(candidate) {
            UserDefaults.standard.set(data, forKey: LookupShortcut.manualStorageKey)
        }
    }

    func lookUpSelection() {
        selectedFlowID = nil
        selectedMode = nil
        resetLookup()
        guard let source = NSWorkspace.shared.frontmostApplication,
              source.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            showManualEntry()
            return
        }
        let processID = source.processIdentifier
        sourceApplication = source.localizedName
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
        sourceApplication = nil
        selectedFlowID = nil
        selectedMode = nil
        resetLookup()
        text = ""
        failure = nil
        manualFocusRequest &+= 1
        show(windowFrame: nil, focusesInput: true)
    }

    func submit(_ input: String) {
        selectedMode = nil
        submit(input, useCache: true)
    }

    func retry() { submit(text, useCache: false) }

    private func submit(_ input: String, useCache: Bool) {
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
            lookupSourceLanguage = (flow.source == .automatic ? FlowLanguage.detect(text) ?? .automatic : flow.source).rawValue
            lookupTargetLanguage = flow.target.rawValue
            Task { await wordbook.openIfExisting() }
            activeMode = flow.resolvedMode(text: text, mode: selectedMode)
            let query = try PreparedLookup(text: text, flow: flow, configuration: settings.configuration(for: flow.provider), mode: activeMode)
            if useCache, let cached = cache.value(for: query) {
                answer = cached
                return
            }
            isLoading = true
            let id = generation
            task = Task { [weak self, lookup] in
                do {
                    try await lookup(query) { [weak self] answer in
                        await self?.receive(answer, generation: id)
                    }
                    guard let self, self.generation == id, !Task.isCancelled else { return }
                    if !self.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.cache.insert(self.answer, for: query)
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
        if !text.isEmpty { submit(text, useCache: true) }
    }

    func selectMode(_ mode: LookupMode?) {
        selectedMode = mode
        if !text.isEmpty { submit(text, useCache: true) }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), !CGPreflightPostEventAccess() {
            CGRequestPostEventAccess()
        }
    }

    func dismiss() {
        selectedFlowID = nil
        selectedMode = nil
        resetLookup()
        panel?.dismiss()
        panel = nil
        text = ""
        failure = nil
        dismissalError = nil
        sourceApplication = nil
    }

    func saveToWordbook() {
        guard !isLoading, !isReadingSelection, !isSavingEntry, savedEntryID == nil,
              lookupError == nil, !answer.isEmpty, !text.isEmpty, !lookupTargetLanguage.isEmpty else { return }
        let entry = WordbookEntry(term: text, sourceLanguage: lookupSourceLanguage,
            targetLanguage: lookupTargetLanguage, sourceApplication: sourceApplication, answerMarkdown: answer)
        let id = generation
        isSavingEntry = true
        wordbookError = nil
        Task {
            let saved = await wordbook.save(entry)
            guard generation == id else { return }
            isSavingEntry = false
            if saved { savedEntryID = entry.id }
            else { wordbookError = wordbook.error ?? "The wordbook is busy. Try saving again." }
        }
    }

    func showWordbook() {
        dismiss()
        NSApplication.shared.activate(ignoringOtherApps: true)
        wordbookWindow.show(store: wordbook, settings: settings)
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
        savedEntryID = nil
        isSavingEntry = false
        wordbookError = nil
        lookupSourceLanguage = "auto"
        lookupTargetLanguage = ""
        activeFlowID = nil
        activeMode = nil
        answer = ""
        lookupError = nil
    }

    private func show(windowFrame: CGRect?, focusesInput: Bool = false) {
        if panel == nil { panel = LookupPanelController() }
        dismissalError = panel?.show(model: self, windowFrame: windowFrame, focusesInput: focusesInput)
    }
}

struct LookupResultCache {
    static let lifetime: Duration = .seconds(5 * 60)
    static let limit = 16

    private struct Key: Hashable {
        let baseURL: String
        let model: String
        let prompt: String

        init(_ query: PreparedLookup) {
            baseURL = query.configuration.baseURL
            model = query.configuration.model
            prompt = query.prompt
        }
    }

    private struct Entry {
        let answer: String
        let expiresAt: ContinuousClock.Instant
        var lastAccessedAt: ContinuousClock.Instant
    }

    private var entries: [Key: Entry] = [:]

    mutating func value(for query: PreparedLookup, now: ContinuousClock.Instant = ContinuousClock().now) -> String? {
        removeExpired(at: now)
        let key = Key(query)
        guard var entry = entries[key] else { return nil }
        entry.lastAccessedAt = now
        entries[key] = entry
        return entry.answer
    }

    mutating func insert(_ answer: String, for query: PreparedLookup,
                         now: ContinuousClock.Instant = ContinuousClock().now) {
        removeExpired(at: now)
        entries[Key(query)] = Entry(answer: answer, expiresAt: now.advanced(by: Self.lifetime), lastAccessedAt: now)
        // ponytail: a linear LRU scan is simpler and bounded by the hard 16-entry limit.
        if entries.count > Self.limit,
           let oldest = entries.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    private mutating func removeExpired(at instant: ContinuousClock.Instant) {
        entries = entries.filter { $0.value.expiresAt > instant }
    }
}

import Testing
import AppKit
import Carbon.HIToolbox
@testable import Glossa

@Test func promptSubstitutionPreservesUserContent() {
    #expect(PromptTemplate.flowDefault.contains(PromptTemplate.placeholder))
    #expect(PromptTemplate.render("Define {{text}} / {{text}}", text: "你好\n**word**") == "Define 你好\n**word** / 你好\n**word**")
    #expect(PromptTemplate.render("{{text}}", text: "literal {{text}}") == "literal {{text}}")
    #expect(PromptTemplate.render("{{text}}", text: "") == "")
    #expect(PromptTemplate.render("Keep my instructions", text: "word") == "Keep my instructions")
}

@Test func lookupInputRejectsEmptyOrOversizedSelectionsWithoutTruncation() throws {
    #expect(try LookupInput.validated(" \nhello world\n ") == "hello world")
    let unicode = String(repeating: "👨‍👩‍👧‍👦", count: 2_000)
    #expect(try LookupInput.validated(unicode) == unicode)
    #expect(throws: SelectionFailure.self) { try LookupInput.validated(" \n\t") }
    #expect(throws: SelectionFailure.self) { try LookupInput.validated(unicode + "x") }
}

@Test func panelPlacementHandlesDisplaysLeftOfAndAbovePrimary() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
    let window = PanelPlacement.appKitFrame(from: CGRect(x: 100, y: -1000, width: 1000, height: 700), primaryScreenTop: 900)
    #expect(window.minY == 1200)
    #expect(PanelPlacement.screenIndex(for: window, screens: [primary, left, above]) == 2)
    #expect(PanelPlacement.screenIndex(for: CGRect(x: -1500, y: 100, width: 1000, height: 600), screens: [primary, left]) == 1)
    let panel = PanelPlacement.frame(in: left)
    #expect(left.contains(panel))
    #expect(panel.maxX == left.maxX - 16)
    #expect(panel.maxY == left.maxY - 16)
}

@Test func shortcutsRequireAModifierAndReserveEscape() {
    #expect(LookupShortcut.default.isValid)
    #expect(LookupShortcut.default.label == "⌥A")
    #expect(!LookupShortcut.escape.isValid)
    #expect(!LookupShortcut(keyCode: 0, modifiers: 0, key: "A").isValid)
    #expect(!LookupShortcut(keyCode: 0, modifiers: UInt32(shiftKey), key: "A").isValid)
    #expect(LookupShortcut(keyCode: 0, modifiers: UInt32(controlKey | optionKey), key: "A").label == "⌃⌥A")
}

@MainActor @Test func manualEntryClearsPreviousResultOnFailureAndDismissal() {
    let model = LookupController(settings: isolatedLookupSettings(), lookup: { _, _ in })
    model.submit("bonjour")
    #expect(model.text == "bonjour")
    #expect(model.failure == nil)
    model.submit(String(repeating: "x", count: 2_001))
    #expect(model.text.isEmpty)
    #expect(model.failure == .tooLong)
    model.submit("再见")
    #expect(model.text == "再见")
    model.dismiss()
    #expect(model.text.isEmpty)
    #expect(model.failure == nil)
}

@MainActor func isolatedLookupSettings() -> LookupSettings {
    let suite = "GlossaTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    return LookupSettings(defaults: defaults)
}

@MainActor @Test func translationFlowsMigrateRoutePersistAndPrepareIndependentRequests() async throws {
    let suite = "GlossaTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = APIConfiguration(baseURL: "https://example.com/v1", model: "legacy-model")
    defaults.set(try JSONEncoder().encode(legacy), forKey: APIConfiguration.storageKey)
    defaults.set("Explain {{text}} my way", forKey: PromptTemplate.storageKey)
    let settings = LookupSettings(defaults: defaults)
    let fallback = try #require(settings.flows.first)
    #expect(fallback.prompt == "Explain {{text}} my way")
    #expect(settings.configuration(for: fallback.provider) == legacy)
    #expect(settings.providerName(fallback.provider).contains("Custom endpoint"))
    #expect(LookupSettings(defaults: defaults).flows == settings.flows)
    #expect(LookupSettings(defaults: defaults).canEdit)

    let japanese = TranslationFlow(source: .japanese, target: .english, provider: .openAI, model: "flow-model")
    let english = TranslationFlow(source: .english)
    settings.flows = [fallback, japanese, english]
    #expect(TranslationFlow.match(in: settings.flows, language: .japanese)?.id == japanese.id)
    #expect(TranslationFlow.match(in: settings.flows, language: nil)?.id == fallback.id)
    #expect(TranslationFlow.match(in: [english], language: .french) == nil)
    #expect(TranslationFlow.match(in: [], language: .english) == nil)
    #expect(TranslationFlow.match(in: [fallback, english, TranslationFlow(source: .english)], language: .english) == nil)
    #expect(FlowLanguage.detect("今日はとても良い天気なので、公園を散歩しましょう。") == .japanese)

    let query = try PreparedLookup(text: "literal {{targetLanguage}}", flow: japanese, configuration: legacy)
    #expect(query.configuration.model == "flow-model")
    #expect(query.configuration.baseURL == legacy.baseURL)
    #expect(query.prompt.contains("Response language: English"))
    #expect(query.prompt.contains("Text: literal {{targetLanguage}}"))
    #expect(try PreparedLookup(text: "word", flow: english, configuration: legacy).configuration.model == "legacy-model")
    var invalid = english
    invalid.prompt = "No placeholder"
    #expect(throws: APIError.invalidPrompt) { try PreparedLookup(text: "word", flow: invalid, configuration: legacy) }
    invalid.prompt = String(repeating: "x", count: 65_536) + "{{text}}"
    #expect(throws: APIError.invalidPrompt) { try PreparedLookup(text: "word", flow: invalid, configuration: legacy) }
    try settings.save(.deepSeek, for: .deepSeek)
    #expect(settings.configuration(for: .openAI) == legacy)
    #expect(LookupSettings(defaults: defaults).flows == settings.flows)

    let received = AsyncStream<PreparedLookup>.makeStream()
    let model = LookupController(settings: settings) { request, update in
        received.continuation.yield(request)
        await update(request.configuration.model)
    }
    var requests = received.stream.makeAsyncIterator()
    model.selectFlow(japanese.id)
    model.submit("word")
    #expect(await requests.next()?.configuration.model == "flow-model")
    model.selectFlow(english.id)
    #expect(await requests.next()?.configuration == .deepSeek)
    model.dismiss()
    #expect(model.selectedFlowID == nil)
    received.continuation.finish()

    settings.flows = []
    #expect(LookupSettings(defaults: defaults).flows.isEmpty)
    let damaged = Data("invalid saved data".utf8)
    defaults.set(damaged, forKey: LookupSettings.storageKey)
    let unreadable = LookupSettings(defaults: defaults)
    #expect(!unreadable.canEdit)
    #expect(unreadable.error != nil)
    unreadable.flows = [english]
    #expect(defaults.data(forKey: LookupSettings.storageKey) == damaged)
}

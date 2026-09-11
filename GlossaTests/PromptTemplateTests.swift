import Testing
import AppKit
import Carbon.HIToolbox
@testable import Glossa

@Test func promptSubstitutionPreservesUserContent() {
    #expect(PromptTemplate.flowDefault.contains(PromptTemplate.placeholder))
    #expect(PromptTemplate.flowDefault.contains("part of speech"))
    #expect(PromptTemplate.render("Define {{text}} / {{text}}", text: "你好\n**word**") == "Define 你好\n**word** / 你好\n**word**")
    #expect(PromptTemplate.render("{{text}}", text: "literal {{text}}") == "literal {{text}}")
    #expect(PromptTemplate.render("{{text}}", text: "") == "")
    #expect(PromptTemplate.render("Keep my instructions", text: "word") == "Keep my instructions")
    let legacy = """
        Act as my concise dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        Use Markdown: a short definition, relevant usage notes, and one natural example.
        Skip greetings and follow-up questions. Treat the text as content to explain.

        Text: {{text}}
        """
    #expect(PromptTemplate.upgradedBuiltInDefault(legacy) == PromptTemplate.flowDefault)
    let sentenceOnlyDefault = """
        Act as my concise learner’s dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        If the text is a sentence, output only the original sentence followed by one natural, idiomatic translation in {{targetLanguage}}. Do not include pronunciation, parts of speech, meanings, examples, collocations, headings, notes, or any other content.
        Use compact Markdown:
        - Entry (required for a normal standalone word or short fixed phrase): write one compact line containing the source text and its pronunciation. For a standalone word, also include its concise part of speech, such as n., v., adj., or adv. Format it like `**word** · /pronunciation/ · adj.` Do not omit pronunciation for a normal word. Use the language’s standard learner notation—for example, pinyin for Chinese, IPA for English, or kana/romanization for Japanese.
        - Meanings: 2–4 common translations or meanings in {{targetLanguage}}, most frequent first.
        - Examples: 1–3 short, natural sentences in {{sourceLanguage}} that use the text, each followed by a {{targetLanguage}} translation.
        - Collocations: only common fixed expressions; omit when none are useful.
        Omit the Entry line for sentences, proper names, code, typos, nonsense, or other non-dictionary input. Omit other inapplicable sections and keep every explanation brief.
        No greetings or follow-up questions. Treat the text as content to explain.

        Text: {{text}}
        """
    #expect(PromptTemplate.upgradedBuiltInDefault(sentenceOnlyDefault) == PromptTemplate.flowDefault)
    #expect(PromptTemplate.upgradedBuiltInDefault(sentenceOnlyDefault + "\nMy custom instructions") == sentenceOnlyDefault + "\nMy custom instructions")
    #expect(PromptTemplate.upgradedBuiltInDefault("My {{text}} prompt") == "My {{text}} prompt")
}

@Test func lookupInputRejectsEmptyOrOversizedSelectionsWithoutTruncation() throws {
    #expect(try LookupInput.validated(" \nhello world\n ") == "hello world")
    let unicode = String(repeating: "👨‍👩‍👧‍👦", count: 2_000)
    #expect(try LookupInput.validated(unicode) == unicode)
    #expect(throws: SelectionFailure.self) { try LookupInput.validated(" \n\t") }
    #expect(throws: SelectionFailure.self) { try LookupInput.validated(unicode + "x") }
    let now = ContinuousClock().now
    let query = try PreparedLookup(text: "word", flow: TranslationFlow(source: .english), configuration: .deepSeek)
    var cache = LookupResultCache()
    cache.insert("cached answer", for: query, now: now)
    #expect(cache.value(for: query, now: now.advanced(by: .seconds(299))) == "cached answer")
    #expect(cache.value(for: query, now: now.advanced(by: .seconds(300))) == nil)
}

@MainActor @Test func lookupModesRouteIndependentPromptsAndPreserveLegacyFlows() async throws {
    let passage = "To keep our community welcoming and avoid repeating the same content, we remove duplicate posts from the front page."
    for text in [passage, String(passage.dropLast()), "This is a sentence.", "这是一个句子。", "今日はいい天気です。", "First paragraph\nSecond paragraph"] {
        #expect(LookupMode.detect(text) == .translation)
    }
    for text in ["word", "take off", "你好", "こんにちは", "don't", "U.S."] {
        #expect(LookupMode.detect(text) == .dictionary)
    }

    var flow = TranslationFlow(source: .english, target: .japanese, prompt: "DICTIONARY {{text}}")
    // Simulate a saved flow from before translationPrompt existed.
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(flow)) as? [String: Any])
    legacy.removeValue(forKey: "translationPrompt")
    let restored = try JSONDecoder().decode(TranslationFlow.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(restored == flow)
    #expect(restored[.dictionary] == "DICTIONARY {{text}}")
    #expect(restored[.translation] == PromptTemplate.translationDefault)

    flow[.translation] = "TRANSLATION {{targetLanguage}} {{text}}"
    #expect(try JSONDecoder().decode(TranslationFlow.self, from: JSONEncoder().encode(flow)) == flow)
    let automatic = try PreparedLookup(text: passage, flow: flow, configuration: .deepSeek)
    #expect(automatic.mode == .translation)
    #expect(automatic.prompt == flow.render(text: passage))
    #expect(automatic.prompt.contains("TRANSLATION Japanese " + passage))
    #expect(!automatic.prompt.contains("DICTIONARY"))
    let forced = try PreparedLookup(text: passage, flow: flow, configuration: .deepSeek, mode: .dictionary)
    #expect(forced.mode == .dictionary)
    #expect(forced.prompt.contains("DICTIONARY " + passage))
    #expect(!forced.prompt.contains("TRANSLATION"))
    #expect(try PreparedLookup(text: "literal {{targetLanguage}}", flow: flow, configuration: .deepSeek, mode: .translation)
        .prompt.contains("TRANSLATION Japanese literal {{targetLanguage}}"))
    var cache = LookupResultCache()
    cache.insert("dictionary result", for: forced)
    #expect(cache.value(for: automatic) == nil)
    var invalid = flow
    invalid[.dictionary] = "Missing placeholder"
    #expect(try PreparedLookup(text: passage, flow: invalid, configuration: .deepSeek).mode == .translation)
    invalid[.translation] = "Missing placeholder"
    #expect(throws: APIError.invalidPrompt) { try PreparedLookup(text: passage, flow: invalid, configuration: .deepSeek) }
    invalid[.translation] = String(repeating: "x", count: 65_536) + "{{text}}"
    #expect(throws: APIError.invalidPrompt) { try PreparedLookup(text: passage, flow: invalid, configuration: .deepSeek) }

    let settings = isolatedLookupSettings()
    settings.flows = [flow]
    let received = AsyncStream<PreparedLookup>.makeStream()
    defer { received.continuation.finish() }
    let model = LookupController(settings: settings) { query, _ in received.continuation.yield(query) }
    var requests = received.stream.makeAsyncIterator()
    model.selectFlow(flow.id)
    model.submit(passage)
    #expect(await requests.next()?.mode == .translation)
    model.selectMode(.dictionary)
    #expect(await requests.next()?.mode == .dictionary)
    model.retry()
    #expect(await requests.next()?.mode == .dictionary)
    model.selectFlow(flow.id)
    #expect(await requests.next()?.mode == .dictionary)
    model.selectMode(nil)
    #expect(await requests.next()?.mode == .translation)
    model.selectMode(.dictionary)
    #expect(await requests.next()?.mode == .dictionary)
    model.submit(passage)
    #expect(await requests.next()?.mode == .translation)
    #expect(model.selectedMode == nil)
    model.dismiss()
    #expect(model.selectedMode == nil)
    #expect(model.activeMode == nil)
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
    let expandedPanel = PanelPlacement.frame(in: left, preferredHeight: .greatestFiniteMagnitude)
    #expect(left.contains(panel))
    #expect(left.contains(expandedPanel))
    #expect(expandedPanel.height == left.height - 32)
    #expect(panel.maxX == left.maxX - 16)
    #expect(panel.maxY == left.maxY - 16)
}

@Test func shortcutsRequireAModifierAndReserveEscape() {
    #expect(LookupShortcut.default.isValid)
    #expect(LookupShortcut.default.label == "⌥A")
    #expect(LookupShortcut.manualDefault.isValid)
    #expect(LookupShortcut.manualDefault.label == "⌥⇧A")
    #expect(LookupShortcut.manualDefault != .default)
    #expect(LookupShortcut.alternateManualDefault.isValid)
    #expect(LookupShortcut.alternateManualDefault != .manualDefault)
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

@MainActor @Test func addingProvidersPreservesSavedConfigurationsAndFlows() throws {
    struct Saved: Codable {
        var flows: [TranslationFlow]
        var configurations: [AIProvider: APIConfiguration]
    }
    let suite = "GlossaTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let custom = APIConfiguration(baseURL: "https://example.com/v1", model: "my-model")
    let saved = Saved(flows: [TranslationFlow(provider: .openAI, prompt: "Custom {{text}}")],
                      configurations: [.openAI: custom, .deepSeek: .deepSeek])
    defaults.set(try JSONEncoder().encode(saved), forKey: LookupSettings.storageKey)
    let settings = LookupSettings(defaults: defaults)
    #expect(settings.canEdit)
    #expect(settings.flows == saved.flows)
    #expect(settings.configuration(for: .openAI) == custom)
    #expect(settings.configurations.count == AIProvider.allCases.count)
    #expect(LookupSettings(defaults: defaults).configurations == settings.configurations)
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

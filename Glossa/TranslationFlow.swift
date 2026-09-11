import Foundation
import NaturalLanguage
import Observation

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI, deepSeek, gemini, claude, qwen, kimi, grok, mistral
    var id: Self { self }
    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .gemini: "Google Gemini"
        case .claude: "Claude (experimental)"
        case .qwen: "Qwen · 通义千问"
        case .kimi: "Kimi"
        case .grok: "xAI Grok"
        case .mistral: "Mistral"
        }
    }
    var defaults: APIConfiguration {
        switch self {
        case .openAI: .init(baseURL: "https://api.openai.com/v1", model: "gpt-4.1-mini")
        case .deepSeek: .deepSeek
        case .gemini: .init(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-3.8-flash")
        case .claude: .init(baseURL: "https://api.anthropic.com/v1", model: "claude-haiku-4-5-20251001")
        case .qwen: .init(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen3.8-max")
        case .kimi: .init(baseURL: "https://api.moonshot.ai/v1", model: "kimi-k2.6")
        case .grok: .init(baseURL: "https://api.x.ai/v1", model: "grok-4.6")
        case .mistral: .init(baseURL: "https://api.mistral.ai/v1", model: "mistral-small-latest")
        }
    }

    var setupNote: String {
        switch self {
        case .claude: "Experimental OpenAI compatibility, not the native Messages API. Use a workspace-scoped API key. Haiku is selected for short, fast responses."
        case .qwen: "Defaults to the Beijing endpoint. Your key and model must match the region; you can paste your workspace-specific compatible-mode base URL."
        case .kimi: "Uses the international Moonshot endpoint. K2.6 runs without thinking for short responses; kimi-k3 is also supported with low reasoning effort."
        default: "Uses streaming Chat Completions. Enter a model ID available to your API account."
        }
    }
}

enum FlowLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic = "auto", english = "en", japanese = "ja"
    case simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    case korean = "ko", french = "fr", german = "de", spanish = "es"
    case italian = "it", portuguese = "pt", russian = "ru", arabic = "ar"
    var id: Self { self }
    var name: String {
        switch self {
        case .automatic: "Auto-detect"
        case .english: "English"
        case .japanese: "Japanese"
        case .simplifiedChinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        case .korean: "Korean"
        case .french: "French"
        case .german: "German"
        case .spanish: "Spanish"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .russian: "Russian"
        case .arabic: "Arabic"
        }
    }

    static func detect(_ text: String) -> Self? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let candidates = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        // ponytail: short words can remain ambiguous; keep a manual flow picker instead of another AI request.
        guard let best = candidates.first, best.value >= 0.6,
              candidates.count == 1 || best.value - candidates[1].value >= 0.2 else { return nil }
        return Self(rawValue: best.key.rawValue)
    }
}

enum LookupMode: String, CaseIterable, Identifiable, Sendable {
    case dictionary, translation
    var id: Self { self }
    var name: String { self == .dictionary ? "Dictionary" : "Translation" }

    static func detect(_ input: String, language: FlowLanguage = .automatic) -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // ponytail: punctuation/length heuristics cannot resolve every short phrase; the panel offers a manual override.
        if text.count >= 80 || text.contains(where: \.isNewline)
            || text.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？!?")) != nil {
            return .translation
        }
        let words = NLTokenizer(unit: .word)
        if language != .automatic { words.setLanguage(NLLanguage(rawValue: language.rawValue)) }
        words.string = text
        let range = text.startIndex..<text.endIndex
        let count = words.tokens(for: range).count
        if count >= 6 { return .translation }
        if count > 1 {
            let ending = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’»」』)]}"))
            if ending.hasSuffix(".") { return .translation }
            let sentences = NLTokenizer(unit: .sentence)
            if language != .automatic { sentences.setLanguage(NLLanguage(rawValue: language.rawValue)) }
            sentences.string = text
            if sentences.tokens(for: range).count > 1 { return .translation }
        }
        return .dictionary
    }
}

struct TranslationFlow: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var source: FlowLanguage = .automatic
    var target: FlowLanguage = .simplifiedChinese
    var provider: AIProvider = .deepSeek
    var model = ""
    var prompt = PromptTemplate.flowDefault
    // Missing in older saved flows; nil uses the built-in translation prompt.
    var translationPrompt: String?
    var title: String { "\(source.name) → \(target.name)" }

    subscript(mode: LookupMode) -> String {
        get { mode == .dictionary ? prompt : translationPrompt ?? PromptTemplate.translationDefault }
        set {
            switch mode {
            case .dictionary: prompt = newValue
            case .translation: translationPrompt = newValue
            }
        }
    }

    func resolvedMode(text: String, mode: LookupMode? = nil) -> LookupMode {
        mode ?? LookupMode.detect(text, language: source)
    }

    func render(text: String, mode: LookupMode? = nil) -> String {
        let template = self[resolvedMode(text: text, mode: mode)]
            .replacingOccurrences(of: "{{sourceLanguage}}", with: source == .automatic ? "the detected source language" : source.name)
            .replacingOccurrences(of: "{{targetLanguage}}", with: target.name)
        // Insert user text last so placeholder-like text in a selection stays literal.
        return "Source language: \(source == .automatic ? "Detect from the text" : source.name).\nResponse language: \(target.name). Use this response language even if the instructions below name another language.\n\n"
            + PromptTemplate.render(template, text: text)
    }

    static func match(in flows: [Self], language: FlowLanguage?) -> Self? {
        let exact = flows.filter { $0.source != .automatic && $0.source == language }
        if !exact.isEmpty { return exact.count == 1 ? exact[0] : nil }
        let fallback = flows.filter { $0.source == .automatic }
        return fallback.count == 1 ? fallback[0] : nil
    }
}

struct PreparedLookup: Sendable {
    let text: String
    let configuration: APIConfiguration
    let prompt: String
    let mode: LookupMode

    init(text: String, flow: TranslationFlow, configuration: APIConfiguration, mode: LookupMode? = nil) throws {
        self.text = try LookupInput.validated(text)
        self.mode = flow.resolvedMode(text: self.text, mode: mode)
        var configuration = configuration
        if !flow.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { configuration.model = flow.model }
        self.configuration = try configuration.validated()
        guard flow.target != .automatic, flow[self.mode].contains(PromptTemplate.placeholder) else { throw APIError.invalidPrompt }
        prompt = flow.render(text: self.text, mode: self.mode)
        guard prompt.utf8.count <= 65_536 else { throw APIError.invalidPrompt }
    }
}

@MainActor @Observable
final class LookupSettings {
    static let storageKey = "translationSettings.v1"
    var flows: [TranslationFlow] = [] { didSet { persist() } }
    private(set) var configurations: [AIProvider: APIConfiguration] = [:]
    private(set) var error: String?
    private(set) var canEdit = true
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoaded = false

    private struct Saved: Codable {
        var flows: [TranslationFlow]
        var configurations: [AIProvider: APIConfiguration]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let data = defaults.data(forKey: Self.storageKey) {
                let saved = try JSONDecoder().decode(Saved.self, from: data)
                guard Set(saved.flows.map(\.id)).count == saved.flows.count,
                      saved.flows.allSatisfy({ $0.target != .automatic }),
                      [AIProvider.openAI, .deepSeek].allSatisfy({ saved.configurations[$0] != nil }),
                      saved.flows.allSatisfy({ saved.configurations[$0.provider] != nil }) else {
                    throw APIError.invalidConfiguration
                }
                flows = saved.flows.map { flow in
                    var flow = flow
                    flow.prompt = PromptTemplate.upgradedBuiltInDefault(flow.prompt)
                    return flow
                }
                configurations = saved.configurations
                for provider in AIProvider.allCases where configurations[provider] == nil {
                    configurations[provider] = provider.defaults
                }
                if flows != saved.flows || configurations != saved.configurations {
                    try write(flows: flows, configurations: configurations)
                }
            } else {
                var configuration = APIConfiguration.deepSeek
                if let data = defaults.data(forKey: APIConfiguration.storageKey) {
                    configuration = try JSONDecoder().decode(APIConfiguration.self, from: data)
                }
                let provider: AIProvider = configuration.isDeepSeek ? .deepSeek : .openAI
                configurations = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { ($0, $0.defaults) })
                configurations[provider] = configuration
                var initial = TranslationFlow(provider: provider)
                initial.prompt = PromptTemplate.upgradedBuiltInDefault(
                    defaults.string(forKey: PromptTemplate.storageKey) ?? PromptTemplate.flowDefault
                )
                flows = [initial]
                try write(flows: flows, configurations: configurations)
            }
            isLoaded = true
        } catch {
            canEdit = false
            self.error = "Saved settings could not be read. They have been kept intact. Restore your preferences and reopen Glossa."
        }
    }

    func configuration(for provider: AIProvider) -> APIConfiguration { configurations[provider] ?? provider.defaults }

    func providerName(_ provider: AIProvider) -> String {
        let host = URL(string: configuration(for: provider).baseURL)?.host?.lowercased()
        return host == URL(string: provider.defaults.baseURL)?.host ? provider.name : "\(provider.name) · Custom endpoint"
    }

    func save(_ configuration: APIConfiguration, for provider: AIProvider) throws {
        guard canEdit else { throw APIError.invalidConfiguration }
        var updated = configurations
        updated[provider] = try configuration.validated()
        try write(flows: flows, configurations: updated)
        configurations = updated
        error = nil
    }

    private func persist() {
        guard canEdit, isLoaded else { return }
        do {
            try write(flows: flows, configurations: configurations)
            error = nil
        } catch { self.error = "Changes could not be saved. Keep Settings open and try again." }
    }

    private func write(flows: [TranslationFlow], configurations: [AIProvider: APIConfiguration]) throws {
        defaults.set(try JSONEncoder().encode(Saved(flows: flows, configurations: configurations)), forKey: Self.storageKey)
    }
}

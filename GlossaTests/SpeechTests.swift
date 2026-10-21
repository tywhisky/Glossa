import Testing
import Foundation
@testable import Glossa

@MainActor @Test func speechUsesExplicitLanguagesAndValidatesBeforeStarting() throws {
    // Short words must respect the flow or the user's override, not the Mac's UI language.
    #expect(SpeechController.language(for: "chat", source: .french, override: .automatic) == .french)
    #expect(SpeechController.language(for: "chat", source: .french, override: .english) == .english)
    #expect(SpeechController.language(for: "123", source: .automatic, override: .automatic) == nil)
    #expect(FlowLanguage.simplifiedChinese.speechLocale == "zh-CN")
    #expect(FlowLanguage.traditionalChinese.speechLocale == "zh-TW")
    #expect(FlowLanguage.english.supportsSpeechVoice(language: "en-GB"))
    #expect(!FlowLanguage.english.supportsSpeechVoice(language: "fr-FR"))
    #expect(!FlowLanguage.automatic.supportsSpeechVoice(language: "en-US"))

    let suite = "GlossaSpeechTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(99, forKey: "speechRate")
    let speech = SpeechController(defaults: defaults)
    #expect(speech.rate == 0.5)
    speech.rate = 0.4
    speech.voiceIdentifiers["en"] = "test-unavailable-voice"
    let restored = SpeechController(defaults: defaults)
    #expect(restored.rate == 0.4)
    #expect(restored.voiceIdentifiers["en"] == "test-unavailable-voice")

    // These validation failures never create a synthesizer, play audio, or contact a provider.
    speech.toggle(text: " \n", language: .english, owner: .lookup)
    #expect(speech.error != nil)
    #expect(!speech.isSpeaking)
    speech.toggle(text: String(repeating: "a", count: 2_001), language: .english, owner: .lookup)
    #expect(speech.error != nil)
    #expect(!speech.isSpeaking)
    speech.toggle(text: "123", language: nil, owner: .wordbook)
    #expect(speech.error == "Choose a reading language for this text.")
    speech.stop(owner: .lookup)
    #expect(speech.owner == .wordbook)
    #expect(speech.error != nil)
    speech.stop(owner: .wordbook)
    #expect(speech.owner == nil)
    #expect(speech.error == nil)
}

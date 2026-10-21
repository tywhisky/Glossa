import AVFoundation
import Observation
import SwiftUI

@MainActor @Observable
final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    enum Owner { case lookup, wordbook }

    private(set) var owner: Owner?
    private(set) var isSpeaking = false
    private(set) var error: String?
    var rate: Float {
        didSet { defaults.set(rate, forKey: "speechRate"); stop() }
    }
    var voiceIdentifiers: [String: String] {
        didSet { defaults.set(voiceIdentifiers, forKey: "speechVoices"); stop() }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var utterance: AVSpeechUtterance?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedRate = (defaults.object(forKey: "speechRate") as? NSNumber)?.floatValue
        rate = savedRate.flatMap { [Float(0.4), 0.5, 0.6].contains($0) ? $0 : nil }
            ?? AVSpeechUtteranceDefaultSpeechRate
        voiceIdentifiers = defaults.dictionary(forKey: "speechVoices") as? [String: String] ?? [:]
        super.init()
    }

    subscript(voiceFor language: FlowLanguage) -> String {
        get { voiceIdentifiers[language.rawValue, default: ""] }
        set { voiceIdentifiers[language.rawValue] = newValue }
    }

    static func language(for text: String, source: FlowLanguage, override: FlowLanguage) -> FlowLanguage? {
        if override != .automatic { return override }
        if source != .automatic { return source }
        return FlowLanguage.detect(text)
    }

    func toggle(text input: String, language: FlowLanguage?, owner: Owner) {
        if self.owner == owner && isSpeaking { stop(); return }
        stop()
        self.owner = owner
        let text: String
        do { text = try LookupInput.validated(input) }
        catch {
            self.error = (error as? SelectionFailure)?.localizedDescription ?? "This text cannot be read aloud."
            return
        }
        guard let language, language != .automatic else {
            error = "Choose a reading language for this text."
            return
        }
        let voice: AVSpeechSynthesisVoice?
        if let identifier = voiceIdentifiers[language.rawValue], !identifier.isEmpty {
            voice = AVSpeechSynthesisVoice(identifier: identifier)
        } else {
            voice = AVSpeechSynthesisVoice(language: language.speechLocale)
        }
        guard let voice, language.supportsSpeechVoice(language: voice.language) else {
            error = "No matching voice is available. Choose a voice in Glossa Settings → Lookup → Read Aloud, or download one in macOS Accessibility settings."
            return
        }
        if synthesizer == nil {
            synthesizer = AVSpeechSynthesizer()
            synthesizer?.delegate = self
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        self.utterance = utterance
        isSpeaking = true
        synthesizer?.speak(utterance)
    }

    func stop(owner: Owner? = nil) {
        guard owner == nil || self.owner == owner else { return }
        // Invalidate first: cancellation callbacks may arrive after another reading starts.
        utterance = nil
        isSpeaking = false
        self.owner = nil
        error = nil
        synthesizer?.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    private nonisolated func finished(_ identifier: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, let utterance = self.utterance, ObjectIdentifier(utterance) == identifier else { return }
            self.utterance = nil
            self.isSpeaking = false
            self.owner = nil
        }
    }
}

extension FlowLanguage {
    var speechLocale: String {
        switch self {
        case .simplifiedChinese: "zh-CN"
        case .traditionalChinese: "zh-TW"
        default: rawValue
        }
    }

    func supportsSpeechVoice(language: String) -> Bool {
        self != .automatic && Locale(identifier: language).language.languageCode
            == Locale(identifier: speechLocale).language.languageCode
    }
}

struct SpeechControls: View {
    let speech: SpeechController
    let text: String
    let sourceLanguage: String
    let owner: SpeechController.Owner
    var compact = false
    @State private var language = FlowLanguage.automatic

    private var isSpeaking: Bool { speech.owner == owner && speech.isSpeaking }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: compact ? 2 : 10) {
                if compact {
                    playbackButton.labelStyle(.iconOnly).buttonStyle(.borderless)
                    Menu {
                        languagePicker.pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 4) {
                            if language != .automatic {
                                Text(language.name).lineLimit(1)
                            }
                            Image(systemName: "chevron.down").imageScale(.small)
                        }
                    }
                    .font(.caption)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Choose reading language")
                    .accessibilityLabel("Reading language")
                    .accessibilityValue(language.name)
                } else {
                    playbackButton
                    languagePicker.labelsHidden().fixedSize()
                    Spacer(minLength: 0)
                }
            }
            .controlSize(.small)
            if !compact, speech.owner == owner, let error = speech.error {
                Text(verbatim: error).font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: language) { speech.stop(owner: owner) }
        .onChange(of: text) { language = .automatic; speech.stop(owner: owner) }
        .onChange(of: sourceLanguage) { speech.stop(owner: owner) }
        .onDisappear { speech.stop(owner: owner) }
    }

    private var playbackButton: some View {
        Button(isSpeaking ? "Stop Reading" : "Read Aloud",
               systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2") {
            speech.toggle(text: text, language: SpeechController.language(for: text,
                source: FlowLanguage(rawValue: sourceLanguage) ?? .automatic, override: language), owner: owner)
        }
        .help(isSpeaking ? "Stop reading" : "Read the original text using a macOS voice")
    }

    private var languagePicker: some View {
        Picker("Reading language", selection: $language) {
            Text("Automatic").tag(FlowLanguage.automatic)
            ForEach(FlowLanguage.allCases.filter { $0 != .automatic }) {
                Text($0.name).tag($0)
            }
        }
        .accessibilityLabel("Reading language")
    }
}

struct SpeechSettingsSection: View {
    @Bindable var speech: SpeechController
    @State private var language = FlowLanguage.english
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        Section {
            Picker("Speaking rate", selection: $speech.rate) {
                Text("Slower").tag(Float(0.4))
                Text("Normal").tag(Float(0.5))
                Text("Faster").tag(Float(0.6))
            }
            Picker("Voice language", selection: $language) {
                ForEach(FlowLanguage.allCases.filter { $0 != .automatic }) {
                    Text($0.name).tag($0)
                }
            }
            Picker("Voice", selection: $speech[voiceFor: language]) {
                Text("Automatic macOS voice").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text(verbatim: "\(voice.name) · \(voice.language) · \(quality(voice))").tag(voice.identifier)
                }
                if let saved = speech.voiceIdentifiers[language.rawValue], !saved.isEmpty,
                   !voices.contains(where: { $0.identifier == saved }) {
                    Text("Selected voice unavailable").tag(saved)
                }
            }
        } header: {
            Text("Read Aloud")
        } footer: {
            Text("Click the speaker in a lookup or Read Aloud in a wordbook entry. Speech uses macOS voices without an AI request. Choose an en-US or en-GB voice for an English accent. Download more voices in System Settings → Accessibility; macOS manages their storage.")
        }
        .onAppear(perform: refreshVoices)
        .onChange(of: language) { refreshVoices() }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            refreshVoices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshVoices()
        }
    }

    private func refreshVoices() {
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { language.supportsSpeechVoice(language: $0.language) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { ($0.language, $0.name, $0.quality.rawValue, $0.identifier)
                < ($1.language, $1.name, $1.quality.rawValue, $1.identifier) }
    }

    private func quality(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .enhanced: "Enhanced"
        case .premium: "Premium"
        default: "Standard"
        }
    }
}

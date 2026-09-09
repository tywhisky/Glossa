import AppKit
import Carbon.HIToolbox

struct LookupShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let `default` = Self(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey), key: "A")
    static let escape = Self(keyCode: UInt32(kVK_Escape), modifiers: 0, key: "Esc")
    static let storageKey = "lookupShortcut"

    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    var isValid: Bool {
        let allowed = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        return keyCode < 128 && keyCode != UInt32(kVK_Escape)
            && !(keyCode == UInt32(kVK_ANSI_C) && modifiers == UInt32(cmdKey))
            && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
            && modifiers & ~allowed == 0 && !key.isEmpty && key.count <= 16
    }

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else {
            return .default
        }
        return value
    }

    static func from(_ event: NSEvent) -> Self? {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] {
            if flags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        guard let key = event.charactersIgnoringModifiers?.uppercased(),
              !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let result = Self(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key == " " ? "Space" : key)
        return result.isValid ? result : nil
    }
}

@MainActor
final class GlobalHotKey {
    private let id: UInt32
    private var handler: EventHandlerRef?
    private var reference: EventHotKeyRef?
    private var shortcut: LookupShortcut?
    var onPress: () -> Void = {}

    init(id: UInt32) { self.id = id }

    func register(_ shortcut: LookupShortcut) -> OSStatus {
        if reference != nil && self.shortcut == shortcut { return noErr }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr else { return status }
                // Carbon dispatches this handler on the application's main event loop.
                return MainActor.assumeIsolated {
                    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                    guard hotKeyID.signature == 0x474C4F53, hotKeyID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                    hotKey.onPress()
                    return noErr
                }
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }

        var next: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: 0x474C4F53, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &next)
        guard status == noErr else { return status }
        if let reference { UnregisterEventHotKey(reference) }
        reference = next
        self.shortcut = shortcut
        return noErr
    }

    func stop() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
        shortcut = nil
    }
}

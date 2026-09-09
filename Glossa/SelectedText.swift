import ApplicationServices
import Foundation
import Carbon.HIToolbox

enum LookupInput {
    static let limit = 2_000

    static func validated(_ text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SelectionFailure.unavailable }
        guard text.count <= limit else { throw SelectionFailure.tooLong }
        return text
    }
}

enum SelectionFailure: Error, LocalizedError {
    case permission, unavailable, tooLong, secureInput, heldModifiers
    case clipboardUnavailable, clipboardChanged, clipboardRestoreFailed

    var errorDescription: String? {
        switch self {
        case .permission: "Allow Accessibility access to read the selected text, or paste it here."
        case .unavailable: "No readable selection was found. Select text and try again, or paste it here."
        case .tooLong: "Select at most 2,000 characters. Your selection has not been shortened."
        case .secureInput: "Glossa does not capture text while secure keyboard input is active."
        case .heldModifiers: "Release the shortcut keys after pressing them, then try again."
        case .clipboardUnavailable: "Automatic Copy was skipped because the current clipboard could not be safely preserved."
        case .clipboardChanged: "The clipboard changed during capture. Glossa left the newer contents untouched. Try again."
        case .clipboardRestoreFailed: "macOS could not restore the previous clipboard contents."
        }
    }
}

struct TextSelection: Sendable {
    let text: String?
    let windowFrame: CGRect?
    let failure: SelectionFailure?
}

actor SelectedTextReader {
    private var deadline = ContinuousClock().now

    func read(from processID: pid_t) async -> TextSelection {
        guard AXIsProcessTrusted() else { return .init(text: nil, windowFrame: nil, failure: .permission) }
        guard !IsSecureEventInputEnabled() else { return .init(text: nil, windowFrame: nil, failure: .secureInput) }
        guard !Task.isCancelled else { return .init(text: nil, windowFrame: nil, failure: .unavailable) }
        deadline = ContinuousClock().now + .milliseconds(800)
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let window = element(kAXFocusedWindowAttribute, of: application)
        let frame = window.flatMap(windowFrame)
        var focused = element(kAXFocusedUIElementAttribute, of: application)

        // ponytail: inspect at most six ancestors; add app-specific support only from a reproducible failure.
        for _ in 0..<6 {
            guard let current = focused, !Task.isCancelled else { break }
            if attribute(kAXSubroleAttribute, of: current) as? String == kAXSecureTextFieldSubrole {
                return .init(text: nil, windowFrame: frame, failure: .secureInput)
            }
            if let text = attribute(kAXSelectedTextAttribute, of: current) as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    return .init(text: try LookupInput.validated(text), windowFrame: frame, failure: nil)
                } catch {
                    return .init(text: nil, windowFrame: frame, failure: .tooLong)
                }
            }
            focused = element(kAXParentAttribute, of: current)
        }
        do {
            try Task.checkCancellation()
            let text = try await ClipboardSelectionReader.shared.read(from: processID)
            return .init(text: text, windowFrame: frame, failure: nil)
        } catch {
            return .init(text: nil, windowFrame: frame, failure: (error as? SelectionFailure) ?? .unavailable)
        }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        guard !Task.isCancelled, ContinuousClock().now < deadline else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ name: String, of parent: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: parent), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: window), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(kAXSizeAttribute, of: window), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let positionValue = position as! AXValue
        let sizeValue = size as! AXValue
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}

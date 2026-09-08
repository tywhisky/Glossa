import ApplicationServices
import Foundation

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
    case restrictedBuild, permission, unavailable, tooLong

    var errorDescription: String? {
        switch self {
        case .restrictedBuild: "Selected-text access is unavailable in this build. Type or paste your text below."
        case .permission: "Allow Accessibility access to read the selected text, or paste it here."
        case .unavailable: "No readable selection was found. Select text and try again, or paste it here."
        case .tooLong: "Select at most 2,000 characters. Your selection has not been shortened."
        }
    }
}

struct TextSelection: Sendable {
    let text: String?
    let windowFrame: CGRect?
    let failure: SelectionFailure?
}

actor SelectedTextReader {
    func read(from processID: pid_t) -> TextSelection {
        guard Bundle.main.object(forInfoDictionaryKey: "GlossaSandboxed") as? String != "YES" else {
            return .init(text: nil, windowFrame: nil, failure: .restrictedBuild)
        }
        guard AXIsProcessTrusted() else { return .init(text: nil, windowFrame: nil, failure: .permission) }
        guard !Task.isCancelled else { return .init(text: nil, windowFrame: nil, failure: .unavailable) }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.2)
        let application = AXUIElementCreateApplication(processID)
        let window = element(kAXFocusedWindowAttribute, of: application)
        let frame = window.flatMap(windowFrame)
        var focused = element(kAXFocusedUIElementAttribute, of: application)

        // ponytail: inspect at most six ancestors; add app-specific support only from a reproducible failure.
        for _ in 0..<6 {
            guard let current = focused, !Task.isCancelled else { break }
            if attribute(kAXSubroleAttribute, of: current) as? String == kAXSecureTextFieldSubrole {
                break
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
        return .init(text: nil, windowFrame: frame, failure: .unavailable)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
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

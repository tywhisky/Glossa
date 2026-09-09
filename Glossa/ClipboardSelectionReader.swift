import AppKit
import Carbon.HIToolbox

@MainActor
final class ClipboardSelectionReader {
    static let shared = ClipboardSelectionReader()
    private var isReading = false

    func read(from processID: pid_t) async throws -> String {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw SelectionFailure.permission }
        let active = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
                && !IsSecureEventInputEnabled()
        }
        let deadline = ContinuousClock().now + .seconds(1)
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            try Task.checkCancellation()
            guard active() else { throw SelectionFailure.unavailable }
            guard ContinuousClock().now < deadline else { throw SelectionFailure.heldModifiers }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try await read(pasteboard: .general, isSourceActive: active) {
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
                throw SelectionFailure.unavailable
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.postToPid(processID)
            up.postToPid(processID)
        }
    }

    // The injected Copy action lets tests use private pasteboards without sending input to other apps.
    func read(pasteboard: NSPasteboard, timeout: Duration = .milliseconds(700),
              isSourceActive: () -> Bool, sendCopy: () throws -> Void) async throws -> String {
        let clock = ContinuousClock()
        let queueDeadline = clock.now + .seconds(1)
        while isReading {
            try Task.checkCancellation()
            guard isSourceActive(), clock.now < queueDeadline else { throw SelectionFailure.unavailable }
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        guard isSourceActive() else { throw SelectionFailure.unavailable }
        isReading = true
        defer { isReading = false }

        let snapshot = try ClipboardSnapshot(pasteboard)
        guard isSourceActive(), pasteboard.changeCount == snapshot.changeCount else { throw SelectionFailure.unavailable }
        try Task.checkCancellation()
        try sendCopy()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            try Task.checkCancellation()
            guard isSourceActive() else { throw SelectionFailure.unavailable }
            let copiedCount = pasteboard.changeCount
            if copiedCount != snapshot.changeCount {
                // Copy may publish its representations in stages; require a briefly stable revision.
                try await Task.sleep(for: .milliseconds(30))
                guard pasteboard.changeCount == copiedCount else { throw SelectionFailure.clipboardChanged }
                guard isSourceActive() else { throw SelectionFailure.unavailable }
                let text = pasteboard.string(forType: .string)
                guard pasteboard.changeCount == copiedCount else { throw SelectionFailure.clipboardChanged }
                // No suspension between reading and restoration. Never restore over a later revision.
                try snapshot.restore(pasteboard, ifUnchangedSince: copiedCount)
                try Task.checkCancellation()
                guard let text else { throw SelectionFailure.unavailable }
                return try LookupInput.validated(text)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        // An unchanged pasteboard is not a successful Copy, even if it already contains text.
        throw SelectionFailure.unavailable
    }
}

@MainActor
struct ClipboardSnapshot {
    let changeCount: Int
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) throws {
        changeCount = pasteboard.changeCount
        let originals = pasteboard.pasteboardItems ?? []
        guard originals.count <= 16 else { throw SelectionFailure.clipboardUnavailable }
        var saved: [[NSPasteboard.PasteboardType: Data]] = []
        var size = 0
        for item in originals {
            guard item.types.count <= 32 else { throw SelectionFailure.clipboardUnavailable }
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw SelectionFailure.clipboardUnavailable }
                size += data.count
                // ponytail: retain at most 1 MiB; skip Copy when the clipboard cannot be fully preserved.
                guard size <= 1_048_576 else { throw SelectionFailure.clipboardUnavailable }
                representations[type] = data
            }
            saved.append(representations)
        }
        guard pasteboard.changeCount == changeCount else { throw SelectionFailure.clipboardChanged }
        items = saved
    }

    func restore(_ pasteboard: NSPasteboard, ifUnchangedSince copiedCount: Int) throws {
        let restored = try items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                guard item.setData(data, forType: type) else { throw SelectionFailure.clipboardUnavailable }
            }
            return item
        }
        // NSPasteboard has no atomic compare-and-restore. Check immediately before writing.
        guard pasteboard.changeCount == copiedCount else { throw SelectionFailure.clipboardChanged }
        pasteboard.clearContents()
        guard restored.isEmpty || pasteboard.writeObjects(restored) else { throw SelectionFailure.clipboardRestoreFailed }
    }
}

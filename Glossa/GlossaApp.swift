import AppKit
import SwiftUI

@main
struct GlossaApp: App {
    @NSApplicationDelegateAdaptor(GlossaDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            GlossaMenu(model: delegate.lookup)
        } label: {
            Image(nsImage: Self.menuBarIcon)
                .accessibilityLabel("Glossa")
        }

        Settings {
            PromptSettingsView(model: delegate.lookup)
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentMinSize)
    }

    private static let menuBarIcon: NSImage = {
        let image = Bundle.main.url(forResource: "dict", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "book.closed", accessibilityDescription: "Glossa")
            ?? NSImage()
        // MenuBarExtra uses the native image size rather than SwiftUI frame modifiers.
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()
}

@MainActor
final class GlossaDelegate: NSObject, NSApplicationDelegate {
    let lookup = LookupController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted tests must not register global shortcuts or read other apps.
        guard NSClassFromString("XCTestCase") == nil else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification, object: nil)
        lookup.start()
    }

    func applicationDidUpdate(_ notification: Notification) {
        updateDockVisibility()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // willClose is sent before isVisible changes; reconcile after the close completes.
        DispatchQueue.main.async { [weak self] in self?.updateDockVisibility() }
    }

    private func updateDockVisibility() {
        let hasOpenWindow = NSApp.windows.contains {
            // The status item also owns a visible window, but must not keep the Dock icon alive.
            ($0.canBecomeMain || $0 is ResultPanel) && ($0.isVisible || $0.isMiniaturized)
        }
        let policy: NSApplication.ActivationPolicy = hasOpenWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        lookup.stop()
    }
}

private struct GlossaMenu: View {
    let model: LookupController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Glossa · AI-only dictionary")
        Text("Select text, then press \(model.shortcut.label)")
        Text("Open manual input with \(model.manualShortcut.label)")
        if let error = model.shortcutError { Text(verbatim: error) }
        if let error = model.manualShortcutError { Text(verbatim: error) }
        Button("Type or Paste Text…") { model.showManualEntry() }
        Button("Wordbook…") {
            model.showWordbook()
        }
        .keyboardShortcut("b")
        Divider()
        Button("Settings…") {
            model.dismiss()
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Glossa") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

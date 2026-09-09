import AppKit
import SwiftUI

@main
struct GlossaApp: App {
    @NSApplicationDelegateAdaptor(GlossaDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Glossa", systemImage: "character.book.closed") {
            GlossaMenu(model: delegate.lookup)
        }

        Settings {
            PromptSettingsView(model: delegate.lookup)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class GlossaDelegate: NSObject, NSApplicationDelegate {
    let lookup = LookupController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted tests must not register global shortcuts or read other apps.
        guard NSClassFromString("XCTestCase") == nil else { return }
        lookup.start()
    }

    func applicationWillTerminate(_ notification: Notification) { lookup.stop() }
}

private struct GlossaMenu: View {
    let model: LookupController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Glossa · AI-only dictionary")
        Text("Select text, then press \(model.shortcut.label)")
        if let error = model.shortcutError { Text(verbatim: error) }
        Button("Type or Paste Text…") { model.showManualEntry() }
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

import AppKit
import SwiftUI

@main
struct GlossaApp: App {
    @NSApplicationDelegateAdaptor(GlossaDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            GlossaMenu(model: delegate.lookup)
        } label: {
            ZStack {
                Image(systemName: "book.closed")
                Text("G")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .offset(y: 1)
            }
            .accessibilityLabel("Glossa")
        }

        Settings {
            PromptSettingsView(model: delegate.lookup)
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentMinSize)
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
        Text("Open manual input with \(model.manualShortcut.label)")
        if let error = model.shortcutError { Text(verbatim: error) }
        if let error = model.manualShortcutError { Text(verbatim: error) }
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

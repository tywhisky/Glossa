import AppKit
import SwiftUI

@main
struct GlossaApp: App {
    var body: some Scene {
        MenuBarExtra("Glossa", systemImage: "character.book.closed") {
            GlossaMenu()
        }

        Settings {
            PromptSettingsView()
        }
    }
}

private struct GlossaMenu: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Glossa · AI-only dictionary")
        Text("Early development — lookups coming soon")
        Divider()
        Button("Prompt Settings…") {
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

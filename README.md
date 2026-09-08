# Glossa

A quiet, AI-only dictionary for macOS. Native SwiftUI, your API key, your prompt.

Glossa aims to make looking up a word disappear into the reading experience: select text, press a shortcut, read a compact result in the top-right corner, and carry on. Save the words you care about to a personal wordbook, with optional iCloud sync.

专注阅读的原生 macOS AI 词典：自定义 Prompt、快捷键取词、右上角结果面板，以及支持 iCloud 同步的单词本。保持轻量、清爽、可长期驻留。

## Status

**Interaction prototype, not a working AI dictionary yet.**

Available now:

- A native menu bar app with no Dock icon or launch window.
- A configurable global shortcut (Option+A by default), with conflict reporting and recording in Settings.
- A transient top-right panel with manual typing/pasting, a clearly labeled example layout, Escape/outside-click dismissal, and replacement of the previous result.
- Input validation for words, phrases, and sentences up to 2,000 Swift characters (extended grapheme clusters), without truncating oversized selections.
- Prompt settings saved locally, with literal `{{text}}` substitution and a live prompt preview.
- A standard Xcode project, Swift 6 checks, a small Swift Testing check, and macOS CI.
- App Sandbox remains enabled pending approval for the direct-distribution build change. Accessibility selection code is implemented but disabled in this build; the panel offers manual input instead. No Accessibility prompt appears at launch. Xcode disables the configured Hardened Runtime for ad-hoc local builds.
- Zero third-party runtime dependencies, analytics, background polling, or bundled models.

Next milestones:

1. Finish the selected-text interaction validation in Chrome webpages and Preview text PDFs: approve the app's non-sandboxed distribution configuration, grant Accessibility access manually, and verify selection capture, focus, multiple screens, dismissal, and memory. The intended panel position is the top-right of the screen containing the reading window, without taking keyboard focus on appearance. The pointer's screen is the fallback when the window cannot be read.
2. One complete AI lookup path: Keychain credentials, a mainstream provider API through `URLSession`, user-defined prompts, cancellable streaming, and native result rendering. Add other provider protocols as needed; provider compatibility must be tested, not assumed.
3. A local wordbook with SwiftData, followed by opt-in private CloudKit sync and export/import for actual backups.

Static dictionaries, OCR, screen capture, lessons, and a local inference engine are outside the product scope.

## Build and run

Requires macOS 14 or newer and Xcode 16 or newer. Open `Glossa.xcodeproj`, select the **Glossa** scheme and **My Mac**, then Run. Look for the book/character symbol in the menu bar. Use **Settings…** to edit your shortcut and prompt, **Type or Paste Text…** to open the interaction preview, and **Quit Glossa** to exit. Option+A also opens the panel from another app; the current sandboxed build asks for manual input.

No packages, API keys, environment files, or paid developer membership are required for the bootstrap. Local builds use ad-hoc signing. A distributable app will need a real signing identity and notarization.

```sh
xcodebuild test -project Glossa.xcodeproj -scheme Glossa \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=-

xcodebuild build -project Glossa.xcodeproj -scheme Glossa \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=-

open build/DerivedData/Build/Products/Release/Glossa.app
```

If `xcodebuild` points at Command Line Tools, set `DEVELOPER_DIR` for your shell to your installed Xcode, for example:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

For optional personal signing settings, copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig`. Keep the shared configuration free of developer team IDs and machine paths.

## Design constraints

**Small at rest.** Keep the idle process event-driven. Create the network session, result UI, and wordbook storage only when needed. Bound response sizes and caches, cancel superseded work, and keep heavy parsing away from the main actor. Use native text rendering for the supported Markdown subset; arbitrary HTML/CSS is not part of prompt-controlled layout.

**Measure before promising a number.** Native SwiftUI alone does not guarantee memory below 100 MB. Measure Release builds outside the debugger on named hardware/OS versions: fresh launch, 60 seconds idle, repeated lookups, opening the wordbook, and after closing each window. Track physical footprint, idle CPU/wakeups, and whether memory settles after repeated use. A bootstrap baseline does not predict the finished dictionary's footprint.

Bootstrap observation (2026-09-08): on an M3 Pro MacBook Pro with 36 GB RAM, macOS 27 beta (`26A5406e`), built with Xcode 27 beta, the Release process after more than 60 seconds idle showed **17.2 MB physical footprint** (`vmmap -summary`, peak 17.6 MB) and a **0.0% CPU snapshot** (`ps`). This single launch had no query or wordbook workload. Debug tests and the arm64/x86_64 Release build passed locally; automated native UI inspection timed out, so settings/menu interaction still needs a manual check. macOS 14 runtime compatibility has not been exercised locally.

**Cross-app selection needs a real permission spike.** The app is intended for distribution outside the Mac App Store. Apple lists assistive Accessibility API usage among [features incompatible with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox). The current configuration remains sandboxed: changing both `ENABLE_APP_SANDBOX` and its entitlement requires explicit approval. Disabling the app's sandbox would remove its filesystem/network sandbox restrictions; it would not grant macOS Accessibility access, disable system security, or replace Developer ID signing/notarization. After approval, validate a signed build with permission denial and unsupported apps before claiming Chrome/Preview support.

Selection capture uses a serial actor, bounded AX messaging timeouts, and only the focused element and up to six ancestors. Superseded or dismissed reads cannot update the panel. Mouse monitors and the temporary Escape shortcut exist only while the panel is visible; closing it releases its content. No background selection polling, synthetic Copy command, or clipboard replacement is used.

Current verification: five Swift Testing checks pass (prompt substitution, input bounds/Unicode, multi-screen geometry, shortcut validation, and result cleanup), and the universal Release build succeeds. The built app's sandbox entitlement was verified as enabled. Native UI automation still times out; shortcut delivery, focus behavior, Chrome/Preview capture, and repeated-open memory measurements remain manual acceptance checks, not verified claims.

**Sync is not backup.** SwiftData with private CloudKit is the intended sync path, currently unimplemented. It needs an Apple Developer team, a real iCloud container, signing capabilities, a compatible schema, and two-device validation. Use defaults/optional fields and avoid uniqueness constraints that CloudKit cannot enforce. Deletions also sync, so provide a separate export/import path for recovery. See [Apple's SwiftData sync guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

## Privacy and secrets

The prototype makes no network requests. Only your prompt and shortcut are persisted, in this Mac's app preferences. Selected and manually entered text stays in memory and is cleared on dismissal; the clipboard is read only when you explicitly paste. Do not put credentials or sensitive source text in the prompt itself.

API credentials will live in macOS Keychain when provider support is implemented. They must never be stored in `UserDefaults`, prompts, `.xcconfig`, source code, `.env` files bundled into the app, or the wordbook/iCloud records. Future lookups will send the selected text and your prompt to the provider you configure; network access must be explicit and use HTTPS.

`.gitignore` excludes `.env` variants (except a placeholder-only `.env.example`), local signing overrides, certificates/private keys, Xcode user state, databases, and build/profiling output. Ignoring a file does not remove it from Git history. Review staged changes before every push. Never paste keys, private prompts, or selected text into logs or public issues. If a credential is exposed, revoke it first.

## Contributing and skills

See [CONTRIBUTING.md](CONTRIBUTING.md) for checks, conventions, and the recommended SwiftUI skill. [AGENTS.md](AGENTS.md) records the product boundaries for coding agents.

## License

[MIT](LICENSE).

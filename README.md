# Glossa

A quiet, AI-only dictionary for macOS. Native SwiftUI, your API key, your prompt.

Glossa aims to make looking up a word disappear into the reading experience: select text, press a shortcut, read a compact result in the top-right corner, and carry on. Save the words you care about to a personal wordbook, with optional iCloud sync.

专注阅读的原生 macOS AI 词典：自定义 Prompt、快捷键取词、右上角结果面板，以及支持 iCloud 同步的单词本。保持轻量、清爽、可长期驻留。

## Status

**Flow-based AI lookup and native Settings redesign implemented; live-provider and interactive UI acceptance checks are still pending.**

Available now:

- A native menu bar app with no Dock icon or launch window.
- Configurable global shortcuts for selected-text lookup (Option+A by default) and manual input (Option+Shift+A), with conflict reporting and recording in Settings.
- A borderless top-right panel on the reading window's screen, with manual typing/pasting, streaming results, Escape/outside-click dismissal, and replacement of the previous result.
- Input validation for words, phrases, and sentences up to 2,000 Swift characters (extended grapheme clusters), without truncating oversized selections.
- Separate, collapsible DeepSeek and OpenAI configurations with a default model per provider; credentials stored per base URL in macOS Keychain.
- Cancellable streaming, stop/retry, bounded responses, a five-minute 16-entry in-memory result cache, and native inline Markdown (bold, emphasis, code, links, and preserved line breaks). Block headings, tables, HTML, and CSS layout are not implemented.
- Native Settings panes for Lookup, AI Providers, and Translation Flows; an inline shortcut recorder and a separate permission group.
- Collapsible language flows with individual prompts, provider selection, optional model overrides, and offline prompt previews. Source-language matching uses macOS Natural Language on demand; the result panel supports manual flow selection.
- A standard Xcode project, Swift 6 checks, a small Swift Testing check, and macOS CI.
- Direct-distribution builds run outside App Sandbox so user-triggered selected-text access can work. Glossa requests Accessibility access only when you choose the permission action; it does not prompt at launch. Xcode disables the configured Hardened Runtime for ad-hoc local builds.
- Zero third-party runtime dependencies, analytics, background polling, or bundled models.

Next milestones:

1. Finish selected-text interaction validation in Chrome webpages and Preview text PDFs: grant Accessibility access manually, then verify direct selection capture, automatic Copy fallback, clipboard restoration, focus, multiple screens, dismissal, and memory. The borderless panel appears at the top-right of the screen containing the reading window without taking keyboard focus on appearance. The pointer's screen is the fallback when the window cannot be read.
2. Validate a real DeepSeek query with a user-supplied key, then measure repeated queries and idle memory. Test other OpenAI-compatible endpoints before claiming support; add other protocols only with an actual provider need.
3. A local wordbook with SwiftData, followed by opt-in private CloudKit sync and export/import for actual backups.

Static dictionaries, OCR, screen capture, lessons, and a local inference engine are outside the product scope.

## Build and run

Requires macOS 14 or newer and Xcode 16 or newer. Open `Glossa.xcodeproj`, select the **Glossa** scheme and **My Mac**, then Run. Look for the book/character symbol in the menu bar. Use **Settings…** to edit your AI providers, shortcuts, and translation flows, **Type or Paste Text…** to open the lookup panel, and **Quit Glossa** to exit. After granting selected-text access, select text in another app and press Option+A to look it up automatically, or press Option+Shift+A to open manual input.

No packages, API keys, environment files, or paid developer membership are required to build and run offline tests. A real lookup requires your provider API key and sufficient account balance. Local builds use ad-hoc signing unless the ignored `Config/Local.xcconfig` supplies an Apple Development identity. A distributable app will need a Developer ID identity and notarization.

```sh
xcodebuild test -project Glossa.xcodeproj -scheme Glossa \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData

xcodebuild build -project Glossa.xcodeproj -scheme Glossa \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData

open build/DerivedData/Build/Products/Release/Glossa.app
```

If `xcodebuild` points at Command Line Tools, set `DEVELOPER_DIR` for your shell to your installed Xcode, for example:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

For optional personal signing settings, copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig`. Keep the shared configuration free of developer team IDs and machine paths.

## Configure DeepSeek

In **Settings… → AI Providers**, expand DeepSeek and use its defaults: base URL `https://api.deepseek.com`, model `deepseek-v4-flash`. Enter your key in the secure field and click **Save**. Then use **Type or Paste Text… → Look Up**. Glossa sends the assembled prompt only when you initiate a lookup or retry. Saving settings and previewing a prompt do not call an API.

The URL, model, request builder, and SSE decoder are shared with OpenAI-compatible Chat Completions endpoints. OpenAI has its own configuration, initially `https://api.openai.com/v1` with `gpt-4.1-mini`. Use a base URL, not the complete `/chat/completions` path, and choose a supported Chat Completions model. Custom endpoints are labeled in Settings. Keys are scoped to the normalized base URL; changing endpoints does not reuse another endpoint’s key. Leave the key field blank to keep its saved key, or use **Delete Key…** to remove it for the displayed URL.

DeepSeek requests explicitly disable thinking for short dictionary responses. That extension is omitted for other hosts. The client requests at most 2,048 output tokens; it limits assembled prompts and output to 64 KiB, SSE events to 64 KiB, and received stream data to 1 MiB. Requests use an ephemeral session, a 30-second inactivity timeout and a 90-second resource timeout, with no automatic retry, disk cache, cookies, or redirects. Completed results may be reused from the five-minute in-memory cache; Retry bypasses it. Truncated or interrupted responses are marked as incomplete.

Defaults and protocol reviewed on 2026-09-08 against the [DeepSeek documentation](https://api-docs.deepseek.com/) and [OpenAI Chat Completions streaming reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events). Compatibility here means streaming Chat Completions with text deltas and `max_tokens`; it does not include Responses, tools, images, or every model-specific option.

## Translation flows

**Settings… → Translation Flows** replaces the global Prompt settings. Each expandable item owns a source language, response language, provider, optional model override, and prompt. For example, Japanese → English can explain Japanese words in English, while English → Simplified Chinese explains English words in Chinese. The default is a dictionary explanation; write “only translate” in an individual prompt for plain translation.

Use `{{text}}`, `{{sourceLanguage}}`, and `{{targetLanguage}}` in prompts. Glossa includes the selected source/response language instructions in every assembled prompt and substitutes user text last, keeping placeholder-like input literal. Previews show the complete prompt without contacting a provider. A blank model override inherits the provider’s default; switching providers clears the override. Provider changes require **Save**; flow edits save automatically. Deleting a flow requires confirmation and keeps provider settings and keys.

On a lookup, a confident local language detection selects a unique flow for that source. A unique **Auto-detect** source flow handles unmatched or uncertain text. Multiple matching flows, multiple fallback flows, or no applicable flow require a choice in the result panel before any request is sent. With no flows, the panel directs you to Settings. The panel’s flow picker can also override an automatic match; choosing another flow cancels the previous query and starts a new one. Manual choices apply to the current lookup and reset for new text. Short words and mixed-language selections can be misidentified, so manual correction remains available.

Existing configuration and prompt migrate to one Auto-detect → Simplified Chinese flow, preserving the endpoint, model, custom prompt, and URL-scoped Keychain entry. Other legacy OpenAI-compatible URLs remain editable and are marked as custom endpoints. Unreadable saved settings are retained and reported, with editing and lookup blocked rather than overwriting them with defaults. These preferences stay local; wordbook/iCloud sync is still unimplemented.

The UI uses native grouped forms, disclosure controls, and settings panes, following Apple’s [Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings) and [disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls). Language detection uses [NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer). The OpenAI default is documented as supporting Chat Completions in the [GPT-4.1 mini reference](https://developers.openai.com/api/docs/models/gpt-4.1-mini); live compatibility has not been exercised here.

## Design constraints

**Small at rest.** Keep the idle process event-driven. Create the network session, result UI, and wordbook storage only when needed. Bound response sizes and caches, cancel superseded work, and keep heavy parsing away from the main actor. Use native text rendering for the supported Markdown subset; arbitrary HTML/CSS is not part of prompt-controlled layout.

**Measure before promising a number.** Native SwiftUI alone does not guarantee memory below 100 MB. Measure Release builds outside the debugger on named hardware/OS versions: fresh launch, 60 seconds idle, repeated lookups, opening the wordbook, and after closing each window. Track physical footprint, idle CPU/wakeups, and whether memory settles after repeated use. A bootstrap baseline does not predict the finished dictionary's footprint.

Bootstrap observation (2026-09-08): on an M3 Pro MacBook Pro with 36 GB RAM, macOS 27 beta (`26A5406e`), built with Xcode 27 beta, the Release process after more than 60 seconds idle showed **17.2 MB physical footprint** (`vmmap -summary`, peak 17.6 MB) and a **0.0% CPU snapshot** (`ps`). This single launch had no query or wordbook workload. Debug tests and the arm64/x86_64 Release build passed locally; automated native UI inspection timed out, so settings/menu interaction still needs a manual check. macOS 14 runtime compatibility has not been exercised locally.

**Cross-app selection needs explicit system permission.** The app is intended for distribution outside the Mac App Store. Apple lists assistive Accessibility API usage among [features incompatible with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), so the approved direct-distribution configuration disables App Sandbox. This does not grant Accessibility access, disable macOS system protections, or replace Developer ID signing/notarization. Validate a signed build with permission denial and unsupported apps before claiming Chrome/Preview support.

Selection capture first checks the focused Accessibility element and up to six ancestors. If no readable selection is exposed, Glossa sends a Copy command, accepts only a fresh clipboard revision, and attempts to restore the complete previous clipboard without overwriting a newer revision. Secure input and secure text fields stop capture. Superseded or dismissed reads cannot update the panel. Mouse monitors and the temporary Escape shortcut exist only while the panel is visible; closing it releases its content.

Current verification (2026-09-09): the Debug build and all 12 Swift Testing checks pass, with no skipped tests, and the universal Release build succeeds using command-line ad-hoc signing overrides because the current personal development certificate is unavailable. Tests cover settings migration/reloading, language routing and ambiguity, per-flow prompt/model request preparation, manual switching, empty/corrupt settings, request validation, bounded SSE decoding, Keychain isolation/update/deletion, offline URLSession transport, and stale-result rejection. They never contact paid APIs. Light/dark offscreen renders of the native Settings content were inspected; interactive native UI automation still times out. Keyboard/VoiceOver interaction, live provider queries, Chrome/Preview capture, flow-menu dismissal behavior, and repeated-open memory measurements remain manual acceptance checks. The bootstrap Release memory observation above does not describe this version.

**Sync is not backup.** SwiftData with private CloudKit is the intended sync path, currently unimplemented. It needs an Apple Developer team, a real iCloud container, signing capabilities, a compatible schema, and two-device validation. Use defaults/optional fields and avoid uniqueness constraints that CloudKit cannot enforce. Deletions also sync, so provide a separate export/import path for recovery. See [Apple's SwiftData sync guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

## Privacy and secrets

AI provider configurations, translation flows and their prompts, and your shortcuts are persisted in this Mac’s app preferences. A lookup sends your input and assembled prompt to the configured provider over HTTPS; provider retention policies apply. The app does not persist query text or responses to disk; completed results can remain in memory for up to five minutes and disappear when the app quits. The visible query is cleared on dismissal. The clipboard is read only when you explicitly paste. Do not put credentials or sensitive source text in the prompt itself.

API credentials live in macOS Keychain, without Keychain synchronization. They are never stored in `UserDefaults`, prompts, `.xcconfig`, source code, app resources, or wordbook/iCloud records. Direct-distribution builds run outside App Sandbox; API requests still require HTTPS. Requests exist only during a lookup and are cancelled when superseded or dismissed; HTTP errors are shown without echoing raw provider bodies or credentials.

`.gitignore` excludes `.env` variants (except a placeholder-only `.env.example`), local signing overrides, certificates/private keys, Xcode user state, databases, and build/profiling output. Ignoring a file does not remove it from Git history. Review staged changes before every push. Never paste keys, private prompts, or selected text into logs or public issues. If a credential is exposed, revoke it first.

## Contributing and skills

See [CONTRIBUTING.md](CONTRIBUTING.md) for checks, conventions, and the recommended SwiftUI skill. [AGENTS.md](AGENTS.md) records the product boundaries for coding agents.

## License

[MIT](LICENSE).

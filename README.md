<p align="center">
  <img src="docs/assets/glossa-icon.png" width="128" height="128" alt="Glossa app icon">
</p>

<h1 align="center">Glossa</h1>

<p align="center">A quiet, AI-only dictionary for macOS.</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

Glossa does three things: lookup, translation, and a wordbook. That's it. No lessons, feeds, piles of static dictionaries, or browser crammed into the app.

Shape every result with your own prompt. Glossa gets back to the basics of language learning instead of pretending to be a linguist.

> [!NOTE]
> Lookup, translation flows, and the local wordbook are implemented. Live provider coverage, cross-app interaction, and private iCloud sync still need validation.

## Why Glossa

- **Pure by design.** Look up, translate, save. Nothing is competing for your attention.
- **Your AI, your words.** Choose a provider, response language, and model, then write separate prompts for dictionary and translation results.
- **Look up without changing context.** Select text in most macOS apps, press a shortcut, and read the result in a compact panel at the top-right of the relevant screen. When direct selection is unavailable, Glossa can use a careful Copy fallback. Accessibility permission is required.
- **A wordbook that remembers the useful part.** Save results, search previous encounters, add context and editable AI memory notes, recover deleted entries, and import or export a readable `.glossawords` backup.
- **Native and deliberately small.** Glossa uses SwiftUI and Apple frameworks, stays event-driven while idle, and ships with no third-party runtime dependencies, analytics, background polling, or bundled model.
- **Private by default.** API keys live in macOS Keychain. Text is sent only when you start a lookup, retry, or explicitly create an AI note.

## How it works

1. Select text in another app and press <kbd>⌥ A</kbd>, or press <kbd>⌥ ⇧ A</kbd> to type or paste.
2. Glossa chooses a language flow and decides whether the text is a dictionary entry or a translation. You can override either choice.
3. The configured provider streams a compact Markdown result into the lookup panel.
4. Save anything worth remembering to the wordbook.

Shortcuts, language flows, prompts, providers, and models are editable in Settings. Provider presets currently include DeepSeek, OpenAI, Gemini, Claude (experimental), Qwen, Kimi, Grok, and Mistral through OpenAI-compatible Chat Completions endpoints.

## Wordbook and iCloud

The local wordbook is built with SwiftData. Each saved encounter can keep the original result, source app, your context, a short meaning, and a memory hook. Backup import/export is separate from sync, so you are not relying on iCloud as your only copy.

Private CloudKit integration is present for properly provisioned builds, but real two-device synchronization, offline conflicts, and account changes still need validation. The ordinary local build stays local-only.

## Build and run

Glossa requires macOS 14 or newer and Xcode 16 or newer. Open `Glossa.xcodeproj`, select the **Glossa** scheme and **My Mac**, then run the app. There are no package dependencies, environment files, or API keys required for an offline build.

```sh
xcodebuild test -project Glossa.xcodeproj -scheme Glossa \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData

xcodebuild build -project Glossa.xcodeproj -scheme Glossa \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData
```

A real lookup needs a supported provider account and API key. Selected-text lookup also needs Glossa enabled in **System Settings → Privacy & Security → Accessibility**. Local builds use ad-hoc signing unless you add personal settings in the ignored `Config/Local.xcconfig`.

## Project status

Implemented:

- Native menu bar app, global shortcuts, selected-text and manual lookup
- Streaming Markdown results with stop, retry, bounded responses, and a small in-memory cache
- Per-language dictionary and translation flows with configurable providers, models, and prompts
- Local SwiftData wordbook, editable AI notes, recoverable deletion, and backup import/export
- Optional private CloudKit configuration for provisioned builds

Still needs validation:

- Live requests across every included provider preset
- Selection capture and Copy fallback across representative apps such as Chrome and Preview
- Signed, two-device iCloud sync and conflict behavior
- Keyboard, VoiceOver, interactive UI, and current Release memory measurements

Static dictionaries, OCR, screen capture, lessons, embedded result browsers, and local model runtimes are intentionally out of scope.

Implementation details, security limits, provider behavior, and the current validation record live in [Technical notes](docs/technical-notes.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build checks and project conventions. [AGENTS.md](AGENTS.md) records the product boundaries used for development.

## License

[MIT](LICENSE)

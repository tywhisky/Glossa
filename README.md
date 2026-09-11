# Glossa

A quiet, AI-only dictionary for macOS. Native SwiftUI, your API key, your prompt.

Glossa aims to make looking up a word disappear into the reading experience: select text, press a shortcut, read a compact result in the top-right corner, and carry on. Save the words you care about to a personal wordbook, with optional iCloud sync.

专注阅读的原生 macOS AI 词典：自定义 Prompt、快捷键取词、右上角结果面板，以及支持 iCloud 同步的单词本。保持轻量、清爽、可长期驻留。

## Status

**AI lookup, native Settings, and a local wordbook with AI note editing and backup import/export are implemented. Optional CloudKit integration is gated by signing; live-provider, iCloud, and interactive UI acceptance checks remain pending.**

Available now:

- A native menu bar app with a 16-point template icon and no launch window; its Dock icon appears while Settings or a lookup panel is open (including minimized windows), and hides when the last one closes. The menu bar itself does not count as an open window. Interactive verification of these transitions is pending.
- Configurable global shortcuts for selected-text lookup (Option+A by default) and manual input (Option+Shift+A), with conflict reporting and recording in Settings.
- A borderless top-right panel on the reading window's screen, with manual typing/pasting, streaming results, Escape/outside-click dismissal, and replacement of the previous result.
- Input validation for words, phrases, and sentences up to 2,000 Swift characters (extended grapheme clusters), without truncating oversized selections.
- Separate, collapsible DeepSeek, OpenAI, Gemini, Claude (experimental), Qwen, Kimi, Grok, and Mistral configurations with a default model per provider; credentials stored per base URL in macOS Keychain. New presets are documentation-reviewed, not live-key verified.
- Cancellable streaming, stop/retry, bounded responses, a five-minute 16-entry in-memory result cache, and native inline Markdown (bold, emphasis, code, links, and preserved line breaks). Block headings, tables, HTML, and CSS layout are not implemented.
- Native Settings panes for Lookup, AI Providers, and Translation Flows; an inline shortcut recorder and a separate permission group.
- A bookmark action for completed lookups and a searchable, native two-column Wordbook window. Saved encounters retain the original AI result, optional source app name, editable context, a short meaning, and a memory hook. Repeated queries can recall a previous saved encounter.
- Local SwiftData persistence, recoverable deletion, versioned `.glossawords` JSON backup export, and validated merge import. AI memory notes are generated only by an explicit action and reviewed before saving.
- An opt-in private CloudKit configuration, sync activity/error display, and restart-based sync switching. The ordinary local build has no iCloud entitlement; real synchronization requires a provisioned build and two-device validation.
- Collapsible language flows with individual prompts, provider selection, optional model overrides, and offline prompt previews. Source-language matching uses macOS Natural Language on demand; the result panel supports manual flow selection.
- A standard Xcode project, Swift 6 checks, a small Swift Testing check, and macOS CI.
- Direct-distribution builds run outside App Sandbox so user-triggered selected-text access can work. Glossa requests Accessibility access only when you choose the permission action; it does not prompt at launch. Xcode disables the configured Hardened Runtime for ad-hoc local builds.
- Zero third-party runtime dependencies, analytics, background polling, or bundled models.

Next milestones:

1. Finish selected-text interaction validation in Chrome webpages and Preview text PDFs: grant Accessibility access manually, then verify direct selection capture, automatic Copy fallback, clipboard restoration, focus, multiple screens, dismissal, and memory. The borderless panel appears at the top-right of the screen containing the reading window without taking keyboard focus on appearance. The pointer's screen is the fallback when the window cannot be read.
2. Validate a real DeepSeek query with a user-supplied key, then measure repeated queries and idle memory. Test other OpenAI-compatible endpoints before claiming support; add other protocols only with an actual provider need.
3. Provision the private iCloud container and signed build, then validate two-device wordbook synchronization, offline edits, account changes, sync on/off, deletion/restore, and backup recovery. Validate the new wordbook UI and live AI note generation separately.

Static dictionaries, OCR, screen capture, lessons, and a local inference engine are outside the product scope.

## Build and run

Requires macOS 14 or newer and Xcode 16 or newer. Open `Glossa.xcodeproj`, select the **Glossa** scheme and **My Mac**, then Run. Look for the Glossa symbol in the menu bar. Use **Settings…** to edit your AI providers, shortcuts, and translation flows, **Type or Paste Text…** to open the lookup panel, and **Quit Glossa** to exit. After granting selected-text access, select text in another app and press Option+A to look it up automatically, or press Option+Shift+A to open manual input with its text field focused.

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

## Additional provider presets

Official documentation reviewed on 2026-09-10. These are text-only Chat Completions presets, **not live-tested integrations**; no paid API requests were made. Existing endpoints, model overrides, flows, and Keychain entries are preserved when missing presets are added. Model IDs remain editable; access depends on the account and region.

| Provider / official reference | Default model | Base URL |
| --- | --- | --- |
| [Gemini](https://ai.google.dev/gemini-api/docs/openai) | `gemini-3.8-flash` | `https://generativelanguage.googleapis.com/v1beta/openai` |
| [Claude](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk) | `claude-haiku-4-5-20251001` | `https://api.anthropic.com/v1` |
| [Qwen](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions) | `qwen3.8-max` | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| [Kimi](https://platform.kimi.ai/docs/api/models-overview) | `kimi-k2.6` | `https://api.moonshot.ai/v1` |
| [Grok](https://docs.x.ai/developers/model-capabilities/legacy/chat-completions) | `grok-4.6` | `https://api.x.ai/v1` |
| [Mistral](https://docs.mistral.ai/api/endpoint/chat) | `mistral-small-latest` | `https://api.mistral.ai/v1` |

Claude uses Anthropic's experimental compatibility layer, not native Messages; Anthropic recommends native integration for production. Use a workspace-scoped key. [Haiku](https://platform.claude.com/docs/en/models/overview) is chosen for response speed, not because it is the newest flagship. Qwen defaults to Beijing's still-supported shared domain; Alibaba recommends replacing it with your region's workspace-specific URL. Kimi uses the international endpoint and defaults to non-thinking K2.6 for dictionary latency; entering `kimi-k3` enables its documented low reasoning effort. Grok uses the still-supported legacy Chat Completions endpoint. No tools, multimodal input, provider SDKs, automatic model discovery, or native provider protocols are added.

## Configure DeepSeek

In **Settings… → AI Providers**, expand DeepSeek and use its defaults: base URL `https://api.deepseek.com`, model `deepseek-v4-flash`. Enter your key in the secure field and click **Save**. Then use **Type or Paste Text… → Look Up**. Glossa sends the assembled prompt only when you initiate a lookup or retry. Saving settings and previewing a prompt do not call an API.

The URL, model, request builder, and SSE decoder are shared with OpenAI-compatible Chat Completions endpoints. OpenAI has its own configuration, initially `https://api.openai.com/v1` with `gpt-4.1-mini`. Use a base URL, not the complete `/chat/completions` path, and choose a supported Chat Completions model. Custom endpoints are labeled in Settings. Keys are scoped to the normalized base URL; changing endpoints does not reuse another endpoint’s key. A saved key appears as a masked password value; focus the field and type to replace it, or use **Delete Key** to remove it for the displayed URL.

DeepSeek and official Kimi K2.6 requests disable thinking for short dictionary responses. Gemini 3.8 Flash and Kimi K3 use low reasoning effort; Qwen 3.8 Max disables thinking on official DashScope/workspace hosts. Other models keep server defaults. The client requests at most 2,048 tokens (reasoning can consume this budget); it limits assembled prompts and output to 64 KiB, SSE events to 64 KiB, and received stream data to 1 MiB. Requests use an ephemeral session, a 30-second inactivity timeout and a 90-second resource timeout, with no automatic retry, disk cache, cookies, or redirects. Completed results may be reused from the five-minute in-memory cache; Retry bypasses it. Truncated or interrupted responses are marked as incomplete.

Defaults and protocol reviewed on 2026-09-08 against the [DeepSeek documentation](https://api-docs.deepseek.com/) and [OpenAI Chat Completions streaming reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events). Compatibility here means streaming Chat Completions with text deltas and `max_tokens`; it does not include Responses, tools, images, or every model-specific option.

## Translation flows

**Settings… → Translation Flows** replaces the global Prompt settings. Each expandable item owns a source language, response language, provider, optional model override, and separate **Dictionary** and **Translation** prompts. Dictionary mode provides pronunciation, meanings, examples, and useful collocations. Translation mode requests only a complete, idiomatic translation, preserving paragraph breaks and citation markers; the original remains visible at the top of the panel. Only the chosen prompt is sent.

The panel's **Mode** picker defaults to automatic local classification, independently of the language **Flow** picker. Text with at least 80 characters, a line break, or strong sentence punctuation uses Translation. Otherwise, native Natural Language tokenization routes six or more words, multiple sentences, or multiword input ending in a period to Translation; shorter input uses Dictionary. These are heuristics, not a grammar classifier: ambiguous short phrases can be corrected with the Mode picker. A manual choice applies only to the current query, survives Retry and Flow changes, and resets on a new lookup or dismissal. Classification makes no AI request. Settings previews use the same mode selection and prompt assembly as lookups.

On startup, unmodified older built-in prompts (including the mixed dictionary/translation versions) upgrade to the dictionary-only default. Existing custom prompts remain the Dictionary prompt. Older saved flows without a Translation prompt use the new built-in translation default; both prompts can be edited separately.

Use `{{text}}`, `{{sourceLanguage}}`, and `{{targetLanguage}}` in prompts. Glossa includes the selected source/response language instructions in every assembled prompt and substitutes user text last, keeping placeholder-like input literal. Previews show the complete prompt without contacting a provider. A blank model override inherits the provider’s default; switching providers clears the override. Provider changes require **Save**; flow edits save automatically. Deleting a flow requires confirmation and keeps provider settings and keys.

On a lookup, a confident local language detection selects a unique flow for that source. A unique **Auto-detect** source flow handles unmatched or uncertain text. Multiple matching flows, multiple fallback flows, or no applicable flow require a choice in the result panel before any request is sent. With no flows, the panel directs you to Settings. The panel’s flow picker can also override an automatic match; choosing another flow cancels the previous query and starts a new one. Manual choices apply to the current lookup and reset for new text. Short words and mixed-language selections can be misidentified, so manual correction remains available.

Existing configuration and prompt migrate to one Auto-detect → Simplified Chinese flow, preserving the endpoint, model, custom prompt, and URL-scoped Keychain entry. Other legacy OpenAI-compatible URLs remain editable and are marked as custom endpoints. Unreadable saved settings are retained and reported, with editing and lookup blocked rather than overwriting them with defaults. These preferences stay local and are excluded from wordbook sync and backups.

The UI uses native grouped forms, disclosure controls, and settings panes, following Apple’s [Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings) and [disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls). Language detection uses [NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer). The OpenAI default is documented as supporting Chat Completions in the [GPT-4.1 mini reference](https://developers.openai.com/api/docs/models/gpt-4.1-mini); live compatibility has not been exercised here.

## Wordbook

After a lookup finishes successfully, click its bookmark button. **Open Wordbook**, or **Wordbook…** in the menu bar (Command+B), opens the native split window: searchable words on the left, dated encounters on the right. Repeated clicks cannot save the same visible result twice; a later lookup can be saved as a new encounter. Grouping uses the source language and Unicode-normalized text, preserving accents and case to avoid merging distinct words. A subsequent query recalls the latest saved encounter for that text and source language.

**Add Context & AI Note…** opens a draft editor. Context is optional and entered by the user: selected-text capture does not read the surrounding sentence. **Create AI Note** sends the word, entered context, and up to 8,000 characters of its original AI result to the provider/model from the selected flow. It uses a compact built-in JSON note prompt and the encounter's saved response language, rather than the flow's lookup prompt. This action may incur API charges. The generated one-sentence meaning and memory hook remain editable; **Save** commits the draft, and cancellation or a failed generation preserves the saved encounter. Edits compare the original local revision before saving and report concurrent changes rather than overwriting them silently.

The sidebar's **Import and Export** menu exports all records, including deletion markers, to a `.glossawords` file. The file is readable JSON, not encrypted by Glossa, and can be saved in iCloud Drive using the standard save panel. It contains `formatVersion: 1`, `exportedAt`, and `entries`; dates are numeric seconds since 2001-01-01 00:00:00 UTC (Foundation's reference date), preserving subsecond revisions. Records contain stable UUIDs, source/response language codes, original result, optional source app, context, meaning, memory hook, creation/update timestamps, and optional deletion timestamp. Credentials, endpoints, models, prompts, shortcuts, and other settings are not exported.

Import supports this versioned format (also with a `.json` extension), previews the record/deletion count, then merges once confirmed. New UUIDs are added; newer revisions of existing UUIDs replace older ones; identical/older revisions are skipped. Different content with identical revision timestamps aborts the import. Files are fully decoded and validated before one database save; rollback preserves prior data if saving fails. Invalid files, duplicate IDs, unsupported versions, files above 32 MiB, and backups above 50,000 records are rejected. Export applies the same size/count limits so exported files remain importable. There is no destructive replace-all import or general-purpose CSV import.

Deletion moves an encounter to **Recently Deleted**, retaining a timestamped marker; restore creates a newer revision. These records currently have no automatic expiry or permanent-delete action. An old backup cannot resurrect a newer deletion marker; recovery is explicit through **Restore**. Backups include these retained records.

The database lives at `~/Library/Application Support/Glossa/Wordbook.store` (plus SQLite sidecars). SwiftData initializes on the first wordbook action, or on a user lookup when a store already exists / sync is enabled. Database and backup encoding work run off the main actor. Once opened, the process retains the container and an in-memory text snapshot; search/grouping currently scan that snapshot. No memory budget or reduction is claimed for this feature. Storage failures keep the database intact, surface an error, and disable writes; Glossa never substitutes an empty store.

### Optional iCloud build

The default entitlement file remains empty so local, ad-hoc builds work without an Apple Developer account. To prepare a sync-capable build, register the app ID with iCloud/CloudKit and Push Notifications, create/associate its container, and use a matching provisioning profile. Put personal configuration only in ignored `Config/Local.xcconfig`, using the placeholders in `Config/Local.xcconfig.example`: `GLOSSA_CODE_SIGN_ENTITLEMENTS`, `GLOSSA_ICLOUD_CONTAINER`, `GLOSSA_ICLOUD_ENVIRONMENT`, and `GLOSSA_APS_ENVIRONMENT`. The optional entitlement file is `Glossa/Glossa-iCloud.entitlements`; the container must exist in the selected team's account. Deploy the CloudKit schema before production distribution. This change does not provision an account/container or publish a schema.

In **Sync & Backups**, enabling iCloud requires confirmation that saved text, notes, source app names, and deletions will sync. Glossa checks its actual signed entitlements before opening a private CloudKit store; an unentitled build explains why the toggle is unavailable. Sync changes take effect after quitting and reopening the app. Both configurations use the same on-disk store, retaining local records without copying between independent databases. Turning sync off does not delete the cloud copy, and the old setting remains active until restart. If an enabled preference is opened in an unentitled build, that same database is opened locally with an explicit warning; the preference is retained. A failed store initialization never causes a fallback to a new empty database.

CloudKit/Core Data events refresh the wordbook and report activity/failures without polling. “iCloud activity completed” reports an observed system sync event, not proof that every other device has received all changes. Simultaneous offline edits to the same record use the system's sync conflict resolution; the timestamp merge rule above applies to Glossa's imports. The payload is stored as one atomic attribute so a note's fields and revision travel together. The integration and account-transition behavior still need real signed, two-device validation.

Verification for this change: the universal Release app build succeeds with `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` for local ad-hoc signing. Offline checks for backup round trips, duplicate/version rejection, merge/deletion behavior, persistence, and AI note parsing were added, but not run in this task. After a reported sidebar layout issue, segmented pickers hide their redundant visual labels while retaining accessibility names. Isolated offscreen renders with empty/saved data at 960- and 760-point window widths confirm the compact header layout; light/dark renders were produced, but native vibrancy/selection colors still require live verification. The renderer uses an isolated database and preferences, never the personal wordbook or an AI API. Interactive UI inspection timed out. macOS 14 runtime behavior, live AI requests, CloudKit sync, and Release memory measurements remain unverified.

## Design constraints

**Small at rest.** Keep the idle process event-driven. Create the network session, result UI, and wordbook storage only when needed. Bound response sizes and caches, cancel superseded work, and keep heavy parsing away from the main actor. Use native text rendering for the supported Markdown subset; arbitrary HTML/CSS is not part of prompt-controlled layout.

**Measure before promising a number.** Native SwiftUI alone does not guarantee memory below 100 MB. Measure Release builds outside the debugger on named hardware/OS versions: fresh launch, 60 seconds idle, repeated lookups, opening the wordbook, and after closing each window. Track physical footprint, idle CPU/wakeups, and whether memory settles after repeated use. A bootstrap baseline does not predict the finished dictionary's footprint.

Bootstrap observation (2026-09-08): on an M3 Pro MacBook Pro with 36 GB RAM, macOS 27 beta (`26A5406e`), built with Xcode 27 beta, the Release process after more than 60 seconds idle showed **17.2 MB physical footprint** (`vmmap -summary`, peak 17.6 MB) and a **0.0% CPU snapshot** (`ps`). This single launch had no query or wordbook workload. Debug tests and the arm64/x86_64 Release build passed locally; automated native UI inspection timed out, so settings/menu interaction still needs a manual check. macOS 14 runtime compatibility has not been exercised locally.

**Cross-app selection needs explicit system permission.** The app is intended for distribution outside the Mac App Store. Apple lists assistive Accessibility API usage among [features incompatible with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), so the approved direct-distribution configuration disables App Sandbox. This does not grant Accessibility access, disable macOS system protections, or replace Developer ID signing/notarization. Validate a signed build with permission denial and unsupported apps before claiming Chrome/Preview support.

Selection capture first checks the focused Accessibility element and up to six ancestors. If no readable selection is exposed, Glossa sends a Copy command, accepts only a fresh clipboard revision, and attempts to restore the complete previous clipboard without overwriting a newer revision. Secure input and secure text fields stop capture. Superseded or dismissed reads cannot update the panel. Mouse monitors and the temporary Escape shortcut exist only while the panel is visible; closing it releases its content.

Current verification (2026-09-09): the Debug build and all 12 Swift Testing checks pass, with no skipped tests, and the universal Release build succeeds using command-line ad-hoc signing overrides because the current personal development certificate is unavailable. Tests cover settings migration/reloading, language routing and ambiguity, per-flow prompt/model request preparation, manual switching, empty/corrupt settings, request validation, bounded SSE decoding, Keychain isolation/update/deletion, offline URLSession transport, and stale-result rejection. They never contact paid APIs. Light/dark offscreen renders of the native Settings content were inspected; interactive native UI automation still times out. Keyboard/VoiceOver interaction, live provider queries, Chrome/Preview capture, flow-menu dismissal behavior, and repeated-open memory measurements remain manual acceptance checks. The bootstrap Release memory observation above does not describe this version.

**Sync is not backup.** SwiftData with private CloudKit is integrated as an optional, provisioned configuration; real sync validation remains pending. The model uses defaults and no uniqueness constraints. Deletions also sync, so versioned export/import and explicit restoration are separate recovery paths. See [Apple's SwiftData sync guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

## Privacy and secrets

AI provider configurations, translation flows and their prompts, and your shortcuts are persisted in this Mac’s app preferences. A lookup sends your input and assembled prompt to the configured provider over HTTPS; provider retention policies apply. Unsaved query text and responses are not persisted to disk; completed results can remain in the lookup cache for up to five minutes and disappear when the app quits. Explicitly bookmarked results, source app names (when available), and wordbook notes are persisted locally and can be synced/exported as described above. Creating an AI memory note sends only the chosen encounter's word, context, language codes, and bounded original result; it does not send the entire wordbook. The visible query is cleared on dismissal. The clipboard is read only when you explicitly paste or trigger the selected-text Copy fallback. Do not put credentials or sensitive source text in prompts or notes.

API credentials live in macOS Keychain, without Keychain synchronization. They are never stored in `UserDefaults`, prompts, `.xcconfig`, source code, app resources, or wordbook/iCloud records. Direct-distribution builds run outside App Sandbox; API requests still require HTTPS. Requests exist only during an explicit lookup or AI note generation and are cancelled when superseded, stopped, or dismissed; HTTP errors are shown without echoing raw provider bodies or credentials.

`.gitignore` excludes `.env` variants (except a placeholder-only `.env.example`), local signing overrides, certificates/private keys, Xcode user state, databases, and build/profiling output. Ignoring a file does not remove it from Git history. Review staged changes before every push. Never paste keys, private prompts, or selected text into logs or public issues. If a credential is exposed, revoke it first.

## Contributing and skills

See [CONTRIBUTING.md](CONTRIBUTING.md) for checks, conventions, and the recommended SwiftUI skill. [AGENTS.md](AGENTS.md) records the product boundaries for coding agents.

## License

[MIT](LICENSE).

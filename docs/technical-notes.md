# Glossa technical notes

[README](../README.md) · [简体中文](../README.zh-CN.md)

This document holds implementation details and validation notes that would otherwise turn the project landing page into a changelog. It describes the current source tree, not a promise that every external integration has been exercised.

## Runtime and window behavior

Glossa is a native SwiftUI menu bar app with no launch window. Its Dock icon appears while Settings, the lookup panel, or the wordbook is open and hides after the final window closes. The menu bar itself does not count as an open window.

Selected-text lookup defaults to Option+A; manual input defaults to Option+Shift+A. Both shortcuts are configurable and report registration conflicts. The lookup panel is borderless and appears at the top-right of the screen containing the reading window, with the pointer's screen as a fallback. It supports streaming output, stop, retry, flow and mode overrides, Escape or outside-click dismissal, and replacement of a previous result.

Input is limited to 2,000 Swift characters without silently truncating oversized selections. Assembled prompts and output are limited to 64 KiB, individual SSE events to 64 KiB, and received stream data to 1 MiB. The client asks for at most 2,048 tokens and uses an ephemeral `URLSession`, a 30-second inactivity timeout, a 90-second resource timeout, no cookies, no redirects, and no automatic retry. Completed results may stay in a 16-entry, five-minute in-memory cache; Retry bypasses it.

## Selected-text access

Selected-text access is always user-triggered. Glossa first checks the focused Accessibility element and up to six ancestors. If no readable selection is exposed, it sends Copy, accepts only a fresh pasteboard revision, and attempts to restore the complete previous pasteboard without overwriting a newer revision. Secure input and secure text fields stop capture. Dismissed or superseded reads cannot update the panel.

Direct-distribution builds run outside App Sandbox because cross-app Accessibility APIs are incompatible with it. This does not grant Accessibility access or replace Developer ID signing and notarization. Glossa asks for permission only when the user chooses the permission action, never at launch.

## Providers and transport

Each provider has an editable base URL and default model. Credentials are scoped to the normalized base URL and stored in macOS Keychain without Keychain synchronization. The app currently includes documentation-reviewed presets for DeepSeek, OpenAI, Gemini, Claude (experimental compatibility layer), Qwen, Kimi, Grok, and Mistral.

The shared transport implements text-only, streaming, OpenAI-compatible Chat Completions with `max_tokens`. It does not implement Responses, tools, images, automatic model discovery, provider SDKs, or every provider-specific option. Presets and model defaults still require live account and region validation.

Requests are HTTPS-only. Redirects are rejected so a prompt or credential cannot be forwarded to another host. Provider error bodies are not echoed into the UI. A request exists only during a user-initiated lookup, retry, or AI-note generation and is cancelled when superseded, stopped, or dismissed.

## Translation flows

Each flow owns a source language, response language, provider, optional model override, and separate Dictionary and Translation prompts. Prompts support `{{text}}`, `{{sourceLanguage}}`, and `{{targetLanguage}}`. Language instructions are added before user text is substituted, keeping placeholder-like user input literal. Offline previews assemble the same prompt without contacting a provider.

Source-language selection uses `NLLanguageRecognizer` on demand. A unique matching flow is chosen automatically; one unique Auto-detect flow handles unmatched or uncertain text. Ambiguous or missing matches require a manual choice before any request is sent.

Mode classification is local and heuristic. Text of at least 80 characters, a line break, or strong sentence punctuation uses Translation. Otherwise, native tokenization routes six or more words, multiple sentences, or multiword input ending in a period to Translation; shorter input uses Dictionary. A manual override applies only to the current query.

## Wordbook and backups

The wordbook uses SwiftData and opens lazily. Saved encounters retain the source and response language, original AI result, optional source app, context, short meaning, memory hook, and timestamps. Search and grouping currently scan an in-memory snapshot after the store has opened. Storage failures are surfaced and disable writes; the app does not replace a failed store with an empty one.

AI memory notes are generated only after an explicit action. The request contains the saved word, user-entered context, language information, and a bounded copy of the original result. The generated meaning and memory hook remain editable before saving, and concurrent local edits are detected instead of silently overwritten.

Exports use a versioned, readable `.glossawords` JSON format. Import fully decodes and validates a file before one database save, then merges by stable UUID and revision timestamp. Invalid files, duplicate IDs, equal-timestamp conflicts, unsupported versions, files over 32 MiB, and backups over 50,000 records are rejected. Deletion creates a recoverable timestamped marker, preventing an older backup from resurrecting a newer deletion.

The default database lives at `~/Library/Application Support/Glossa/Wordbook.store`. Backups are not encrypted by Glossa and can include selected text, AI results, source app names, context, and notes. Credentials, endpoints, models, prompts, and shortcuts are excluded.

## Optional iCloud build

The normal entitlement file is empty so local ad-hoc builds work without a paid developer account. A sync-capable build needs an App ID with iCloud/CloudKit and Push Notifications, an existing container, a matching provisioning profile, and the optional `Glossa/Glossa-iCloud.entitlements` file. Personal values belong in the ignored `Config/Local.xcconfig`; placeholders are documented in `Config/Local.xcconfig.example`.

Sync is opt-in and uses the user's private CloudKit database. Enabling it requires confirmation and a restart. CloudKit/Core Data events refresh the wordbook without polling and surface activity or failures. An observed completed event is not proof that every device has received every record. Real two-device sync, offline edits, account transitions, deletion and restore, and backup recovery remain unvalidated.

Sync is not a backup: deletions synchronize too. The separate import/export format is the recovery path.

## Privacy and storage

Provider settings, translation flows, prompts, and shortcuts live in local app preferences. API credentials live only in Keychain. Unsaved query text and responses are not written to disk, though completed results may remain in memory for up to five minutes. Explicitly bookmarked results and notes are persisted locally and may be synced or exported when the user enables those actions.

The project includes no third-party runtime dependencies, analytics, background polling, static dictionaries, OCR, screen capture, lessons, embedded result browser, bundled models, or local inference runtime.

## Build, signing, and validation

The deployment target is macOS 14. A standard offline check is:

```sh
xcodebuild test -project Glossa.xcodeproj -scheme Glossa \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData

xcodebuild build -project Glossa.xcodeproj -scheme Glossa \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData
```

Local builds use ad-hoc signing unless `Config/Local.xcconfig` supplies personal settings. Distribution requires Developer ID signing and notarization.

A bootstrap Release measurement made before the current feature set showed a 17.2 MB physical footprint after more than 60 seconds idle on an M3 Pro MacBook Pro with 36 GB RAM and macOS 27 beta. It is not a current memory claim. Measure the current Release build outside the debugger at idle, during repeated lookups, with the wordbook open, and after closing windows before publishing a memory budget.

Current validation gaps include live provider requests, representative Chrome and Preview selection capture, keyboard and VoiceOver interaction, signed two-device CloudKit behavior, macOS 14 runtime behavior, and current Release memory measurements.

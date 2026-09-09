# Glossa

## Product boundaries

Build a quiet, AI-only macOS dictionary in native SwiftUI. The intended flow is selected text → global shortcut → top-right result panel. Users control the prompt, response language, and supported Markdown layout. A personal wordbook with optional iCloud sync is the other core feature.

Exclude static dictionaries, OCR/screen capture, lessons, embedded browsers for result rendering, and local model runtimes. Keep idle work event-driven and runtime dependencies minimal. Measure Release memory before claiming an improvement or a fixed budget.

## Working conventions

- Read the current implementation before choosing structure. Prefer native APIs and small concrete types; add a service only with its first working caller.
- For SwiftUI changes, use `swiftui-expert-skill` when installed; see `CONTRIBUTING.md` for its source and reviewed revision. Verify macOS API availability against the deployment target.
- Keep credentials in Keychain when provider support is added. Persist only nonsecret preferences in `UserDefaults`; keep credentials out of prompts, app resources, logs, and sync records.
- Keep captured text access user-triggered. Implement and test Accessibility/distribution constraints before enabling cross-app selection.
- For wordbook storage or iCloud changes, read the sync constraints in `README.md`. Surface persistence failures without replacing a failed store with an empty one.
- For build/signing changes, use ignored `Config/Local.xcconfig` for personal settings. Commit only placeholder configuration.
- For code changes, finish when the relevant README build command succeeds. Run tests and UI acceptance only when the user explicitly requests them; never contact paid AI APIs in automated tests.

The README distinguishes implemented behavior from planned features; update it when that boundary moves.

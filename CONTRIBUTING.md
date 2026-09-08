# Contributing to Glossa

Glossa is deliberately small. Start with the current code and use SwiftUI, Foundation, and macOS APIs before adding a dependency. Propose new product features in an issue before expanding the dictionary's scope.

## Development

Use the build/test commands in [README.md](README.md). The shared **Glossa** scheme supports Run, Test, Profile, and Archive. CI runs the Debug tests and a universal Release build; signed release distribution is not configured yet.

Keep changes focused. Add a small runnable check for nontrivial logic, and manually exercise changed UI with keyboard navigation, light/dark appearance, and VoiceOver labels. Use Release builds outside the debugger for performance measurements. Verify minimum supported macOS versions before claiming support for a new API.

The initial app has only a menu bar scene and a settings scene. Prompt data uses `@AppStorage`; transient preview input uses `@State`. Add services and storage when implementing the features that use them, rather than introducing an unused service layer.

Before a pull request:

```sh
git diff --check
git diff --cached
```

Run the Xcode checks, and include what was verified and any remaining limitations. Use placeholder-only fixtures. Do not attach personal databases, API responses, credentials, signing files, or logs containing user selections. To report a security issue, use GitHub's private vulnerability reporting if available; otherwise ask the maintainer for a private channel without posting the exploit or sensitive data publicly.

## Recommended agent skill

[SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill) by Antoine van der Lee and contributors covers state ownership, macOS scenes, accessibility, and performance. It is a development aid, not an app dependency. Its [skills.sh listing](https://skills.sh/avdlee/swiftui-agent-skill/swiftui-expert-skill) provides an installer:

```sh
npx skills add https://github.com/AvdLee/SwiftUI-Agent-Skill --skill swiftui-expert-skill -g
```

The bootstrap used revision `4c6a97d15aa5e023538c3cb06b5192f241dd451d`, path `skills/swiftui-expert-skill`. The command above follows upstream and may install a newer version; review updates before use. To reproduce the bootstrap guidance, use the skill folder from that exact revision in your agent's user-level skill directory.

Consult the skill's `SKILL.md`, `references/latest-apis.md`, and the references relevant to the change. macOS availability and measured behavior take precedence over examples aimed at iOS. Glossa's product scope remains authoritative.

Keep personal skill installations outside the repository. The app builds and tests without any agent tool installed.

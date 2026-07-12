# Anchored

[![Clean Build & Test](https://github.com/Varun-Chinthoju/Anchored/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Varun-Chinthoju/Anchored/actions/workflows/ci.yml)

Anchored is a macOS menu-bar app that notices when your work context drifts and adds a gentle, reversible prompt to help you return.

> **Stability: experimental.** The V1 focus workflow is usable for testing, but browser, visual, and AI-assisted classification remain actively developed. See [known limitations](#known-limitations) before relying on it all day.

## What it does

- **Passive focus detection:** watches app switching and optional browser context, then prompts after sustained work rather than making you start a timer.
- **Profiles and gentle enforcement:** configure app/domain rules, switch profiles from the menu bar, and use a countdown pill plus click-through dimming overlay during an active session.
- **Local history:** records session events locally in SQLite and presents an on-device dashboard.

## Install or build

There is not yet a signed public download. Build from source on macOS 13 or later with Xcode 14+ and XcodeGen:

```bash
git clone https://github.com/Varun-Chinthoju/Anchored.git
cd Anchored
xcodegen generate
xcodebuild -project Anchored.xcodeproj -scheme Anchored -configuration Release -destination 'platform=macOS' build
```

For development and the CI-equivalent test command:

```bash
xcodegen generate
xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

The release process, including installation testing, signing, notarization, and GitHub Releases, is tracked in [the release checklist](docs/release-checklist.md).

## Privacy

Anchored’s default configuration is local-only: focus rules, session events, and the optional context-history database stay on your Mac. It has no telemetry or account sync.

| Data or capability | Default | Storage / recipient | Control |
| --- | --- | --- | --- |
| App bundle ID and session events | On | Local SQLite database | Local history can be cleared in Privacy & Data |
| Browser URL and window title | Only when browser context is available | Used locally; sanitized before optional history storage | macOS Accessibility permission and context-history toggle |
| Screen capture / OCR / visual check | On-device feature may be enabled | Not persisted by Anchored | Disable **AI Visual Productivity Check** in Settings |
| Cloud classification | **Off** | When enabled, app name, title, URL, and any OCR text used for the request are sent to the provider you select (Gemini, OpenAI, or Anthropic) | Disable **Cloud AI classification** in Settings |
| API keys | N/A | macOS Keychain, device-only while unlocked | Remove or replace them in Settings |

Cloud analysis is opt-in. Turning it off prevents new cloud-classification requests; local deterministic rules continue to work. Screenshots are used only in memory for on-device OCR/visual analysis and are not persisted by Anchored. When detailed context history is enabled, its retention period is configurable in Privacy & Data (1–365 days); it is disabled by default.

## Classification policy

Focus decisions are deterministic before they are “smart.” The first matching rule wins:

1. Explicit allowed-domain rules
2. Explicit blocked-domain rules
3. Browser-content heuristics and local browser classifiers
4. Profile app allow/block rules and local app classifiers
5. Optional on-device visual result, only for an otherwise neutral context
6. Optional cloud result, only for the same still-current neutral context
7. Neutral fallback

An asynchronous visual or cloud result never overrides an explicit rule, never applies after the active context changes, and never starts dimming on its own. It can only promote a still-current neutral context to focus, preventing flicker and contradictory enforcement.

## V1 scope

The stable core is deliberately small:

- passive focus detection
- app and domain rules
- countdown pill and click-through dimming overlay
- local session history
- profile switching

AI-assisted app, browser, visual, OCR, and cloud classification are experimental aids around that core—not requirements for it.

## Known limitations

- Browser context availability depends on Accessibility and browser automation permissions; a browser with no readable active tab resolves safely without blocking the app.
- No signed/notarized release artifact is published yet; build from source only if you are comfortable with an experimental app.
- Visual and cloud classifiers are optional and can be slower or less reliable than explicit app/domain rules.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), and the [architecture map](docs/architecture/anchored-architecture.md). Report bugs and propose features through the included GitHub templates. The repository uses the PolyForm Noncommercial 1.0.0 license; see [LICENSE](LICENSE).

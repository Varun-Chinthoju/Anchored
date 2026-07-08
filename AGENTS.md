# Repository Guidelines

## Project Structure & Module Organization

Anchored is a Swift 5.7/macOS 13 menu-bar application generated with XcodeGen. Application code lives in `Anchored/`:

- `App/` and `MenuBar/`: lifecycle, windows, SwiftUI views, and status-menu UI.
- `Engine/`: `FocusEngine`, activity monitoring, browser strategies, and matching logic.
- `Models/`: sessions, events, profiles, and context value types.
- `Storage/`: GRDB/SQLite persistence, preferences, and dashboard queries.
- `Onboarding/`, `Overlay/`, `Audio/`, and `Resources/`: supporting UI and bundled assets.

Tests mirror these domains under `AnchoredTests/`. Product specifications and plans live in `docs/ideas/`. Update `project.yml` when targets, dependencies, or source layout change; `Anchored.xcodeproj` is generated and ignored.

## Build, Test, and Development Commands

```bash
xcodegen generate
xcodebuild -project Anchored.xcodeproj -scheme Anchored -destination 'platform=macOS' build
xcodebuild test -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open Anchored.xcodeproj
```

Generate the project before building. The final command opens Xcode for local running and debugging with the `Anchored` scheme.

When validating the app manually, prefer a release build workflow: build `Anchored` with `-configuration Release`, copy the resulting `Anchored.app` into `/Applications`, and open that installed app instead of only running from DerivedData or Xcode.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift API naming: `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and descriptive enum cases. Prefer small value types, dependency injection, and `[weak self]` in escaping closures. Keep AppKit/UI mutation on the main thread and persistence work off it. No formatter or linter is configured, so follow the surrounding file and avoid unrelated formatting changes.

Treat `FocusEngine` state transitions and the ten-session Accessibility permission gate as architectural invariants. Register browser support through `BrowserStrategyFactory`; keep SQL in `SQLiteSessionStore.swift` or `DashboardQueries.swift`.

## Testing Guidelines

Tests use XCTest. Name files `TypeNameTests.swift` and methods `testBehaviorUnderCondition()`. Add unit coverage for state transitions, URL matching, browser parsing, persistence migrations, and preference changes. Use isolated `UserDefaults` suites and temporary databases; never mutate shared production singletons or rely on arbitrary sleeps. For manual app testing, always prefer a release build, install the built app into `/Applications`, and open that installed copy. Run the full suite before submitting changes.

## Commit & Pull Request Guidelines

Recent history uses concise Conventional Commit prefixes such as `feat:`, `fix:`, `refactor:`, and `chore:`. Keep each commit focused and imperative. Pull requests should explain behavior and architectural impact, link relevant issues/specs, list exact verification commands, and include screenshots or recordings for UI changes. Update `project.yml` for added files and confirm generation, build, and tests succeed.

## Security & Privacy

Never commit secrets, local databases, DerivedData, or generated Xcode projects. Window titles and browser URLs are sensitive: keep processing local, avoid raw-value logging, and preserve permission checks and graceful fallbacks.

## Architecture Doc And Agent Workflow

Start repo orientation with [docs/architecture/anchored-architecture.md](/Users/varun/Development/Anchor/docs/architecture/anchored-architecture.md). It is the canonical map of runtime flows, key modules, storage boundaries, invariants, and the V2.6 impact surface.

For every major update, read and follow [docs/skills/anchored-architecture-maintainer/SKILL.md](/Users/varun/Development/Anchor/docs/skills/anchored-architecture-maintainer/SKILL.md) before finishing the task. A major update includes any change that alters architecture, runtime composition, engine behavior, persistence shape, permissions/privacy flow, module ownership, or the implementation plan in `docs/ideas/anchored-v2.6-plan.md`.

Major updates are not complete until the architecture doc is updated to reflect the shipped code and any still-open gaps.

# Anchored context-pack instructions

Treat this as a read-only context pack for the Anchored macOS application.

## Repository orientation

- Read `AGENTS.md` and `docs/architecture/anchored-architecture.md` first.
- Historical product plans are archived outside the repository in `/private/tmp/anchored-plans-external/`.
- The runtime composition root is `Anchored/App/AppDelegate.swift`.
- Focus classification and enforcement live in `Anchored/Engine/FocusEngine.swift`.
- Persistence boundaries are `Anchored/Storage/SQLiteSessionStore.swift`, `Anchored/Storage/SessionStore.swift`, and the context-history stores.
- The Xcode project is generated from `project.yml`; do not edit `Anchored.xcodeproj` directly.

## Reasoning constraints

- Preserve the FocusEngine state invariants and the ten-session Accessibility permission gate.
- Keep window titles and browser URLs local and sanitized; do not suggest raw-value logging.
- Keep AppKit and SwiftUI mutations on the main thread and persistence work off it.
- Preserve unrelated working-tree changes when proposing or applying a patch.
- For behavior changes, trace the runtime path before recommending a dashboard-only fix.

When proposing changes, name the exact files, explain architectural impact, and include focused XCTest coverage plus the relevant XcodeGen/build/test commands.

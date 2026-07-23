# Anchored Test Matrix

This matrix is the working map for Anchored verification. It ties the product journeys and architectural invariants to the test layer that should prove them, so coverage gaps are obvious and repeatable.

Status legend:

- `Yes` means the behavior is already intended to be covered by automated tests.
- `Partial` means some of the behavior is automated, but the full journey still needs manual or smoke coverage.
- `No` means the behavior still needs a dedicated automated path.

## Critical Journeys

| Area | Scenario | Test layer | Expected result | Automated | Last verified | Primary coverage |
|---|---|---|---|---|---|---|
| Journey A | Automatic focus session starts only after the threshold and corroborating positive signals | Engine integration | Session starts once, uses `automaticSessionDuration`, and stores one session-start event | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey A | Switching between productive apps during the threshold | Engine integration | Work streak continues and stale threshold callbacks do not start a duplicate session | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey A | Changing profile, disabling automation, or stopping the engine while the threshold is pending | Engine integration | Pending automatic start is invalidated and no stale callback can anchor a session | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey A | Sleep or lock during the threshold | Engine integration | Focus time does not advance and the threshold does not fire early | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey A | Session end cleanup | Engine integration | Timers, overlays, and session state are all torn down once | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Overlay/OverlayManagerTests.swift` |
| Journey B | Distraction countdown starts from an anchored session | Engine + UI coordinator | Countdown is scheduled exactly once and the pill appears when enabled | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Overlay/OverlayManagerTests.swift` |
| Journey B | Return to work before countdown expiry | Engine integration | Countdown is canceled, the pill disappears, and stale callbacks are harmless | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/FocusEngineHarnessTests.swift`, `AnchoredTests/Overlay/OverlayManagerTests.swift` |
| Journey B | Countdown expires after returning to work | Engine integration | Old countdown callback does not dim a newer context | Yes | CI | `AnchoredTests/Engine/FocusEngineHarnessTests.swift`, `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey B | Countdown expires while still distracted | UI coordinator | Exactly one dim overlay is shown and the dim-center sequence follows the configured phase timing | Partial | CI | `AnchoredTests/Overlay/OverlayManagerTests.swift`, `AnchoredTests/Overlay/DimOverlayWindowTests.swift`, `AnchoredTests/Overlay/DimCenterPanelTests.swift` |
| Journey B | Return to work from the dim state | UI coordinator + engine | Enforcement surfaces disappear and the focus session resumes if appropriate | Partial | CI | `AnchoredTests/Overlay/OverlayManagerTests.swift`, `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey C | Mixed-use website correction stays page-scoped | Resolver + menu bar | The current snapshotted context is corrected without silently promoting the whole domain | Yes | CI | `AnchoredTests/Engine/ClassificationResolverTests.swift`, `AnchoredTests/App/AppDelegateTests.swift` |
| Journey C | Repeated page corrections on the same mixed-use site | Storage + resolver | Confidence increases only for the matching page/category/intent bucket | Yes | CI | `AnchoredTests/Storage/ContextualLearningStoreTests.swift`, `AnchoredTests/Engine/ClassificationResolverTests.swift` |
| Journey C | Website-wide approval is chosen explicitly | UI coordinator | A permanent domain rule is created only after explicit user choice | Partial | CI | `AnchoredTests/App/AppDelegateTests.swift`, `AnchoredTests/Engine/ClassificationResolverTests.swift` |
| Journey C | Another page on the same domain is not auto-allowed | Resolver | The rule remains contextual by default and does not spread across unrelated pages | Yes | CI | `AnchoredTests/Engine/ClassificationResolverTests.swift` |
| Journey D | Normal break request before 30 minutes of net focus | Engine integration | Break request is rejected unless policy permits it | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/BreakReviewCheckerTests.swift` |
| Journey D | Bypassed break from the dim overlay | Engine integration | Session enters break state and accounting pauses | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey D | Return to work after leaving and coming back | Engine integration | Only the newest 15-second grace timer can resume the session | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey D | Old break callback fires after manual resume | Engine integration | The stale callback is ignored and the newer session is unaffected | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey E | Schedule closes during automatic tracking or pending timers | Engine integration | Automatic focus tracking, countdowns, and promotion are suppressed while the schedule is off | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Models/FocusScheduleTests.swift` |
| Journey E | Schedule changes while timers are active | Engine integration | Inappropriate automatic timers are invalidated and no duplicate timers are created | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey E | Wake and unlock happen inside or outside the schedule | Engine integration | Automatic timers only re-arm when the schedule allows them | Partial | CI | `AnchoredTests/Engine/FocusEngineTests.swift` |
| Journey F | Privacy canary is exercised through storage, diagnostics, and cloud paths | Storage + diagnostics + cloud | Credentials, raw URLs, OCR, typed text, and summaries never appear in protected sinks | Yes | CI | `AnchoredTests/Storage/ContextHistoryStoreTests.swift`, `AnchoredTests/Storage/ClassificationFeedbackStoreTests.swift`, `AnchoredTests/Engine/DiagnosticsCenterTests.swift`, `AnchoredTests/Engine/CloudClassifierTests.swift` |
| Journey F | Fresh install with history disabled | Storage integration | No context-history rows are written until opt-in is enabled | Yes | CI | `AnchoredTests/Storage/ContextHistoryStoreTests.swift` |
| Journey F | Re-enabling and clearing history | Storage integration | Sanitized rows appear only after opt-in and clear removes them all | Yes | CI | `AnchoredTests/Storage/ContextHistoryStoreTests.swift`, `AnchoredTests/Storage/SQLiteSessionStoreTests.swift` |
| Journey F | Installed-app smoke flow | Smoke / manual | Release app reaches readiness markers, runs the journey, and exits cleanly | Partial | Release checklist | `docs/release-checklist.md` |

## Invariant Coverage

| Area | Scenario | Test layer | Expected result | Automated | Last verified | Primary coverage |
|---|---|---|---|---|---|---|
| Safety | Stop tears down every enforcement surface | Engine + UI coordinator | No timer, overlay, or session state survives stop | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/FocusEngineHarnessTests.swift`, `AnchoredTests/Overlay/OverlayManagerTests.swift` |
| Safety | Stop invalidates every pending timer | Engine integration | Stale countdown, break, focus-prompt, doomscroll, and expiry callbacks are harmless | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/FocusEngineHarnessTests.swift` |
| Safety | Old session timers cannot affect a new session | Engine integration | Generation and session checks reject stale callbacks | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/FocusEngineHarnessTests.swift` |
| Safety | Preference changes reclassify the live context | Engine integration | Classification-affecting revision changes clear in-flight work and refresh the live state | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/ClassificationCacheTests.swift` |
| Safety | Profile changes reclassify the live context | Engine integration | Profile-scoped cache entries do not cross boundaries | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Storage/ContextualLearningStoreTests.swift` |
| Safety | API-key changes invalidate old classification work | Engine + cloud | Stale cloud results are rejected and reclassification happens against the new revision | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/CloudClassifierTests.swift` |
| Safety | Sleep and lock do not count toward focus or countdown time | Engine integration | Focus accounting pauses cleanly and resumes without drift | Yes | CI | `AnchoredTests/Engine/FocusEngineTests.swift`, `AnchoredTests/Engine/FocusEngineHarnessTests.swift` |
| Safety | Commitments never remove the quit path | UI / release verification | Quit remains available in every visible state, including dimming and onboarding | Partial | Release checklist | `docs/release-checklist.md` |
| Policy | Explicit rules outrank heuristics and optional evidence | Unit tests | Domain and app rules win over heuristic and classifier evidence | Yes | CI | `AnchoredTests/Engine/ClassificationResolverTests.swift` |
| Policy | Mixed-use sites remain contextual by default | Unit tests | Page-level corrections do not become automatic domain allow rules | Yes | CI | `AnchoredTests/Engine/ClassificationResolverTests.swift`, `AnchoredTests/Engine/IntentAwareFocusEngineTests.swift` |
| Policy | Classification cache keys include revision boundaries | Unit tests | Cache hits do not cross profile, session, or configuration changes | Yes | CI | `AnchoredTests/Engine/ClassificationCacheTests.swift` |
| Policy | Browser results are generation-checked | Integration tests | Late browser or context-collection callbacks are discarded as stale | Yes | CI | `AnchoredTests/Engine/ContextCollectorTests.swift`, `AnchoredTests/Engine/AppSwitchMonitorTests.swift` |
| Storage | History opt-in is enforced at the storage boundary | Storage integration | Disabled history writes nothing even if callers try | Yes | CI | `AnchoredTests/Storage/ContextHistoryStoreTests.swift` |
| Storage | URLs and titles are sanitized before persistence | Storage integration | Credentials, query strings, fragments, and unsafe text are removed or normalized | Yes | CI | `AnchoredTests/Engine/ContextSanitizerTests.swift`, `AnchoredTests/Storage/SQLiteSessionStoreTests.swift` |
| Storage | Migration is idempotent | Storage integration | Re-running migration does not duplicate or corrupt records | Yes | CI | `AnchoredTests/Storage/SQLiteMigrationTests.swift` |
| Storage | Dashboard queries ignore stale generations | Storage + UI model | Older query results cannot replace newer dashboard data | Yes | CI | `AnchoredTests/Storage/DashboardQueriesTests.swift`, `AnchoredTests/App/DashboardViewTests.swift` |
| Storage | Feedback and learning data stay profile-aware | Storage integration | Records do not leak across profiles or sessions | Yes | CI | `AnchoredTests/Storage/ContextualLearningStoreTests.swift`, `AnchoredTests/Storage/ClassificationFeedbackStoreTests.swift` |
| UI | Countdown pill preference only changes presentation | UI coordinator | Hiding the pill does not disable enforcement | Yes | CI | `AnchoredTests/Overlay/OverlayManagerTests.swift` |
| UI | Overlay remains click-through | UI coordinator | Dimming never traps input and quit remains reachable | Partial | CI | `AnchoredTests/Overlay/DimOverlayWindowTests.swift`, `AnchoredTests/Overlay/OverlayManagerTests.swift` |
| UI | Activation policy changes are main-thread-safe | App lifecycle | Accessory and regular modes switch only when windows require it | Yes | CI | `AnchoredTests/App/AppDelegateTests.swift` |
| UI | Settings search reaches the actual pane | UI coordinator | Search opens the correct section without breaking the split view | Yes | CI | `AnchoredTests/App/SettingsSearchSupportTests.swift` |
| Diagnostics | Sanitized diagnostics stay bounded and private | Diagnostics | Recent events are copied without raw titles, URLs, OCR, typed text, screenshots, or API keys | Yes | CI | `AnchoredTests/Engine/DiagnosticsCenterTests.swift` |
| Smoke | Installed release app reaches readiness markers | Manual smoke | `startup_ui_ready` and `menu_bar_status_item_ready` appear before interaction begins | Partial | Release checklist | `docs/release-checklist.md` |
| Smoke | Basic overlay and quit path in the installed app | Manual smoke | Countdown, dimming, cleanup, and quit all work in the built `.app` | Partial | Release checklist | `docs/release-checklist.md` |
| Reliability | Long-running soak stays bounded | Soak / stress | Memory, timers, overlays, cache size, and in-flight work remain within limits | No | Pending | Future soak harness |
| Reliability | Randomized state-machine testing | Property-based engine tests | Stale actions are harmless across generated action sequences | No | Pending | Future harness around `FocusEngine` |
| Reliability | Installed smoke mode stays non-accidental | Build / release tooling | Debug smoke settings cannot activate in normal release use | No | Pending | `project.yml`, release workflow, smoke-mode entrypoint |

## Notes For Future Work

- Add a reusable `FocusEngineTestHarness` so the journey rows read like scenarios instead of setup scripts.
- Keep the matrix updated whenever a new timer, overlay surface, or persistence boundary is added.
- If a row only has manual coverage, keep it in the matrix until a real automated test exists and has a stable file path.
- When the architecture changes, update this matrix together with `docs/architecture/anchored-architecture.md`.

# ANCHORED MEGAFILE - All Plans + Specs Consolidated
Generated: 2026-07-09T17:45:50.944264
Source commit: c1b679a + P0 fixes (FocusEngine non-blocking, Gemini header, Keychain mock flag, AppSwitchMonitor 2.5s lifecycle)
Total source files: 19

## Index
- anchored-cloud-byok-classification-plan.md (11506 bytes)
- anchored-cloud-byok-classification-spec.md (4257 bytes)
- anchored-consolidated-plan.md (27017 bytes)
- anchored-dashboard-refresh-audit.md (2805 bytes)
- anchored-dashboard-refresh-plan.md (12236 bytes)
- anchored-dashboard-refresh.md (6968 bytes)
- anchored-ml-engine-plan.md (4986 bytes)
- anchored-v1-plan.md (34061 bytes)
- anchored-v1.md (20591 bytes)
- anchored-v2-plan.md (17231 bytes)
- anchored-v2.5-plan.md (21253 bytes)
- anchored-v2.5.md (14358 bytes)
- anchored-v2.6-async-context-plan.md (14967 bytes)
- anchored-v2.6-async-context-spec.md (4719 bytes)
- anchored-v2.6-plan.md (38459 bytes)
- anchored-v2.6.md (30823 bytes)
- anchored-v2.md (35008 bytes)
- anchored-v3-plan.md (31572 bytes)
- anchored-v3.md (30299 bytes)

---



================================================================================
FILE: anchored-cloud-byok-classification-plan.md
SIZE: 11506
================================================================================

# Implementation Plan: Cloud AI Classification with BYOK

> **Source specification:** [Cloud AI BYOK Classification Spec](./anchored-cloud-byok-classification-spec.md)

## 1. Overview and Planning Decisions

This plan implements cloud-based context classification utilizing Google Gemini, OpenAI, or Anthropic models with Bring Your Own Key (BYOK) configurations. Users will supply their own API keys, which are stored securely in the macOS Keychain. The pipeline operates by sending the app name, window title, URL, and OCR screen text in a structured prompt. Custom API endpoints are supported to allow routing through reverse proxies (like OpenRouter) or local servers. If cloud queries fail or time out, the engine degrades gracefully to local classifiers.

### Decisions Locked for This Plan

- **Secure Key Storage**: API keys are saved directly to Keychain Services (`SecItem` APIs) using a dedicated service name. Plaintext keys are never stored in `UserDefaults`.
- **Text-Only Prompting**: Context queries will consist of app name, window title, URL, and OCR-extracted text. Raw screenshots (images) are not uploaded.
- **Strict Time Limits**: Network requests are allocated a maximum duration of 2.0 seconds via `URLSessionConfiguration`.
- **Custom Endpoints**: Settings will expose editable endpoint text fields initialized with default URLs for each provider.
- **Sequential Fallback**: If the network is unreachable, authorization fails, or a request times out, `FocusEngine` automatically falls back to local classifiers.

### Dependency Graph

```mermaid
graph TD
    A[Task 1: Implement KeychainHelper] --> C[Task 3: Implement CloudClassifier]
    B[Task 2: Extend PreferencesManager Settings] --> C
    C --> D[Task 4: Add Unit Tests with URLProtocol Mocking]
    D --> E[Task 5: Wire CloudClassifier into FocusEngine]
    E --> F[Task 6: Implement Settings UI Panel]
    F --> G[Task 7: Diagnostics & Final Verification]
```

---

## 2. Task List

### Phase 1: Keychain and Storage Configuration

#### Task 1: Implement KeychainHelper for Secure API Key Storage

**Description:** Build a utility class to interact with the macOS Security framework's Keychain Services. This handles setting, retrieving, and deleting API keys for different AI providers without exposing them in plaintext.

**Acceptance criteria:**
- [ ] Implement `KeychainHelper` with functions:
  - `static func saveKey(_ key: String, forProvider provider: String) throws`
  - `static func loadKey(forProvider provider: String) -> String?`
  - `static func deleteKey(forProvider provider: String) throws`
- [ ] Keys must be saved under the service identifier `com.varun.Anchored.cloud-ai`.
- [ ] Use `kSecClassGenericPassword` with account attributes corresponding to the provider name (e.g. `gemini`, `openai`, `anthropic`).

**Verification:**
- [ ] Write unit tests verifying that a key can be saved, read back, updated, and deleted successfully.
- [ ] Confirm no trace of the key is saved inside `UserDefaults.standard` dump.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Storage/KeychainHelper.swift`
- `AnchoredTests/Storage/KeychainHelperTests.swift`

**Estimated scope:** S

---

#### Task 2: Extend PreferencesManager with Cloud AI Settings

**Description:** Add configuration preferences to `PreferencesManager` for controlling cloud AI classification features.

**Acceptance criteria:**
- [ ] Add the following `@Published` properties in `PreferencesManager`:
  - `enableCloudClassification: Bool`
  - `cloudProvider: Int` (0 = Gemini, 1 = OpenAI, 2 = Anthropic)
  - `cloudModel: String`
  - `cloudEndpoint: String`
- [ ] Define default values for endpoints:
  - Gemini: `https://generativelanguage.googleapis.com/v1beta/models/`
  - OpenAI: `https://api.openai.com/v1/chat/completions`
  - Anthropic: `https://api.anthropic.com/v1/messages`
- [ ] Add default model configurations:
  - Gemini: `gemini-2.5-flash`
  - OpenAI: `gpt-4o-mini`
  - Anthropic: `claude-3-5-haiku`

**Verification:**
- [ ] Run preferences unit tests to verify cloud properties are loaded, mutated, and saved successfully.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Storage/PreferencesManager.swift`
- `AnchoredTests/Storage/PreferencesManagerTests.swift`

**Estimated scope:** S

---

### Phase 2: Cloud API Integration

#### Task 3: Implement CloudClassifier Service

**Description:** Build the networking layer that constructs payloads and posts context verification requests to the active cloud AI provider.

**Acceptance criteria:**
- [ ] Create `CloudClassifier` class.
- [ ] Implement `func classify(appName: String, windowTitle: String, url: URL?, ocrText: String, completion: @escaping (Result<Bool, Error>) -> Void)`.
- [ ] Construct the prompt asking: *"Is the application 'X' with window title 'Y', URL 'Z', and screen text 'A' productive for 'ProfileName'? Answer only 'yes' or 'no'."*
- [ ] Format JSON request payloads:
  - Gemini: `contents: [{ parts: [{ text: prompt }] }]`
  - OpenAI: `messages: [{ role: "user", content: prompt }]`
  - Anthropic: `messages: [{ role: "user", content: prompt }]` (and include headers for Anthropic version).
- [ ] Set request header `Authorization` or endpoint query keys dynamically using keys retrieved from `KeychainHelper`.
- [ ] Parse provider-specific response JSON structures to check for case-insensitive "yes" or "no".

**Verification:**
- [ ] Project compiles with no warnings.

**Dependencies:** Tasks 1, 2

**Files likely touched:**
- `Anchored/Engine/CloudClassifier.swift`

**Estimated scope:** M

---

#### Task 4: Add CloudClassifier Unit Tests with Mock HTTP Server

**Description:** Write unit tests for `CloudClassifier` using `URLProtocol` mocking to prevent real network requests while testing API parsing.

**Acceptance criteria:**
- [ ] Create `CloudClassifierTests.swift` using a custom `MockURLProtocol` interceptor.
- [ ] Write test cases verifying correct payload structures are generated for each provider.
- [ ] Write test cases verifying parsing of successful "yes" and "no" responses for Gemini, OpenAI, and Anthropic.
- [ ] Test graceful behavior under HTTP status codes 401 (invalid key), 429 (rate limited), and network timeouts (2.0s).

**Verification:**
- [ ] `xcodebuild test -only-testing:AnchoredTests/CloudClassifierTests` passes with 0 failures.

**Dependencies:** Task 3

**Files likely touched:**
- `AnchoredTests/Engine/CloudClassifierTests.swift`

**Estimated scope:** M

---

### Phase 3: FocusEngine and settings Integration

#### Task 5: Wire CloudClassifier into FocusEngine

**Description:** Integrate cloud checks in `FocusEngine.isDistraction` and `FocusEngine.isFocusContext`, using a semaphore for synchronous wait.

**Acceptance criteria:**
- [ ] In `FocusEngine.isDistraction`, if `enableCloudClassification` is active, perform OCR text extraction.
- [ ] Invoke `CloudClassifier.classify` using a `DispatchSemaphore`.
- [ ] Wait for up to 2.2 seconds.
- [ ] If classification completes successfully, return its boolean value (reversing the productive flag to match the distraction outcome).
- [ ] If classification fails or times out, print a fallback log and execute local image/keyword classifiers.

**Verification:**
- [ ] Run engine test suites verifying fallback transitions are triggered when network failures are simulated.

**Dependencies:** Task 4

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`
- `AnchoredTests/Engine/FocusEngineTests.swift`

**Estimated scope:** M

---

#### Task 6: Implement Cloud AI Settings UI Panel

**Description:** Expose cloud classification configurations (toggles, provider pickers, secure API key entries) inside the General settings view.

**Acceptance criteria:**
- [ ] In [SettingsView.swift](file:///Users/varun/Development/Anchor/Anchored/MenuBar/SettingsView.swift), add a "Cloud AI Productivity Check" toggle.
- [ ] Expose picker fields for "Cloud Provider", "Model Name", and "Endpoint URL" when enabled.
- [ ] Use `SecureField` for key inputs.
- [ ] Load the current key from `KeychainHelper` on view appear, and save/delete keys on edit commit.
- [ ] Ensure settings look aligned with the Heritage control-room card styles.

**Verification:**
- [ ] Open settings panel, modify keys and endpoints, verify changes persist across restarts.
- [ ] Verify keys remain obscured in the UI.

**Dependencies:** Tasks 2, 5

**Files likely touched:**
- `Anchored/MenuBar/SettingsView.swift`

**Estimated scope:** M

---

#### Task 7: Diagnostics & Final Verification

**Description:** Perform integration testing across the entire app stack, ensuring cloud classification flows work end-to-end.

**Acceptance criteria:**
- [ ] Verify that saving a key, selecting Gemini/OpenAI/Anthropic, and switches trigger proper cloud classification prompts.
- [ ] Ensure that no main thread blocking or frame rate drops occur when cloud calls are made.

**Verification:**
- [ ] Run the complete test suite: all 151+ tests pass.

**Dependencies:** Task 6

**Files likely touched:**
- `AnchoredTests/Engine/FocusEngineTests.swift`

**Estimated scope:** S

---

## 3. Checkpoints

### ✅ Checkpoint: Phase 1 (Keychain & Preferences)
- [ ] `KeychainHelper` compiles and passes generic security tests.
- [ ] `PreferencesManager` holds new keys and loads default endpoints.

### ✅ Checkpoint: Phase 2 (Networking & API)
- [ ] `CloudClassifier` formats requests correctly according to Gemini, OpenAI, and Anthropic APIs.
- [ ] Mock network tests run successfully with zero network calls.

### ✅ Checkpoint: Phase 3 (Integration & UI)
- [ ] Settings view displays new fields using unified control-room card primitives.
- [ ] API keys save to Keychain on edit commit.
- [ ] Failing queries fallback to local classifications without UI lag.

---

## 4. Risks and Mitigations

| Risk | Impact | Mitigation |
| :--- | :---: | :--- |
| API keys exposed in system diagnostic dumps or logs. | High | Mask settings text fields, never print payloads containing keys in logs, and only store keys in Keychain. |
| Cloud queries freeze the menu bar popover when user activates setting windows. | High | Perform network calls using `URLSession` on background queues. Use a semaphore on the engine's background tracking thread, not the UI thread. |
| Custom endpoints fail to parse due to malformed URLs. | Med | Implement URL validation in `PreferencesManager` and `SettingsView` before saving. Fall back to standard endpoints if custom values are invalid. |
| Cloud API limits or offline status breaks focus detection. | Med | Set a strict 2.0-second timeout and implement automatic fallback to local Vision classification. |

---

## 5. Parallelization Opportunities

- **Safe to Parallelize**:
  - Task 1 (KeychainHelper) and Task 2 (Preferences Manager extension) can be written concurrently by separate agents.
- **Must be Sequential**:
  - Task 3 (CloudClassifier) depends on Tasks 1 and 2.
  - Task 5 (FocusEngine wiring) depends on Task 3 and Task 4.
  - Task 6 (UI) must follow engine updates to avoid wiring issues.

### Suggested Execution Table

| Agent | Task Assignation | Focus Area |
| :--- | :--- | :--- |
| **Agent A** | Tasks 1, 2, 6 | Secure keychain helper, preference properties, and Settings view UI layout. |
| **Agent B** | Tasks 3, 4 | Cloud classifier networking service, custom payload formatting, and URLProtocol mocks. |
| **Agent C** | Tasks 5, 7 | FocusEngine wiring, semaphore timeouts, diagnostics, and regression test suites. |



================================================================================
FILE: anchored-cloud-byok-classification-spec.md
SIZE: 4257
================================================================================

# Spec: Cloud AI Classification with BYOK (Bring Your Own Key)

## Objective
To provide a fast, highly accurate, and lightweight context classification option using cloud LLMs/VLMs with the user's own API keys (BYOK). This avoids the high CPU/GPU resource usage and system package dependency overhead of local MLX vision models (like SmolVLM) while preserving user ownership of their credentials.

User Story:
> As a user, I want to use my own Google Gemini, OpenAI, or Anthropic API keys to analyze my active screen context (app name, window title, URL, and OCR screen text) so that Anchored can determine if I am focused without freezing my system, downloading huge files, or leaking my keys in plaintext.

## Tech Stack
- Language: Swift 5.7
- Frameworks: AppKit, Foundation, Security (Keychain APIs)
- Providers Supported: 
  - Google Gemini (Default: `gemini-2.5-flash`)
  - OpenAI (Default: `gpt-4o-mini`)
  - Anthropic (Default: `claude-3-5-haiku`)

## Commands
- Build Project:
  ```bash
  xcodegen generate
  xcodebuild -project Anchored.xcodeproj -scheme Anchored -destination 'platform=macOS' build
  ```
- Run Tests:
  ```bash
  xcodebuild test -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  ```

## Project Structure
- `Anchored/Engine/CloudClassifier.swift` -> Integrates API requests and payloads for Google Gemini, OpenAI, and Anthropic.
- `Anchored/Storage/KeychainHelper.swift` -> Manages secure persistence of API keys in the macOS Keychain.
- `Anchored/Storage/PreferencesManager.swift` -> Exposes Cloud AI preferences (enable toggle, provider, model name).
- `Anchored/MenuBar/SettingsView.swift` -> Appends the Cloud AI configuration fields to the General Settings Pane.
- `AnchoredTests/Engine/CloudClassifierTests.swift` -> Unit tests using URLSession mocking to verify request formatting and response decoding.

## Code Style
Standard Anchored conventions: 4-space indentation, standard naming, dependency injection.

```swift
// Example secure storage API:
struct KeychainHelper {
    static func setPassword(_ secret: String, for account: String, service: String) throws
    static func getPassword(for account: String, service: String) -> String?
    static func deletePassword(for account: String, service: String) throws
}
```

## Testing Strategy
- **Framework**: XCTest
- **Coverage**: 100% test coverage for API payload construction, API response parsing, Keychain security functions, and fallback transitions.
- **Mocking**: Use standard `URLProtocol` mocking to intercept network calls so that unit tests can verify behavior under various API responses (success `yes`/`no`, auth error, rate limit, timeout) without making real network requests.

## Boundaries
- **Always**:
  - Store API Keys in the macOS Keychain, never in `UserDefaults` in plaintext.
  - Run all network operations asynchronously on background queues with a maximum timeout deadline of 2.0 seconds.
  - Mask the input API Key inside Settings text fields (e.g. using `SecureField`).
- **Ask First**:
  - Adding support for other cloud providers (e.g. local Ollama/OpenRouter proxies).
- **Never**:
  - Block the AppKit main/UI thread while awaiting a cloud classification response.
  - Log the user's API keys or prompt payloads in plaintext logs.

## Success Criteria
- [ ] Users can toggle Cloud AI classification, select their provider, and enter their API key.
- [ ] API keys are successfully saved and loaded from the macOS Keychain, remaining hidden from standard plist preference caches.
- [ ] Prompt payloads match the official Gemini, OpenAI, and Anthropic chat completion schemas.
- [ ] Classification requests time out gracefully in 2.0 seconds, falling back to local Vision OCR or domain lists on failure.
- [ ] Intercepted mock tests pass cleanly.

## Open Questions
1. Should we support sending raw window screenshots (images) as multi-modal payloads to the cloud APIs, or is text-only context (App name + Window Title + URL + OCR-extracted text) sufficient? (Text-only is significantly faster, cheaper, and more private).
2. Should we pre-fill the API endpoint URLs, or do we want to allow users to override the endpoint for reverse proxies (like OpenRouter or custom gateways)?



================================================================================
FILE: anchored-consolidated-plan.md
SIZE: 27017
================================================================================

# Implementation Plan: Anchored Consolidated — V2.6 + Cloud BYOK + UI + ML + V3 Prep

> **Source specifications:** 
> - [V2.6 Spec](./anchored-v2.6.md) + [V2.6 Plan](./anchored-v2.6-plan.md)
> - [V2.6 Async Context Spec](./anchored-v2.6-async-context-spec.md) + [Async Plan](./anchored-v2.6-async-context-plan.md)
> - [Cloud BYOK Spec](./anchored-cloud-byok-classification-spec.md) + [Cloud Plan](./anchored-cloud-byok-classification-plan.md)
> - [Dashboard Refresh Spec](./anchored-dashboard-refresh.md) + [Refresh Plan](./anchored-dashboard-refresh-plan.md)
> - [ML Engine Plan](./anchored-ml-engine-plan.md)
> - [V3 Spec](./anchored-v3.md) + [V3 Plan](./anchored-v3-plan.md)
> - [V1 Plan](./anchored-v1-plan.md), [V2 Plan](./anchored-v2-plan.md), [V2.5 Plan](./anchored-v2.5-plan.md)

Generated: 2026-07-09 after commit `c1b679a` audit.
Repo state: master ahead origin by 6, 18 idea docs. P0 gaps identified: main-thread semaphore blocking in FocusEngine, Gemini key in URL query, XCTest sniffing in KeychainHelper, AppSwitchMonitor polling interval + sleep/wake missing.

## 1. Overview and Planning Decisions

### Overview
Anchored is Swift 5.7/macOS 13 menu-bar app: AppSwitchMonitor -> FocusEngine -> OverlayManager/MenuBarController/SessionStore. V2.6 hardens context reliability (ContextSnapshot/ContextIdentity, async AppleEventExecutor, ContextCollector with generation rejection, GRDB migrations, ContextSanitizer, opt-in history). Separately, a BYOK Cloud AI classifier (Gemini/OpenAI/Anthropic) landed in same branch with Keychain storage. Dashboard refresh unified app chrome into nautical control-room. ML engine plan defines future on-device CoreML layer. V3 adds CoreML intent, Bouncer hard enforcement, iCloud sync.

This consolidated plan merges all parallel idea docs into one executable dependency graph, so future agents don't rediscover seams.

### Decisions Locked
- Thread Isolation: AppleScript via AppleEventExecutor serial background queue, 750ms budget, discard late result (ADR: `docs/decisions/anchored-v2.6-apple-event-executor.md`).
- Cloud BYOK: Text-only prompt (appName + title + URL + OCR 2000 chars), Keychain service `com.varun.Anchored.cloud-ai`, header-only key transport (`x-goog-api-key`, `Authorization Bearer`, `x-api-key`), 2.0s URLSession timeout, non-blocking async trigger from FocusEngine, fallback to local classifiers. Never block main.
- Polling: 2.5s interval, suppress duplicate ContextIdentity (bundleID + sanitizedURL + normalizedTitle), suspend on screensDidSleep / sessionDidResignActive, resume on screensDidWake / sessionDidBecomeActive, stop privileged polling on .permissionDenied.
- Privacy: Sanitized persistence only (credentials/queries/fragments stripped), raw title/URL transient; context_observations disabled by default, bounded retention.
- Migration: GRDB v1-v4 (sessions, context_observations v2, metadata v3, sanitize legacy URLs v4), recoverable errors, never delete original DB auto.
- List Provider: Inject Focus/Distraction providers, remove NSClassFromString XCTest detection in production.
- Theme: Unified dark warm control-room, shared ThemePalette chrome, Appearance chooser removed from settings.
- ML: Inputs = sanitized ContextSnapshot only, output label+confidence+version+latency, precedence explicit rules > override cache > ML > neutral, no main-thread inference.

### Dependency Graph
```mermaid
graph TD
    A[Task1: Executor Gate] --> B[Task2-3: ContextSnapshot & Identity]
    B --> C[Task4: Collector Orchestration]
    C --> D[Task5: Async Browser Strategies]
    C --> E[Task6: Safe AX Provider]
    D --> F[Task7: AppSwitchMonitor Stream]
    E --> F
    F --> G[Task8: FocusEngine Integration]
    G --> H[Task9: List Provider Injection]
    H --> I[Task10: Singleton-Free Tests]
    G --> J[Task11-13: Storage Migrations + Sanitizer + History Recording]
    J --> K[Task14: Retention & Deletion]
    K --> L[Task15: Privacy Settings Pane]
    G --> M[Task16-18: Analytics Async Contracts + Chart Migration]
    J --> M
    H --> N[Task19-25: BYOK Keychain + Prefs + Classifier + Non-blocking Wiring + Tests]
    N --> O[Task26: Settings Cloud Panel]
    L --> P[Task27-29: Diagnostics & Release Verification]
    M --> P
    N --> P
    I --> P
    P --> Q[Task30-33: Dashboard Refresh Unification]
    Q --> R[Task34-38: ML Engine Boundary + Shadow Mode]
    R --> S[Task39-45: V3 Bouncer + iCloud Sync + Nudges]
```

## 2. Task List

### Phase 0: Foundation Gates (V2.6 Core)

#### Task 1: Validate Apple Event Executor Decision Gate
**Description:** Confirm executor harness against Safari + Chromium, menu interactivity under blocked request, signing/distribution compatibility. Record in ADR.
**Acceptance:** Executor off main thread, 750ms budget demo success/timeout/late-reject, decision record docs cancellation limits + rejected alternatives.
**Verification:** Run executor harness, confirm menus responsive, review ADR.
**Dependencies:** None
**Files:** `Anchored/Engine/AppleEventExecutor.swift`, `AnchoredTests/Engine/AppleEventExecutorTests.swift`, `docs/decisions/anchored-v2.6-apple-event-executor.md`
**Scope:** S

#### Task 2: Define ContextSnapshot & Source Enum
**Description:** Canonical runtime model: bundleID, localizedName, url?, title, source (application/chromium/safari/firefox), observedAt. Codable/Equatable.
**Acceptance:** Struct exists, identity derived via sanitizer, source enum covers browsers.
**Verification:** `xcodebuild test -only-testing:AnchoredTests/Models/ContextSnapshotTests`
**Dependencies:** None
**Files:** `Anchored/Models/ContextSnapshot.swift`, `AnchoredTests/Models/ContextSnapshotTests.swift`
**Scope:** XS

#### Task 3: Define ContextIdentity & Normalization
**Description:** Deduplication key: bundleID + sanitizedURL + normalizedTitle, ignoring observedAt. Trim, collapse whitespace, drop control chars/null, case-insensitive host/scheme compare.
**Acceptance:** Identity ignores timestamp, normalization rules covered, identical polls suppressed.
**Verification:** Unit tests for title/URL normalization edge cases.
**Dependencies:** Task 2
**Files:** `Anchored/Models/ContextSnapshot.swift`, `Anchored/Engine/ContextSanitizer.swift`
**Scope:** S

#### Task 4: Implement Collector Orchestration Primitives
**Description:** `ContextCollecting` protocol, `ContextCollector` with currentGeneration + NSLock, serial queue, browser vs accessibility routing, stale generation discard.
**Acceptance:** Generation increments, late callbacks discarded, one request active, failures typed (.timedOut/.permissionDenied/.execFailed).
**Verification:** `ContextCollectorTests` pass without sleeps.
**Dependencies:** Tasks 2-3
**Files:** `Anchored/Engine/ContextCollector.swift`, `AnchoredTests/Engine/ContextCollectorTests.swift`
**Scope:** M

### Phase 1: Providers

#### Task 5: Adapt Chromium & Safari Strategies to Async Executor
**Description:** Inject AppleEventExecuting, refactor `getActiveContext` completion-based, 750ms deadline, parse title\nURL response.
**Acceptance:** Strategies compile with executor injection, timeout returns .timedOut not empty context, empty response -> .execFailed.
**Verification:** `BrowserStrategiesTests` pass.
**Dependencies:** Task 1, Task 4
**Files:** `Anchored/Engine/BrowserStrategies.swift`, `AnchoredTests/Engine/BrowserStrategiesTests.swift`
**Scope:** M

#### Task 6: Centralize Safe Accessibility Collection
**Description:** Single helper validated via AccessibilityValue, bound recursion depth/visited-node, typed results, permissionDenied path.
**Acceptance:** No as! unsafeBitCast, Firefox + native providers typed, permission loss -> .permissionDenied no crash.
**Verification:** `AccessibilityContextProviderTests` pass, manual Firefox/Xcode/Terminal.
**Dependencies:** Tasks 2-4
**Files:** `Anchored/Engine/AccessibilityContextProvider.swift`, `Anchored/Engine/AccessibilityValue.swift`
**Scope:** M

#### Task 7: Publish Deduplicated Stream from AppSwitchMonitor
**Description:** Refactor to ContextCollecting, 2.5s Timer, ContextIdentity dedup, generation-based stale rejection, lifecycle: sleep/wake/lock/unlock suspend/resume, permissionDenied stops privileged polling, app-only tracking before permission.
**Acceptance:** Title-only, URL-only, app, native-window each emit one; identical polls none; app switch invalidates prior; sleep/lock suspend; permission loss stops privileged polling.
**Verification:** `AppSwitchMonitorTests` pass without real timers, app target builds activation returns <16ms.
**Dependencies:** Tasks 5-6
**Files:** `Anchored/Engine/AppSwitchMonitor.swift`, `Anchored/Engine/ActivityMonitor.swift`, `AnchoredTests/Engine/AppSwitchMonitorTests.swift`
**Scope:** M

### Checkpoint: Live Monitor
- Safari, Chromium, Firefox, Xcode, Terminal manual checks pass
- Collection does not block menus/overlays
- Polling emits title-only changes, suppresses duplicates
- Monitor tests pass without fixed waits

#### Task 8: Integrate ContextSnapshot with FocusEngine
**Description:** Replace positional callback args with ContextSnapshot, atomic update current app/URL/title/context, notification .focusEngineContextDidChange includes snapshot + compatibility keys, title-only events preserve focus timers.
**Acceptance:** FocusEngine consumes single snapshot, updates atomically, notification includes snapshot, title-only no duplicate distraction.
**Verification:** `FocusEngineTests`, `ShadowTrackingEngineTests`, `OverlayManagerTests` pass, app target builds.
**Dependencies:** Task 7
**Files:** `Anchored/Engine/FocusEngine.swift`, `Anchored/Engine/ShadowTrackingEngine.swift`
**Scope:** M

### Phase 2: Deterministic Test Boundaries

#### Task 9: Inject Focus & Distraction List Providers
**Description:** Minimal read protocols, FocusListManager accepts injected defaults/distraction providers, remove XCTest detection, inject into FocusEngine at AppDelegate composition root.
**Acceptance:** No production file checks NSClassFromString XT, providers injected, production behavior preserved.
**Verification:** Search no XCTest in Anchored/, `FocusEngineTests` + `DistractionListManagerTests` pass.
**Dependencies:** Task 8
**Files:** `Anchored/Storage/FocusListManager.swift`, `Anchored/Storage/DistractionListManager.swift`, `Anchored/Engine/FocusEngine.swift`, `Anchored/App/AppDelegate.swift`
**Scope:** M

#### Task 10: Remove Shared Manager Mutation from Engine Tests
**Description:** Replace singleton backup/restore with injected fakes/mocks, isolated UserDefaults suites, temp DBs.
**Acceptance:** No global singleton mutation in tests, isolated suites, no arbitrary sleeps.
**Verification:** Full suite passes in parallel, no pollution.
**Dependencies:** Task 9
**Files:** `AnchoredTests/Engine/*`, `AnchoredTests/Support/Mock*`
**Scope:** M

#### Task 11: Persistence Sanitizer + GRDB Migrations (Deterministic Writes)
**Description:** ContextSanitizer sanitizes persisted URL (strip creds/queries/fragments capped 1024 chars) + title (trim, collapse ws, control chars). DatabaseMigrations v1 sessions idx, v2 context_observations, v3 metadata, v4 sanitize legacy rows transactionally idempotent, recoverable init errors preserve original DB.
**Acceptance:** Sanitizer removes sensitive parts, legacy rows sanitized transactionally, migrations recoverable, no raw URL/titles persisted without consent.
**Verification:** Migration fixture tests pass, `SQLiteSessionStore` tests.
**Dependencies:** Tasks 2-3, 10
**Files:** `Anchored/Engine/ContextSanitizer.swift`, `Anchored/Storage/DatabaseMigrations.swift`, `Anchored/Storage/SQLiteSessionStore.swift`, `Anchored/Models/PersistedContextObservation.swift`
**Scope:** M

#### Task 12: Record Opt-In Context Observations
**Description:** ContextHistoryStore records bundleID/appName/title/url/source/domain/sessionState into context_observations only when isEnabled, via ContextHistoryPipeline listening .focusEngineContextDidChange snapshot.
**Acceptance:** Writes only when consent, sanitized path, consent enforced inside storage boundary not just UI.
**Verification:** Disabled writes produce no rows.
**Dependencies:** Task 11
**Files:** `Anchored/Storage/ContextHistoryStore.swift`, `Anchored/Engine/ContextHistoryPipeline.swift`
**Scope:** S

#### Task 13: Implement Retention, Clearing, and History Summary
**Description:** Bounded retention (configurable), clear-all, count/oldest-date summary.
**Acceptance:** Retention enforced, deletion controls work, summary query returns count + oldest.
**Verification:** Retention tests.
**Dependencies:** Task 12
**Files:** `Anchored/Storage/ContextHistoryStore.swift`, `Anchored/Storage/PreferencesManager.swift`
**Scope:** S

### Phase 3: Privacy & Analytics

#### Task 14: Wire Context History into Engine Pipeline + Privacy Settings Pane
**Description:** AppDelegate wires historyStore + pipeline, settings pane Privacy & Data section: toggle history, retention, count/oldest/clear. Cloud AI toggle separate but in same privacy section.
**Acceptance:** Consent not hidden under general/about, P0: no main thread blocking when wiring.
**Verification:** Privacy flow manual, no DB writes when disabled.
**Dependencies:** Tasks 8, 13
**Files:** `Anchored/App/AppDelegate.swift`, `Anchored/MenuBar/SettingsView.swift`, `Anchored/Storage/PreferencesManager.swift`
**Scope:** M

#### Task 15: Introduce Async Dashboard Query Contracts
**Description:** DashboardQueries typed async completion-based APIs off main, generation-checked.
**Acceptance:** No SQLite read on main, per-view request generations, error/loading states.
**Verification:** Query tests pass, rapid range changes handled.
**Dependencies:** Task 11
**Files:** `Anchored/Storage/DashboardQueries.swift`, `Anchored/Models/DashboardModels.swift`
**Scope:** M

#### Task 16: Migrate Captain's Charts to Async Load States
**Description:** Tidal wave, constellation heatmap, fleet spreadmap, top distractions, weekly history to async contracts with loading/error.
**Acceptance:** Charts non-blocking, out-of-order results discarded via generation.
**Verification:** Manual dashboard month-to-date ranges.
**Dependencies:** Task 15
**Files:** `Anchored/App/Views/TidalWaveChartView.swift`, `ConstellationHeatmapView.swift`, `FleetTreeSpreadmapView.swift`, `TopDistractionsView.swift`, `WeeklyHistoryView.swift`
**Scope:** L

### Checkpoint: Storage + Privacy
- Opt-in writes enforced in storage boundary
- Migration fixture passes
- Charts non-blocking

### Phase 4: Cloud BYOK Hardening (Post P0 Fixes)

#### Task 17: Implement KeychainHelper Secure (Completed, needs hardening)
**Description:** Already implemented; hardening: remove XCTest sniffing, use explicit useMockOnly flag.
**Acceptance:** Keys under service com.varun.Anchored.cloud-ai, kSecClassGenericPassword, account = provider, mockKeys overlay + useMockOnly.
**Verification:** KeychainHelperTests save/read/update/delete, no UserDefaults leak.
**Dependencies:** None (done)
**Files:** `Anchored/Storage/KeychainHelper.swift`, `AnchoredTests/Storage/KeychainHelperTests.swift`
**Scope:** S — Done, patched.

#### Task 18: Extend PreferencesManager Cloud AI Settings
**Description:** enableCloudClassification Bool, cloudProvider Int (0 Gemini,1 OpenAI,2 Anthropic), cloudModel String, cloudEndpoint String, defaults: gemini-2.5-flash/openai gpt-4o-mini/anthropic claude-3-5-haiku, endpoints prefilled, custom override allowed.
**Acceptance:** Published properties, clamping not needed, migration.
**Verification:** PreferencesManagerTests.
**Dependencies:** None (done)
**Files:** `Anchored/Storage/PreferencesManager.swift`
**Scope:** S — Done.

#### Task 19: Implement CloudClassifier Service (Hardened)
**Description:** Networking layer: prompt "Is app X with title Y URL Z screen text A productive for ProfileName? Answer yes/no." JSON payloads per provider: Gemini contents parts, OpenAI chat completions, Anthropic messages. Header key transport: x-goog-api-key, Bearer, x-api-key. URLSession ephemeral 2s timeout. Never log key/prompt plaintext.
**Acceptance:** P1 fix: Gemini key NOT in URL query, headers only. Prompt schemas match official. 2s deadline, background queue.
**Verification:** CloudClassifierTests via MockURLProtocol, check header not URL contains key.
**Dependencies:** Tasks 17-18
**Files:** `Anchored/Engine/CloudClassifier.swift`, `AnchoredTests/Engine/CloudClassifierTests.swift`
**Scope:** M — Fixed (key header).

#### Task 20: Non-blocking Wiring into FocusEngine
**Description:** P0 fix: Replace semaphore wait 2.2s with async utility queue fire-and-forget logging. isDistraction/isFocusContext return immediately local classification. triggerAsyncCloudClassification handles OCR only if off-main, otherwise "" for main path.
**Acceptance:** No DispatchSemaphore in FocusEngine, no main thread block >16ms, fallback to local when cloud fails/times out, logs masked.
**Verification:** Manual activation lag test, no blocking.
**Dependencies:** Task 19
**Files:** `Anchored/Engine/FocusEngine.swift`
**Scope:** M — Fixed.

#### Task 21: Cloud Tests + Diagnostics
**Description:** URLProtocol mocks for success yes/no, auth error, rate limit, timeout. Fallback transitions tested. Build full suite 151+ tests.
**Acceptance:** All cloud tests pass, no network calls, no plaintext key logs.
**Verification:** `xcodebuild test -scheme AnchoredTests -only-testing:CloudClassifierTests`
**Dependencies:** Task 20
**Files:** `AnchoredTests/Engine/CloudClassifierTests.swift`, `AnchoredTests/Support/MockURLProtocol.swift`
**Scope:** M

#### Task 22: Settings Cloud AI Panel
**Description:** SettingsView: Cloud AI toggle, provider picker, SecureField for keys, model + endpoint fields when enabled, load onAppear from KeychainHelper, save/delete on commit, masked SecureField.
**Acceptance:** UI heritage card styles, keys obscured, persists across restart, no plaintext in UserDefaults.
**Verification:** Open settings, modify keys, restart, verify hidden.
**Dependencies:** Tasks 18,20
**Files:** `Anchored/MenuBar/SettingsView.swift`
**Scope:** M

### Checkpoint: BYOK
- Keychain save/load works, masked
- Gemini header fixed, no key in URL
- FocusEngine non-blocking verified
- Settings persists

### Phase 5: App-Wide UI Overhaul (Dashboard Refresh)

#### Task 23: Shared Control-Room Primitives
**Description:** ControlRoomSurface holds shell/card/footer reusable across dashboard, settings, onboarding, popovers, overlays.
**Acceptance:** Primitives used by dashboard first, then others.
**Files:** `Anchored/App/Views/ControlRoomSurface.swift`
**Scope:** M

#### Task 24: Dashboard Nautical Control Room
**Description:** DashboardView matches image.png reference: warm dark surfaces, gold accents, layered cards, compact nav, hero headers, dense readable panels.
**Acceptance:** No pitch-black fallback, semantic palette derived from theme's own colors.
**Verification:** Release build visual QA.
**Files:** `Anchored/App/Views/DashboardView.swift`, `Anchored/Models/AppTheme.swift`
**Scope:** L

#### Task 25: Remove Appearance Chooser + Unify Settings
**Description:** SettingsView no longer exposes Appearance selection visible, retains compatibility fallback via PreferencesManager selectedThemeID = default baldr/Heritage.
**Acceptance:** Settings sidebar no separate Stats/Hourglass, Analytics/Voyage Logs unified under Captain's Log.
**Files:** `Anchored/MenuBar/SettingsView.swift`, `Anchored/Storage/PreferencesManager.swift`
**Scope:** M

#### Task 26: Align Overlays, Onboarding, Popovers to Same Language
**Description:** PermissionGate, ExitTrigger, EndSessionButton, CountdownPill, StartSessionWindow, OnboardingStyles, MenuBarPopover to shared palette.
**Acceptance:** All surfaces visually belong to same family, no mismatched chrome.
**Files:** `Anchored/Overlay/*`, `Anchored/Onboarding/*`, `Anchored/App/StartSessionWindow.swift`, `Anchored/MenuBar/MenuBarPopoverView.swift`
**Scope:** L

#### Task 27: Window Chrome + Final Alignment
**Description:** Titlebar treatment, content insets, background gradients, NSWindow appearance.
**Acceptance:** Dashboard, settings, onboarding windows consistent chrome.
**Files:** `Anchored/MenuBar/DashboardWindow.swift`, `SettingsWindow.swift`, `OnboardingWindow.swift`
**Scope:** M

### Checkpoint: UI
- Appearance chooser gone
- Unified control-room aesthetic
- No black fallback

### Phase 6: ML Engine Preparation

#### Task 28: Define Testable Classification Boundary
**Description:** ContextClassifying protocol, ClassificationResult (label, confidence, modelVersion, latency, explanation), ClassificationLabel, ClassificationPolicy, deterministic mock.
**Acceptance:** CoreML out of FocusEngine, engine depends on protocol, precedence tests pass without model.
**Files:** `Anchored/Models/ClassificationResult.swift`, `Anchored/Engine/ContextClassifying.swift`, `ClassificationPolicy.swift`
**Scope:** M

#### Task 29: Baseline Model Training Pipeline (Off-App)
**Description:** Versioned pipeline outside app target, macro F1 tracking, domain-split, quantized CoreML export stable input/output names.
**Acceptance:** Productive false-positive <2%, distracting precision >90%, macro F1 >0.85 held-out domain split.
**Files:** `scripts/ml/`
**Scope:** L

#### Task 30: CoreML Runtime
**Description:** CoreMLContextClassifier background serial inference, generation stale rejection, bounded cache, model load errors, p50/p95 latency metrics without content.
**Acceptance:** p95 <50ms, no main-thread loading, memory <100MB with model.
**Files:** `Anchored/Engine/CoreMLContextClassifier.swift`
**Scope:** L

#### Task 31: Shadow Mode
**Description:** Compute predictions but don't enforce, compare with explicit rules + user actions, diagnostics summary, feedback UI Mark as Focus/Distraction/Not Sure.
**Acceptance:** False-positive/latency targets pass across browsers/native.
**Files:** `Anchored/Engine/ShadowTrackingEngine.swift`, `Anchored/Storage/ClassificationOverrideStore.swift`
**Scope:** M

### Phase 7: V3 — Bouncer + Sync + Nudges

#### Task 32: Global Overrides & Bouncer Enforcement
**Description:** Optional aggressive hide distractions, cooldown, emergency overrides.
**Files:** `Anchored/Engine/FocusEngine.swift`, `Anchored/Overlay/OverlayManager.swift`
**Scope:** L

#### Task 33: iCloud Sync Ecosystem
**Description:** Key-Value sync profiles/settings granular merge, analytics local-only.
**Files:** `Anchored/Storage/*`
**Scope:** M

#### Task 34: AI-Dynamic Smart Nudges
**Description:** Adapt timing based on cognitive intensity, background auto-voyage tracking.
**Files:** `Anchored/Engine/SmartNudgeManager.swift`, `ShadowTrackingEngine.swift`
**Scope:** M

#### Task 35: Dashboard Metrics Migration + Final Polish
**Description:** Unified analytics, month-to-date anchored first session, all-time summary below fold, dogfooding, rollout.
**Files:** `Anchored/App/Views/*`, `Anchored/Storage/DashboardQueries.swift`
**Scope:** L

### Phase 8: Diagnostics & Release Verification

#### Task 36: Add Privacy-Safe Diagnostics + Release Checks
**Description:** Instrumentation without raw context in logs, per-view generations, migration/privacy/analytics/performance checks.
**Acceptance:**
- No AppleScript/AX/SQLite/title norm on main
- One collection at a time
- Idle mem growth <5MB over 8h
- p50 <150ms, p95 <500ms release
- Sanitized diagnostics
**Verification:** Release build, full parallel suite, manual matrix Safari/Chromium/Firefox/Xcode/Terminal, soak test.
**Dependencies:** All prior checkpoints
**Files:** `Anchored/Engine/*`, `docs/architecture/anchored-architecture.md`
**Scope:** L

## 3. Risks and Mitigations
| Risk | Impact | Mitigation |
| Apple Event APIs cannot be cancelled safely | High | Serial non-overlapping + late-result discard, ADR gate Task1 |
| Legacy DBs contain raw URLs with query/fragments | High | Sanitized transactional migration v4 idempotent, preserve original on fail |
| Native polling energy | Med | Frontmost only, dedup, suspend sleep/lock, 2.5s cadence |
| Firefox AX traversal slow/cyclic | Med | Bound recursion depth/visited count, validate types |
| Snapshot refactor churn | Med | Land snapshot first, compatibility keys V2.6 |
| Migration failure prevents launch | High | Explicit migrations, fixture tests, recoverable errors |
| Consent bypassed | High | Enforce opt-in inside storage boundary, test disabled writes |
| Async chart out-of-order | Med | Generation per view, controlled doubles |
| Gemini key in URL logs | P1 -> Fixed | Use x-goog-api-key header |
| FocusEngine semaphore blocks main | P0 -> Fixed | Async fire-and-forget trigger |
| Docs/ideas drift | Med | Megafile + external compressed archive + architecture refresh |

## 4. Parallelization
- **Safe parallel:** Keychain + Prefs tasks, classifier + tests, dashboard refresh vs engine
- **Must sequential:** Executor before strategies, strategies before monitor, monitor before FocusEngine, migrations v1->v4 sequential, Task 14 before 15
- **Owner rules:** FocusEngine Tasks 8 then 9 sequential; SQLiteSessionStore Tasks 11-14 sequential; AppDelegate Tasks 9 then 14; SettingsView Task 14 vs 22 split but coordinate

## 5. Current Repo Status (Post-Fix)
- Committed c1b679a includes AppleEventExecutor, ContextSnapshot, ContextCollector, async BrowserStrategies, AppSwitchMonitor base, FocusEngine snapshot integration, CloudClassifier, KeychainHelper, tests, decision record.
- Fixes applied in uncommitted worktree: FocusEngine non-blocking (removed semaphore), CloudClassifier header transport, KeychainHelper explicit mock flag, AppSwitchMonitor 2.5s + lifecycle.
- Remaining: verify full suite, bump architecture doc per maintainer skill, rebuild external archive, produce megafile.

## 6. Next Steps (Executable Order)
1. Fix P0s (this plan fixes them) -> commit
2. `xcodegen generate` + `xcodebuild test` suite
3. Update `docs/architecture/anchored-architecture.md` via skill
4. Move all `docs/ideas/*.md` to external `/tmp/anchored-plans-external`, compress, create megafile.

## 7. Open Questions
- Should cloud classification eventually become async decision influencing FocusEngine with generation check (currently fire-and-forget log) or stay observation-only?
- Custom endpoint validation UI for reverse proxies?
- Single fixed Heritage palette or preserve internal baldr id for compat?

## Appendix: File Sequencing Map
- contexts: `ContextSnapshot.swift` -> `ContextIdentity` -> `ContextSanitizer` -> `ContextCollector` -> `AccessibilityContextProvider` -> `BrowserStrategies` -> `AppSwitchMonitor` -> `FocusEngine` -> `ContextHistoryPipeline` -> `ContextHistoryStore`
- cloud: `KeychainHelper` -> `PreferencesManager` cloud keys -> `CloudClassifier` -> `FocusEngine.triggerAsync` -> `SettingsView`
- ui: `AppTheme` -> `ControlRoomSurface` -> `DashboardView` -> `SettingsView` -> `Overlay/*` -> `Onboarding/*`
- ml: `ClassificationResult` -> `ContextClassifying` -> `ClassificationPolicy` -> `CoreMLContextClassifier` -> `ClassificationOverrideStore` -> `ShadowTrackingEngine`



================================================================================
FILE: anchored-dashboard-refresh-audit.md
SIZE: 2805
================================================================================

# Anchored Dashboard Refresh Audit

## Reference Summary

The repo-root `image.png` is a warm nautical control-room mock, not a generic dark dashboard. The dominant traits are:

- dark brown and charcoal canvas with soft warm gradients
- gold and bronze accents instead of bright blue or purple UI chrome
- compact left navigation rail with grouped sections
- serif hero header with short supporting copy
- rounded cards with thin borders, low-contrast depth, and restrained glow
- dense but readable content, with the dashboard as the most elaborate surface

## Current Surface Audit

The current app already has the right broad pieces, but the visual language is fragmented:

- `Anchored/App/Views/DashboardView.swift` is the closest match to the mock, but its palette and glow treatment still feel more like a generalized dark shell than the reference composition.
- `Anchored/MenuBar/SettingsView.swift` still exposes the older Appearance surface and uses a mixed settings language that does not match the dashboard shell.
- `Anchored/Onboarding/OnboardingView.swift` and `Anchored/Overlay/PermissionGateView.swift` use their own pirate-styled cards and spacing rules rather than a shared shell vocabulary.
- `Anchored/MenuBar/MenuBarPopoverView.swift` is visually denser and more utility-like than the mock, with its own card hierarchy.
- `Anchored/MenuBar/DashboardWindow.swift`, `Anchored/MenuBar/SettingsWindow.swift`, and `Anchored/Onboarding/OnboardingWindow.swift` still rely on window-level defaults that can fight the new surface language.

## Locked Design Rules

1. Treat the dashboard mock as the system source of truth for spacing, hierarchy, and surface depth.
2. Derive all chrome from one semantic palette layer. Do not reintroduce ad hoc literals per screen.
3. Use warm dark canvas tones, gold accents, thin borders, and soft shadows. Avoid pitch-black fallback chrome.
4. Keep typography intentional: serif for hero headings, compact rounded sans for labels and control text.
5. Prefer reusable shell, card, separator, pill, and footer primitives so settings, onboarding, overlays, and popovers do not drift.
6. Keep the change scoped to presentation and window chrome. Do not touch engine, storage, or session behavior in phase 0.

## Change Cluster

The first implementation slice should move these surfaces together:

- dashboard shell and cards
- settings navigation and pane chrome
- onboarding step cards and background
- permission and exit-trigger overlays
- menu bar popover cards
- window-level appearance, transparency, and insets

## Phase 0 Output

This audit establishes the shared visual rules for the overhaul. The next implementation step is to extract the reusable shell and card primitives that every surface can adopt without inventing a second visual language.



================================================================================
FILE: anchored-dashboard-refresh-plan.md
SIZE: 12236
================================================================================

# Implementation Plan: Anchored App-Wide UI Overhaul — Nautical Control Room

> **Source specification:** [Anchored App-Wide UI Overhaul and Appearance Removal](./anchored-dashboard-refresh.md)

## 1. Overview and Planning Decisions

This overhaul takes the `image.png` reference as the visual target for the whole app, not just the dashboard. The work replaces the current mixed visual language with one coherent nautical control-room system: dark warm surfaces, gold accents, layered cards, compact navigation, deliberate hierarchy, and more editorial window chrome.

The implementation should preserve current behavior and data flow. The only intentional functional change is the removal of the visible Appearance/theme chooser from Settings, with any stored theme preference retained only as a compatibility fallback if needed.

### Decisions Locked for This Plan

- **Visual direction:** use the reference image as the canonical style guide for dashboard, settings, onboarding, overlays, menu bar popovers, and related windows.
- **Scope boundary:** do not change focus-engine logic, persistence schema, analytics behavior, or session rules as part of the UI work.
- **Theme surface:** remove the user-facing Appearance section from Settings and stop presenting theme selection in the app.
- **Compatibility:** keep old theme preference data readable only if needed to avoid breaking existing installs.
- **Shared language:** extract reusable shell/card/surface primitives so the app does not drift back into surface-specific styling.

### Dependency Graph

```mermaid
graph TD
    A[Task 1: Visual Audit and Shared Surface Decisions] --> B[Task 2: App Shell and Palette Primitives]
    A --> C[Task 3: Dashboard Redesign]
    B --> C
    B --> D[Task 4: Settings and Appearance Removal]
    B --> E[Task 5: Auxiliary Surface Restyle]
    C --> F[Task 6: Window and Chrome Alignment]
    D --> F
    E --> F
    F --> G[Task 7: Architecture Doc Refresh]
```

---

## 2. Task List

### Phase 0: Visual Baseline and Scope Lock

#### Task 1: Audit the existing chrome surfaces against the reference and lock shared design rules

**Description:** Inspect the current dashboard, settings, onboarding, overlays, popovers, and window shells against `image.png`, then define the shared visual rules the overhaul must use. This task should establish the reusable surface vocabulary before any view refactor begins so later work does not invent inconsistent styles.

**Acceptance criteria:**

- [ ] The target surfaces are identified and grouped by shared shell needs.
- [ ] The dashboard reference is translated into concrete rules for spacing, surface depth, border treatment, typography hierarchy, and accent usage.
- [ ] A short implementation note captures which parts of the app must change together to avoid mixed chrome.

**Verification:**

- [ ] Review the audit note alongside `image.png` and confirm the intended language matches the mock.
- [ ] Confirm the scope excludes engine, storage, and behavioral changes.

**Dependencies:** None

**Files likely touched:**

- `docs/ideas/anchored-dashboard-refresh.md`
- `docs/ideas/anchored-dashboard-refresh-plan.md`
- optionally a short design note under `docs/ideas/`

**Estimated scope:** S

### Checkpoint: Visual Baseline

- [ ] Reference-driven design rules are written down.
- [ ] Scope is limited to UI chrome and navigation.
- [ ] Shared surface vocabulary is clear enough to guide implementation.

---

### Phase 1: Shared Shell and Primitive Layer

#### Task 2: Introduce reusable shell and card primitives for the new visual language

**Description:** Create or refactor shared SwiftUI primitives for background shells, cards, separators, section headers, and range/control pills so the new look can be applied consistently across multiple windows. Prefer a small set of reusable components over per-screen styling blocks.

**Acceptance criteria:**

- [ ] The app has reusable primitives for card surfaces, shell backgrounds, borders, and chrome-accent treatment.
- [ ] Those primitives use a single semantic palette language instead of ad hoc color literals.
- [ ] Existing surfaces can adopt the new primitives without duplicating layout code.

**Verification:**

- [ ] App target builds after the primitives are introduced.
- [ ] Preview or compile checks pass for any extracted component files.

**Dependencies:** Task 1

**Files likely touched:**

- `Anchored/App/Views/` shared view files
- `Anchored/MenuBar/` shared chrome files
- `Anchored/Models/AppTheme.swift`
- `Anchored/Storage/PreferencesManager.swift`

**Estimated scope:** M

#### Task 3: Restyle the main dashboard to match the reference composition

**Description:** Rebuild [DashboardView.swift](/Users/varun/Development/Anchor/Anchored/App/Views/DashboardView.swift) so the dashboard becomes the canonical example of the new visual language. This includes the left rail, hero header, range selector, chart cards, distraction list, metric cards, and footer strip.

**Acceptance criteria:**

- [ ] The dashboard uses the reference-style composition: compact nav rail, title block, top-right range selector, primary chart, secondary cards, and footer.
- [ ] The typography hierarchy and spacing feel like the mock rather than the current generic split view.
- [ ] The dashboard uses the shared primitives from Task 2 rather than local one-off chrome.

**Verification:**

- [ ] Build the app target after the dashboard refactor.
- [ ] Run a release build and visually inspect the dashboard against the reference image.

**Dependencies:** Tasks 1, 2

**Files likely touched:**

- `Anchored/App/Views/DashboardView.swift`
- `Anchored/MenuBar/DashboardWindow.swift`
- `Anchored/MenuBar/MenuBarController.swift` if window behavior needs tuning

**Estimated scope:** L

### Checkpoint: Dashboard Core

- [ ] Dashboard composition matches the target hierarchy.
- [ ] Shared shell primitives are in use.
- [ ] No behavior or data model regressions have been introduced.

---

### Phase 2: Settings and Appearance Removal

#### Task 4: Remove the visible Appearance/theme chooser from Settings

**Description:** Delete the user-facing Appearance section from Settings and remove any navigation paths that expose theme selection. Preserve compatibility only where needed so older preference data does not cause startup or rendering issues.

**Acceptance criteria:**

- [ ] Settings no longer shows an Appearance section or theme picker.
- [ ] The settings sidebar and section routing still work for the remaining sections.
- [ ] Theme preference storage either becomes a silent fallback or is retired cleanly without affecting launch.

**Verification:**

- [ ] Build the app target after the Settings cleanup.
- [ ] Open Settings and confirm there is no Appearance entry or theme card UI.

**Dependencies:** Task 2

**Files likely touched:**

- `Anchored/MenuBar/SettingsView.swift`
- `Anchored/MenuBar/SettingsWindow.swift`
- `Anchored/Storage/PreferencesManager.swift`
- `Anchored/Models/AppTheme.swift` if compatibility code is retained

**Estimated scope:** M

#### Task 5: Restyle onboarding, overlays, menu bar popovers, and secondary windows

**Description:** Apply the same visual language to the remaining app surfaces that users see regularly: onboarding, permission gates, exit-trigger overlays, start-session windows, and menu bar popovers. The goal is to eliminate obvious style drift outside the dashboard.

**Acceptance criteria:**

- [ ] Onboarding, overlays, popovers, and auxiliary windows visually belong to the same app family as the dashboard.
- [ ] The shared palette and surface rules are used consistently across those surfaces.
- [ ] No surface falls back to pitch-black or mismatched chrome.

**Verification:**

- [ ] Build the app target after each affected surface is updated.
- [ ] Launch the app and visually inspect the affected windows for consistency.

**Dependencies:** Task 2

**Files likely touched:**

- `Anchored/Onboarding/OnboardingWindow.swift`
- `Anchored/Onboarding/OnboardingStyles.swift`
- `Anchored/Overlay/PermissionGateView.swift`
- `Anchored/Overlay/PermissionGatePanel.swift`
- `Anchored/Overlay/ExitTriggerView.swift`
- `Anchored/MenuBar/MenuBarPopoverView.swift`
- `Anchored/App/StartSessionWindow.swift`

**Estimated scope:** L

### Checkpoint: App Surfaces

- [ ] Settings no longer exposes appearance selection.
- [ ] Secondary windows follow the same visual language as the dashboard.
- [ ] Shared chrome primitives hold across the app, not just one screen.

---

### Phase 3: Window Chrome and Final Alignment

#### Task 6: Align window chrome, backgrounds, and spacing across the app

**Description:** Tune the actual window-level chrome so the application feels cohesive when each surface is shown in its own window or panel. This includes titlebar treatment, content insets, background gradients, and any NSWindow-level appearance settings that still conflict with the new design.

**Acceptance criteria:**

- [ ] Dashboard, settings, onboarding, and other windows open with consistent window treatment.
- [ ] Titlebar transparency, content background, and padding feel deliberate rather than default.
- [ ] There are no visible mismatches between AppKit window chrome and SwiftUI content surfaces.

**Verification:**

- [ ] Build the app target and confirm no window-chrome compile regressions.
- [ ] Perform a manual walkthrough of the main windows in a release build.

**Dependencies:** Tasks 3, 4, 5

**Files likely touched:**

- `Anchored/MenuBar/DashboardWindow.swift`
- `Anchored/MenuBar/SettingsWindow.swift`
- `Anchored/Onboarding/OnboardingWindow.swift`
- `Anchored/App/StartSessionWindow.swift`

**Estimated scope:** M

#### Task 7: Refresh architecture and implementation notes to reflect the shipped UI overhaul

**Description:** Update the canonical architecture doc and any related notes so future agents understand the new app-wide visual language, the removed Appearance surface, and the main files to inspect for future UI changes.

**Acceptance criteria:**

- [ ] `docs/architecture/anchored-architecture.md` reflects the new shipped UI reality.
- [ ] The doc names the new UI seams and the files future agents should read first.
- [ ] Any stale references to a user-facing Appearance chooser are removed or clearly marked obsolete.

**Verification:**

- [ ] Review the updated architecture doc for accuracy and brevity.
- [ ] Confirm the repo map still answers the key orientation questions without broad search.

**Dependencies:** Tasks 3, 4, 5, 6

**Files likely touched:**

- `docs/architecture/anchored-architecture.md`
- `docs/ideas/anchored-dashboard-refresh.md`
- `docs/ideas/anchored-dashboard-refresh-plan.md`

**Estimated scope:** S

### Checkpoint: Complete

- [ ] The app-wide UI overhaul matches the intended reference language.
- [ ] The Appearance chooser is gone from the user-facing settings flow.
- [ ] All major app surfaces share one coherent visual system.
- [ ] The architecture doc has been updated to match the shipped result.

## 3. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Restyling only one window leaves the app visually fragmented | High | Use shared primitives first, then apply them across dashboard, settings, onboarding, overlays, and popovers |
| Removing theme selection breaks existing stored preferences | Medium | Keep a compatibility fallback in preferences until the new look is fully shipped |
| Window-level AppKit chrome fights the new SwiftUI surfaces | Medium | Treat NSWindow appearance, titlebar transparency, and background treatment as part of the same task slice |
| Scope expands into behavior or persistence changes | High | Keep the spec boundary strict: visual language only, not engine or storage behavior |

## 4. Open Questions

- Should the app keep any internal theme plumbing after the overhaul, or should it fully collapse to one fixed visual system?
- Do we want the dashboard to be the most ornate surface, with settings and overlays slightly simpler, or should every surface match the dashboard density exactly?
- Are there any existing windows or panels that should intentionally remain visually plain for utility reasons?



================================================================================
FILE: anchored-dashboard-refresh.md
SIZE: 6968
================================================================================

# Spec: Anchored App-Wide UI Overhaul and Appearance Removal

## Assumptions

1. The attached `image.png` is the target visual direction for the entire app, not just the dashboard.
2. The app keeps its current data sources and behaviors; this change is primarily presentation, navigation, and chrome.
3. The visible Appearance chooser should be removed from Settings so users no longer pick themes.
4. Existing theme preference data may remain only as a compatibility fallback for older installs.
5. The app stays on Swift 5.7 and macOS 13.

## Objective

Redesign Anchored so the whole user-facing app matches the attached reference: a warm, dark nautical control room with compact side navigation, prominent hero headers, layered cards, gold accents, and dense but readable content panels.

At the same time, remove the user-facing appearance/theme selection surface so the product has one coherent visual system instead of a theme picker plus multiple drifting visual languages.

Success means the app feels intentional and premium across dashboard, settings, onboarding, popovers, overlays, and related windows, the palette is consistent across the visible surfaces involved in this change, and the settings UI no longer presents an Appearance option.

## Tech Stack

- Swift 5.7
- SwiftUI and AppKit
- XcodeGen project generation
- XCTest for unit coverage
- Existing Anchored theme and preferences models, used only as internal compatibility or styling support if needed

## Commands

Generate project:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild -project Anchored.xcodeproj -scheme Anchored -destination 'platform=macOS' build
```

Test:

```bash
xcodebuild test -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Manual verification:

```bash
xcodebuild -project Anchored.xcodeproj -scheme Anchored -configuration Release -destination 'platform=macOS' build
```

Then install and open the built `Anchored.app` from `/Applications` for visual QA.

## Project Structure

- `Anchored/App/Views/DashboardView.swift`
  - Main dashboard layout, section composition, cards, range selector, and hero header.
- `Anchored/MenuBar/MenuBarPopoverView.swift`
  - Menu bar popover chrome and interaction surfaces.
- `Anchored/MenuBar/DashboardWindow.swift`
  - Window sizing, appearance, and hosting setup for the dashboard shell.
- `Anchored/MenuBar/SettingsView.swift`
  - Settings navigation and panes; remove the Appearance entry and related theme picker UI.
- `Anchored/Storage/PreferencesManager.swift`
  - Theme preference persistence or compatibility fallback if the app keeps an internal fixed palette.
- `Anchored/Models/AppTheme.swift`
  - Shared theme palette definitions if the fixed dashboard continues to use the semantic palette layer internally.
- `Anchored/Onboarding/OnboardingWindow.swift`
  - First-run flow chrome and presentation if it should match the new visual language.
- `Anchored/Overlay/PermissionGateView.swift`
  - Permission gate overlay styling.
- `Anchored/Overlay/ExitTriggerView.swift`
  - Session prompt overlay styling.
- `Anchored/App/StartSessionWindow.swift`
  - Start-session window chrome and layout if it should be restyled to the same language.
- `AnchoredTests/Storage/PreferencesManagerTests.swift`
  - Preference fallback behavior and any compatibility checks for the removed appearance surface.
- `AnchoredTests/Models/AppThemeTests.swift`
  - Palette invariants if the internal theme layer remains part of the implementation.
- `docs/architecture/anchored-architecture.md`
  - Update after the shipped change so the repo map reflects the new dashboard and removed appearance surface.

## Code Style

Prefer SwiftUI composition with small, explicit card views and semantic palette values rather than hard-coded ad hoc colors.

```swift
VStack(alignment: .leading, spacing: 12) {
    Text("Captain's Deck")
        .font(.system(size: 28, weight: .semibold, design: .serif))
        .foregroundColor(palette.textPrimaryColor)

    DashboardCard(title: "Tide Over Time", subtitle: range.title, palette: palette) {
        TrendSparkline(buckets: buckets, palette: palette, axisLabels: axisLabels)
    }
}
.padding(16)
.background(
    LinearGradient(
        colors: [palette.canvasColor, palette.surfaceColor],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
)
```

Conventions for this change:

- Use the new nautical palette consistently across all visible app surfaces.
- Keep the layout dense but readable, with a clear hierarchy from hero header to supporting cards.
- Prefer reusable card primitives and shell surfaces over per-view styling duplication.
- Avoid introducing a second visual language for settings, onboarding, overlays, or popovers.

## Testing Strategy

- Add or update unit tests for appearance-removal compatibility and any preference fallback behavior.
- Keep existing model or palette tests only if the internal theme layer still matters after the refactor.
- Build the app after each major UI slice to catch layout or type errors early.
- Use manual visual QA in a release build as the primary verification for visual fidelity, because the target is a screenshot match rather than a purely logic-driven feature.

## Boundaries

- Always: preserve current analytics and session data behavior unless the spec explicitly changes it.
- Always: keep the change local to presentation and navigation unless a deeper seam is required.
- Always: update the architecture doc after the shipped UI change.
- Ask first: deleting stored preference keys, adding new dependencies, or changing the project layout.
- Ask first: removing internal theme code entirely if it is still needed by other surfaces.
- Never: reintroduce a visible Appearance/theme picker in the main settings flow.
- Never: change persistence schema or focus-engine behavior as part of this UI refresh.

## Success Criteria

- The dashboard layout closely matches the reference image in structure, density, and tone.
- Settings, onboarding, overlays, menu bar popovers, and auxiliary windows share the same visual language.
- The left rail, hero header, card grid, and range selector are visually consistent and feel like one system.
- The Appearance section no longer appears in Settings.
- Existing installs continue to open and run without a migration failure.
- The release build passes manual QA and opens the redesigned dashboard correctly.
- `docs/architecture/anchored-architecture.md` reflects the new shipped reality.

## Open Questions

- Should the removed appearance UI leave behind a silent compatibility fallback, or should the app fully ignore the stored theme selection once the new app-wide look ships?
- Should every visible window adopt the same shell and palette language, or should the dashboard remain the most elaborate surface?
- Are there any settings subsections that should be re-ordered once Appearance is removed?



================================================================================
FILE: anchored-ml-engine-plan.md
SIZE: 4986
================================================================================

# Anchored ML Engine Implementation Plan

## Goal

Ship an on-device classifier that can distinguish productive, distracting, and uncertain context without blocking the UI or overriding explicit user rules. The ML layer must improve focus classification; it must not become a second, opaque state machine.

## Product Contract

- Inputs: sanitized `ContextSnapshot` fields only: bundle ID, host/path, and title.
- Outputs: label, confidence, model version, latency, and explanation source.
- Precedence: explicit profile rules > user override cache > ML prediction > neutral fallback.
- Privacy: inference and feedback remain local. Raw titles and URLs are never logged.
- Safety: uncertain or failed predictions resolve to neutral and never trigger blocking.

## Phase 0: Finish the Context Foundation

Complete the V2.6 runtime path before adding CoreML:

1. Introduce the canonical `ContextSnapshot` monitor-to-engine contract.
2. Move browser and Accessibility collection off the main thread.
3. Reject stale and duplicate results.
4. Preserve explicit app/domain classification behavior with regression tests.

Exit gate: Safari, Chromium, Firefox, and native app context updates are reliable, deduplicated, and non-blocking.

## Phase 1: Define a Testable Classification Boundary

Add:

- `ContextClassifying`
- `ClassificationResult`
- `ClassificationLabel`
- `ClassificationPolicy`
- a deterministic mock classifier for engine tests

Keep CoreML out of `FocusEngine`. The engine should depend on the protocol and consume a resolved decision produced by policy code.

Exit gate: precedence and fallback tests pass without loading a model.

## Phase 2: Build and Evaluate the Baseline Model

Create a versioned training pipeline outside the app target.

- Start with real, reviewed examples rather than synthetic URLs alone.
- Split data by domain/source to prevent train/test leakage.
- Track macro F1, per-class precision/recall, calibration, and confusion matrices.
- Export a compact CoreML text model with stable input/output names.
- Store dataset and model metadata, not sensitive user context, in the repo.

Initial acceptance targets:

- productive false-positive rate below 2%
- distracting precision above 90%
- macro F1 above 0.85 on a held-out domain split

## Phase 3: Add the CoreML Runtime

Implement `CoreMLContextClassifier` with:

- background serial inference
- generation-based stale-result rejection
- bounded in-memory cache
- model loading/version errors
- p50/p95 latency metrics without content values

Targets:

- p95 inference below 50 ms on supported Macs
- no main-thread model loading or prediction
- app memory below 100 MB with the model loaded

## Phase 4: Run in Shadow Mode

For at least one internal release:

- compute predictions but do not alter enforcement
- compare predictions with explicit rules and user actions
- expose a local diagnostics summary
- add "Mark as Focus", "Mark as Distraction", and "Not Sure" feedback

Exit gate: measured production-like false-positive and latency targets pass across supported browsers and native apps.

## Phase 5: Controlled Engine Integration

Introduce ML decisions behind a preference flag.

1. Explicit allow/block rules always win.
2. User override cache wins over the bundled model.
3. High-confidence predictions may classify context.
4. Low-confidence, timed-out, or failed predictions remain neutral.
5. ML cannot directly start dimming or blocking without the existing `FocusEngine` timers and state invariants.

Add focused regression tests for rapid tab switching, stale results, model failure, and conflicting explicit rules.

## Phase 6: Personalization

Do not begin with one-example `MLUpdateTask` retraining. First ship a local override cache and collect enough user-labeled examples for safe batching. Add model updates only after proving:

- updates are atomic and rollbackable
- model size remains bounded
- accuracy does not regress on a fixed validation set
- the running classifier reloads only after a validated update

## Verification Matrix

- Unit: policy precedence, confidence thresholds, stale results, cache, failures.
- Integration: browser/native snapshot to classification to engine decision.
- Model: held-out domain split, calibration, drift, and adversarial titles.
- Performance: launch cost, p95 inference, memory, and energy.
- Privacy: no raw context in logs, diagnostics, crash text, or analytics.
- Release: full XCTest suite plus a release build and installed-app manual pass.

## Likely Files

- `Anchored/Models/ContextSnapshot.swift`
- `Anchored/Models/ClassificationResult.swift`
- `Anchored/Engine/ContextClassifying.swift`
- `Anchored/Engine/ClassificationPolicy.swift`
- `Anchored/Engine/CoreMLContextClassifier.swift`
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Storage/ClassificationOverrideStore.swift`
- `AnchoredTests/Engine/ClassificationPolicyTests.swift`
- `AnchoredTests/Engine/CoreMLContextClassifierTests.swift`
- `scripts/ml/`




================================================================================
FILE: anchored-v1-plan.md
SIZE: 34061
================================================================================

# Implementation Plan: Anchored V1 — Ghost Mode

## Overview

Build the complete Anchored V1 macOS utility from scratch: a zero-permission, zero-configuration menu bar app that passively detects work focus via `NSWorkspace` app switch notifications, prompts users to anchor sessions at the exit point, and applies graduated screen dimming when they stray to distraction apps during an active session. Includes a 4-state onboarding flow, JSON session logging, and audio feedback.

**Source spec:** [anchored-v1.md](file:///Users/varun/Development/Anchor/docs/ideas/anchored-v1.md)

## Architecture Decisions

- **AppKit-first, SwiftUI for views:** `NSApplicationDelegate` bootstraps the app. All windows are `NSWindow`/`NSPanel` created programmatically. SwiftUI views are embedded via `NSHostingView` for onboarding cards and menu bar popovers. This gives full control over window-level properties (`ignoresMouseEvents`, `level`, `collectionBehavior`) that SwiftUI window management doesn't expose reliably.
- **LSUIElement:** The app runs as an agent (`LSUIElement = true` in Info.plist) — no Dock icon, menu bar only.
- **Deployment target:** macOS 13.0+ (Ventura). No backward-compat shims for Big Sur/Monterey.
- **V2 seam:** The `ActivityMonitor` protocol is defined in V1 but only `AppSwitchMonitor` conforms. Data models include a `url: String?` field that's always `nil` in V1. This is the insertion point for `BrowserURLMonitor` in V2.
- **No external dependencies.** Pure Swift + AppKit + SwiftUI. No SPM packages, no CocoaPods. The app should build with `xcodebuild` and nothing else.

## Dependency Graph

```mermaid
graph TD
    A[Xcode Project Scaffold] --> B[Data Models & SessionStore]
    A --> C[DistractionListManager]
    A --> D[AudioEngine]
    B --> E[ActivityMonitor Protocol]
    C --> E
    E --> F[AppSwitchMonitor]
    F --> G[FocusEngine State Machine]
    C --> G
    B --> G
    G --> H[DimOverlay Window]
    G --> I[CountdownPill Panel]
    G --> J[ExitTriggerCapsule Panel]
    H --> K[OverlayManager]
    I --> K
    J --> K
    G --> K
    K --> L[MenuBarController]
    B --> L
    D --> M[Audio Hookup]
    K --> M
    L --> M
    L --> N[Onboarding Window]
    C --> N
    N --> O[AppDelegate Integration]
    L --> O
    G --> O
    M --> O
    O --> P[Polish & Edge Cases]
```

## Task List

---

### Phase 1: Foundation

#### Task 1: Xcode Project Scaffold

**Description:** Create the Xcode project with the correct target configuration: macOS app, Swift, AppKit lifecycle (not SwiftUI App), `LSUIElement` set in Info.plist, deployment target macOS 13.0, and a clean folder structure matching the architecture diagram.

**Acceptance criteria:**
- [ ] Xcode project builds and runs, showing an empty menu bar icon (placeholder `NSStatusItem`)
- [ ] No Dock icon appears (`LSUIElement = YES` in Info.plist)
- [ ] Deployment target is macOS 13.0
- [ ] Folder structure exists: `Anchored/App/`, `Anchored/Engine/`, `Anchored/Overlay/`, `Anchored/Onboarding/`, `Anchored/MenuBar/`, `Anchored/Audio/`, `Anchored/Models/`, `Anchored/Storage/`
- [ ] `main.swift` or `AppDelegate.swift` uses `NSApplicationDelegate` (no `@main App` struct)

**Verification:**
- [ ] `xcodebuild -scheme Anchored build` succeeds
- [ ] Running the app shows a menu bar icon and no Dock icon

**Dependencies:** None

**Files likely touched:**
- `Anchored.xcodeproj/`
- `Anchored/App/AppDelegate.swift`
- `Anchored/Info.plist`
- `Anchored/App/main.swift`

**Estimated scope:** Small (1-2 files + project config)

---

#### Task 2: Data Models & Session Event Schema

**Description:** Define the core data types used throughout the app: `SessionEvent` (the JSON-serializable event log entry), `SessionState` (the engine's runtime state enum), and `AppContext` (a lightweight wrapper around bundle ID + app name). Include the `url: String?` field on `SessionEvent` for V2 readiness.

**Acceptance criteria:**
- [ ] `SessionEvent` is `Codable` with all fields from the spec schema (`id`, `timestamp`, `type`, `appBundleID`, `appName`, `url`, `focusDurationSeconds`, `sessionDurationSeconds`, `distractionAppBundleID`, `action`)
- [ ] `SessionEventType` enum: `.sessionStart`, `.sessionEnd`, `.distractionDetected`, `.escalationTriggered`
- [ ] `SessionAction` enum: `.anchored`, `.dismissed`, `.timeout`, `.escalated`, `.returned`
- [ ] `AppContext` struct wraps `bundleIdentifier: String` and `localizedName: String`
- [ ] All types compile and can round-trip through JSON encoding/decoding

**Verification:**
- [ ] Unit test: encode a `SessionEvent` to JSON and decode it back, assert equality
- [ ] Build succeeds

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Models/SessionEvent.swift`
- `Anchored/Models/AppContext.swift`
- `AnchoredTests/Models/SessionEventTests.swift`

**Estimated scope:** Small (2-3 files)

---

#### Task 3: SessionStore (JSON Persistence)

**Description:** Build the `SessionStore` class that reads and writes `SessionEvent` arrays to `~/Library/Application Support/Anchored/sessions.json`. Handles directory creation, file creation on first write, atomic writes, and provides query methods for "last N sessions."

**Acceptance criteria:**
- [ ] `SessionStore.shared` singleton with configurable file path (for testing)
- [ ] `func log(_ event: SessionEvent)` appends an event and writes atomically
- [ ] `func recentSessions(limit: Int) -> [SessionEvent]` returns the most recent N `sessionEnd` events
- [ ] Creates `~/Library/Application Support/Anchored/` directory if it doesn't exist
- [ ] Thread-safe (uses a serial dispatch queue for file I/O)

**Verification:**
- [ ] Unit test: log 5 events, read back recent 3, assert correct order and count
- [ ] Unit test: first write creates directory and file
- [ ] Build succeeds

**Dependencies:** Task 2

**Files likely touched:**
- `Anchored/Storage/SessionStore.swift`
- `AnchoredTests/Storage/SessionStoreTests.swift`

**Estimated scope:** Small (2 files)

---

#### Task 4: DistractionListManager

**Description:** Build the `DistractionListManager` that stores the user's distraction app bundle IDs in `UserDefaults`. Provides the default pre-selected list, supports add/remove, and exposes a `func isDistraction(_ bundleID: String) -> Bool` check used by the engine.

**Acceptance criteria:**
- [ ] Default distraction list contains bundle IDs for: Discord, Slack, Messages, Telegram, Twitter/X (if desktop app), Steam, Spotify, Music
- [ ] `func isDistraction(_ bundleID: String) -> Bool` performs O(1) lookup (backed by a `Set`)
- [ ] `func add(_ bundleID: String)` and `func remove(_ bundleID: String)` persist changes to `UserDefaults`
- [ ] `var allDistractions: [String]` returns the current list for UI display
- [ ] Publishes changes via `@Published` or `NotificationCenter` so the engine picks up edits without restart

**Verification:**
- [ ] Unit test: default list contains expected bundle IDs
- [ ] Unit test: add a custom bundle ID, verify `isDistraction` returns true
- [ ] Unit test: remove a default, verify `isDistraction` returns false
- [ ] Build succeeds

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Storage/DistractionListManager.swift`
- `AnchoredTests/Storage/DistractionListManagerTests.swift`

**Estimated scope:** Small (2 files)

---

#### Task 5: AudioEngine

**Description:** Build a lightweight `AudioEngine` that preloads and plays short sound effects. V1 uses three sounds: a tactile tick (button press), a subtle pop (capsule appearance), and a warm chime (session anchored / onboarding complete). Use `NSSound` with system sounds or bundled `.caf`/`.aiff` assets.

**Acceptance criteria:**
- [ ] `AudioEngine.shared` singleton
- [ ] `func play(_ sound: AnchoredSound)` where `AnchoredSound` is an enum: `.tick`, `.pop`, `.chime`
- [ ] Custom `.caf` sound assets bundled in `Anchored/Resources/Sounds/` — tactile tick, subtle pop, warm chime
- [ ] Sounds are preloaded at init to avoid first-play latency
- [ ] Playback is non-blocking (fire-and-forget via `AVAudioPlayer` or `NSSound`)
- [ ] Gracefully handles missing sound files (logs warning, doesn't crash)

**Verification:**
- [ ] Manual test: call `AudioEngine.shared.play(.tick)` — hear a sound
- [ ] Build succeeds

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Audio/AudioEngine.swift`
- `Anchored/Audio/AnchoredSound.swift`
- `Anchored/Resources/Sounds/` (sound assets)

**Estimated scope:** Small (2-3 files + assets)

---

### ✅ Checkpoint: Foundation

- [ ] All unit tests pass
- [ ] App builds and launches (empty menu bar icon, no Dock icon)
- [ ] `SessionStore` reads/writes JSON to disk
- [ ] `DistractionListManager` persists to UserDefaults
- [ ] `AudioEngine` plays all three sounds
- [ ] No external dependencies introduced

---

### Phase 2: Core Engine

#### Task 6: ActivityMonitor Protocol & AppSwitchMonitor

**Description:** Define the `ActivityMonitor` protocol (the V2 seam) and implement `AppSwitchMonitor`, which listens to `NSWorkspace.didActivateApplicationNotification` and emits `(bundleID: String, url: URL?)` tuples on every app switch. The `url` is always `nil` in V1.

**Acceptance criteria:**
- [ ] `ActivityMonitor` protocol with `var onContextChange: ((_ bundleID: String, _ url: URL?) -> Void)? { get set }` and `func start()` / `func stop()`
- [ ] `AppSwitchMonitor` conforms to `ActivityMonitor`
- [ ] On `start()`, registers for `NSWorkspace.didActivateApplicationNotification`
- [ ] On each notification, extracts `NSRunningApplication.bundleIdentifier` and calls `onContextChange`
- [ ] On `stop()`, removes the observer
- [ ] Ignores notifications where `bundleIdentifier` is `nil` (rare but possible for system processes)

**Verification:**
- [ ] Manual test: launch app, switch between apps, verify `onContextChange` fires with correct bundle IDs (add print statements)
- [ ] Build succeeds

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Engine/ActivityMonitor.swift`
- `Anchored/Engine/AppSwitchMonitor.swift`

**Estimated scope:** Small (2 files)

---

#### Task 7: FocusEngine State Machine

**Description:** Build the `FocusEngine` — the central coordinator that receives context change events from `AppSwitchMonitor`, manages work session tracking, and decides when to show the exit-trigger capsule, start the countdown pill, or trigger ambient escalation. This is the brain of the app.

**Acceptance criteria:**
- [ ] `FocusEngine` holds references to `ActivityMonitor`, `DistractionListManager`, and `SessionStore`
- [ ] Tracks `currentApp: String?`, `workSessionStart: Date?`, and `activeSession: ActiveSession?` (struct with `startDate`, `anchoredDuration`, `appName`)
- [ ] Implements the decision logic from the spec:
  - Distraction app detected + no session + elapsed > threshold → delegate call to show exit-trigger capsule
  - Distraction app detected + active session → delegate call to show countdown pill
  - Non-distraction app detected + was dimming → delegate call to lift overlay
  - Non-distraction app detected + no `workSessionStart` → sets `workSessionStart = now`
- [ ] Exposes a `FocusEngineDelegate` protocol with callbacks: `didRequestExitTrigger(duration:appName:)`, `didDetectDistraction(bundleID:)`, `didReturnToWork()`, `sessionDidEnd()`
- [ ] `func anchorSession(duration: TimeInterval)` locks in an active session
- [ ] `func dismissTrigger()` resets `workSessionStart`
- [ ] `func endSession()` terminates the active session and logs a `sessionEnd` event
- [ ] Session auto-ends when timer expires (uses a `Timer` scheduled for the anchored duration)
- [ ] Configurable `focusThreshold: TimeInterval` (default 600s = 10 min)

**Verification:**
- [ ] Unit test: simulate app switches via mock `ActivityMonitor`, verify delegate calls fire in correct order
- [ ] Unit test: verify session auto-ends after timer duration
- [ ] Unit test: verify `workSessionStart` resets on distraction detection when no session is active
- [ ] Build succeeds

**Dependencies:** Tasks 3, 4, 6

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Engine/FocusEngineDelegate.swift`
- `Anchored/Models/ActiveSession.swift`
- `AnchoredTests/Engine/FocusEngineTests.swift`

**Estimated scope:** Medium (3-4 files)

---

### ✅ Checkpoint: Core Engine

- [ ] All unit tests pass (including FocusEngine state machine tests)
- [ ] App can detect app switches and log them to console
- [ ] FocusEngine correctly identifies distraction vs. non-distraction apps
- [ ] State transitions are verified: idle → watching → trigger-ready → anchored → distraction-detected → returned
- [ ] The engine is fully testable with mock inputs (no UI dependency)

---

### Phase 3: Overlay System

#### Task 8: DimOverlay Window

**Description:** Build the ambient escalation overlay — a borderless, click-through `NSWindow` that spans all connected displays and ramps opacity from 0% to 50% over 15 seconds. Includes a tiny "⚓ Anchored" label and "End Session" button in the bottom-right corner that is *not* click-through.

**Acceptance criteria:**
- [ ] `DimOverlayWindow` subclass of `NSWindow` with `styleMask: .borderless`
- [ ] `ignoresMouseEvents = true` on the main window
- [ ] Window `level` is `.statusBar` (macOS 14+) or `.screenSaver` (macOS 13) — use `if #available` check
- [ ] `backgroundColor` is `NSColor.black.withAlphaComponent(0.0)` initially
- [ ] `func startEscalation()` animates alpha from `0.0` to `0.5` over 15 seconds using `NSAnimationContext` or `CABasicAnimation`
- [ ] `func liftOverlay()` fades alpha to `0.0` over 300ms and removes the window
- [ ] Creates one window per screen via `NSScreen.screens`
- [ ] Responds to `NSApplication.didChangeScreenParametersNotification` to handle display connect/disconnect
- [ ] "End Session" button is a child `NSPanel` or embedded `NSHostingView` that does NOT ignore mouse events, positioned bottom-right of primary display
- [ ] `collectionBehavior` includes `.canJoinAllSpaces` so overlay works across Spaces/full-screen apps

**Verification:**
- [ ] Manual test: trigger overlay, verify it covers all screens
- [ ] Manual test: verify click-through — can click apps beneath the overlay
- [ ] Manual test: verify "End Session" button is clickable
- [ ] Manual test: verify overlay works when an app is in full-screen mode
- [ ] Build succeeds

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Overlay/DimOverlayWindow.swift`
- `Anchored/Overlay/EndSessionButton.swift` (SwiftUI view)

**Estimated scope:** Medium (2-3 files)

---

#### Task 9: CountdownPill Panel

**Description:** Build the countdown pill — a small capsule panel in the upper-right corner that shows "Focusing… Dimming in Xs" with a live countdown. Fades in cleanly, ticks every second, and fades out when cancelled or when countdown hits zero.

**Acceptance criteria:**
- [ ] `CountdownPillPanel` subclass of `NSPanel` with `styleMask: .borderless`
- [ ] Floating level (above normal windows but below dim overlay)
- [ ] Positioned in upper-right corner of primary display with padding
- [ ] Content is a SwiftUI view via `NSHostingView`: rounded capsule shape, label "Focusing… Dimming in {N}s"
- [ ] Countdown ticks every 1 second via `Timer.scheduledTimer`
- [ ] `func show(seconds: Int, onComplete: @escaping () -> Void)` starts the countdown
- [ ] `func cancel()` stops the timer and fades out over 200ms
- [ ] On countdown reaching 0, calls `onComplete` and fades out
- [ ] Does NOT ignore mouse events — but has no interactive elements (just visual)

**Verification:**
- [ ] Manual test: show pill, verify countdown ticks visually
- [ ] Manual test: switch to non-distraction app before countdown ends, verify pill cancels
- [ ] Build succeeds

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Overlay/CountdownPillPanel.swift`
- `Anchored/Overlay/CountdownPillView.swift` (SwiftUI)

**Estimated scope:** Small (2 files)

---

#### Task 10: ExitTriggerCapsule Panel

**Description:** Build the exit-trigger capsule — a borderless floating panel that slides down from the menu bar position with a spring animation, showing "You just locked in {duration} of focused time in {appName}. Want to protect this momentum?" with [Keep Focused: 25m] and [Taking a Break] buttons. Auto-dismisses after 15 seconds.

**Acceptance criteria:**
- [ ] `ExitTriggerPanel` subclass of `NSPanel` with `styleMask: .borderless`
- [ ] Positioned centered horizontally below the menu bar, anchored to the status item position if available
- [ ] Content is a SwiftUI view via `NSHostingView`: clean card with message, two buttons
- [ ] `func show(duration: TimeInterval, appName: String, onAnchor: @escaping (TimeInterval) -> Void, onDismiss: @escaping () -> Void)`
- [ ] Slide-down entry animation using spring timing (`.spring(response: 0.4, dampingFraction: 0.75)` or AppKit equivalent)
- [ ] Three duration buttons: **[15m]**, **[25m]**, **[45m]** — each calls `onAnchor` with the selected duration in seconds
- [ ] [Taking a Break] button calls `onDismiss` callback
- [ ] Auto-dismiss timer: 15 seconds. If no interaction, slides back up and calls `onDismiss`
- [ ] Audio: plays `.pop` sound on appearance

**Verification:**
- [ ] Manual test: trigger capsule, verify slide-down animation
- [ ] Manual test: click "Keep Focused", verify callback fires
- [ ] Manual test: wait 15 seconds, verify auto-dismiss
- [ ] Build succeeds

**Dependencies:** Task 5 (AudioEngine)

**Files likely touched:**
- `Anchored/Overlay/ExitTriggerPanel.swift`
- `Anchored/Overlay/ExitTriggerView.swift` (SwiftUI)

**Estimated scope:** Medium (2-3 files)

---

#### Task 11: OverlayManager (Coordinator)

**Description:** Build the `OverlayManager` that coordinates the three overlay components (dim overlay, countdown pill, exit-trigger capsule). Conforms to `FocusEngineDelegate` and translates engine events into overlay show/hide calls. Handles the sequencing: distraction detected → show countdown pill → pill expires → start dim escalation → user returns → lift everything.

**Acceptance criteria:**
- [ ] `OverlayManager` conforms to `FocusEngineDelegate`
- [ ] `didRequestExitTrigger(duration:appName:)` → shows `ExitTriggerPanel`, routes button callbacks back to `FocusEngine`
- [ ] `didDetectDistraction(bundleID:)` → shows `CountdownPillPanel` with configured countdown duration, on expiry triggers `DimOverlayWindow.startEscalation()`
- [ ] `didReturnToWork()` → cancels countdown pill if active, lifts dim overlay if active
- [ ] `sessionDidEnd()` → lifts all overlays, hides all panels
- [ ] Only one exit-trigger capsule at a time (debounce rapid app switches)
- [ ] Only one countdown/escalation sequence at a time
- [ ] Configurable `countdownDuration: Int` (default 10, range 5-20)

**Verification:**
- [ ] Integration test: wire `FocusEngine` → `OverlayManager`, simulate a full flow: work → distraction → capsule → anchor → distraction → pill → escalation → return → lift
- [ ] Manual test: verify the full sequence visually
- [ ] Build succeeds

**Dependencies:** Tasks 7, 8, 9, 10

**Files likely touched:**
- `Anchored/Overlay/OverlayManager.swift`

**Estimated scope:** Medium (1 file, but complex coordination logic)

---

### ✅ Checkpoint: Core Loop Works End-to-End

- [ ] All tests pass
- [ ] App can be launched, detects work in a real app (e.g. Xcode), and shows the exit-trigger capsule when switching to Discord
- [ ] Clicking "Keep Focused" anchors a session
- [ ] Switching to a distraction during a session shows the countdown pill
- [ ] Countdown expiry triggers ambient escalation (screen dims)
- [ ] Returning to a non-distraction app lifts the dim overlay immediately
- [ ] Session auto-ends after timer duration
- [ ] **This is the first fully dogfood-able build. Test it yourself before proceeding.**

---

### Phase 4: Menu Bar & Persistence

#### Task 12: MenuBarController

**Description:** Build the menu bar interface — an `NSStatusItem` with an anchor icon, a left-click popover/dropdown showing session state and history, and a right-click context menu with Preferences, Edit Distraction List, and Quit.

**Acceptance criteria:**
- [ ] `MenuBarController` creates an `NSStatusItem` with a monochrome anchor SF Symbol (`anchor.circle`) adapting to light/dark mode
- [ ] Three visual states:
  - Idle: standard icon
  - Watching: same icon (no change — app is silently tracking)
  - Anchored: icon gains a green dot accessory or switches to `anchor.circle.fill`
- [ ] Left-click opens an `NSPopover` or `NSMenu` with:
  - Current session status (if anchored: remaining time, app name, "End Session" button)
  - Recent sessions list (last 5, showing app name + duration + time)
- [ ] Right-click opens `NSMenu` with:
  - "Edit Distraction List…"
  - "Preferences…"
  - "Session History"
  - Separator
  - "Quit Anchored"
- [ ] "End Session" button calls `FocusEngine.endSession()`
- [ ] Menu bar updates reactively when session state changes

**Verification:**
- [ ] Manual test: left-click shows dropdown with session info
- [ ] Manual test: right-click shows context menu
- [ ] Manual test: icon changes when a session is active
- [ ] Manual test: "End Session" terminates the session and lifts overlays
- [ ] Build succeeds

**Dependencies:** Tasks 3, 7

**Files likely touched:**
- `Anchored/MenuBar/MenuBarController.swift`
- `Anchored/MenuBar/MenuBarPopoverView.swift` (SwiftUI)
- `Anchored/MenuBar/SessionHistoryView.swift` (SwiftUI)

**Estimated scope:** Medium (3 files)

---

#### Task 13: Session Logging Integration

**Description:** Wire `SessionStore.log()` calls into the `FocusEngine` at all the correct points: session start, session end, distraction detected, escalation triggered. Ensure all events include the correct metadata. Wire "Session History" menu item to show recent sessions from the store.

**Acceptance criteria:**
- [ ] `session_start` event logged when user clicks "Keep Focused"
- [ ] `session_end` event logged when session timer expires, user clicks "End Session", or app quits during a session
- [ ] `distraction_detected` event logged each time the countdown pill is triggered
- [ ] `escalation_triggered` event logged when the countdown pill reaches zero and dimming begins
- [ ] All events include correct `appBundleID`, `appName`, `focusDurationSeconds`, and `action` fields
- [ ] `url` field is `nil` on all V1 events
- [ ] "Session History" in the right-click menu opens a popover showing the last 20 sessions from `SessionStore`

**Verification:**
- [ ] Manual test: complete a full session, inspect `~/Library/Application Support/Anchored/sessions.json`, verify events are present and well-formed
- [ ] Manual test: verify "Session History" displays real data
- [ ] Build succeeds

**Dependencies:** Tasks 3, 7, 12

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift` (add logging calls)
- `Anchored/MenuBar/MenuBarController.swift` (wire history)
- `Anchored/MenuBar/SessionHistoryView.swift`

**Estimated scope:** Small (edits to 2-3 existing files)

---

#### Task 14: Launch at Login

**Description:** Implement the "Launch at Login" preference using `SMAppService` (macOS 13+). Toggle is exposed in Preferences and in onboarding State 4. Default is ON.

**Acceptance criteria:**
- [ ] Uses `SMAppService.mainApp` to register/unregister as a login item
- [ ] `PreferencesManager` stores the user's preference and syncs with `SMAppService` on changes
- [ ] Default is `true` (registered on first launch after onboarding)
- [ ] Toggling off in Preferences unregisters from login items
- [ ] Gracefully handles errors from `SMAppService` (logs, doesn't crash)

**Verification:**
- [ ] Manual test: enable launch at login, log out and back in, verify app starts
- [ ] Manual test: disable, log out and back in, verify app does NOT start
- [ ] Build succeeds

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Storage/PreferencesManager.swift`

**Estimated scope:** XS (1 file)

---

### ✅ Checkpoint: Feature-Complete Core

- [ ] All tests pass
- [ ] Full behavioral loop works end-to-end with real apps
- [ ] Session events are persisted to JSON and visible in Session History
- [ ] Menu bar icon reflects session state
- [ ] Launch at Login works
- [ ] **Second dogfooding checkpoint.** Use for a full work day before proceeding to onboarding.

---

### Phase 5: Onboarding & Polish

#### Task 15: Onboarding Window (4 States)

**Description:** Build the onboarding flow — a borderless, floating `NSWindow` centered on screen containing a SwiftUI view that transitions through 4 states: Welcome, How It Works, Distraction App Selector, and Preferences & Launch. Only shown on first run.

**Acceptance criteria:**
- [ ] `OnboardingWindow` is a borderless `NSWindow` with `level: .floating`, centered on screen
- [ ] Content is a single SwiftUI view (`OnboardingView`) managing state transitions via an `@State var currentStep: Int`
- [ ] **State 1 (Welcome):** App title, anchor icon, tagline, "Set Up Anchored" button. Tick sound on click.
- [ ] **State 2 (How It Works):** 3-step illustrated explainer with iconographic visuals (SF Symbols), "Next" button
- [ ] **State 3 (Distraction App Selector):** Grid of pill-shaped toggle buttons for default distraction apps (pre-selected) and suggested apps (unselected). "Add another app…" text field with autocomplete from `/Applications`. Writes selections to `DistractionListManager`. "Next" button.
- [ ] **State 4 (Preferences & Launch):** Countdown duration segmented control (5/10/15/20s), focus threshold segmented control (5/10/15/30 min), Launch at Login toggle (default on). "Save & Launch Anchored" button.
- [ ] State transitions use horizontal slide animations
- [ ] "Save & Launch" → writes preferences, registers login item, plays chime, scales card down + fades out, closes window, sets `hasCompletedOnboarding = true` in UserDefaults

**Verification:**
- [ ] Manual test: delete UserDefaults key, relaunch app, verify onboarding appears
- [ ] Manual test: complete all 4 states, verify preferences are saved correctly
- [ ] Manual test: verify distraction list selections persist
- [ ] Manual test: verify card dismissal animation
- [ ] Build succeeds

**Dependencies:** Tasks 4, 5, 14

**Files likely touched:**
- `Anchored/Onboarding/OnboardingWindow.swift`
- `Anchored/Onboarding/OnboardingView.swift` (SwiftUI)
- `Anchored/Onboarding/WelcomeStepView.swift` (SwiftUI)
- `Anchored/Onboarding/HowItWorksStepView.swift` (SwiftUI)
- `Anchored/Onboarding/DistractionSelectorView.swift` (SwiftUI)
- `Anchored/Onboarding/PreferencesStepView.swift` (SwiftUI)

**Estimated scope:** Large (6 files — but all SwiftUI views, well-scoped)

---

#### Task 16: AppDelegate Integration & First-Run Detection

**Description:** Wire everything together in `AppDelegate`. On launch: check `hasCompletedOnboarding`. If false, show onboarding window. If true, silently start the engine and menu bar. Connect `FocusEngine` → `OverlayManager` → `MenuBarController` delegation chain.

**Acceptance criteria:**
- [ ] `AppDelegate.applicationDidFinishLaunching` checks `UserDefaults.hasCompletedOnboarding`
- [ ] First run → shows `OnboardingWindow`, does NOT start engine until onboarding completes
- [ ] Subsequent runs → initializes `MenuBarController`, `FocusEngine`, `AppSwitchMonitor`, `OverlayManager`, and starts monitoring immediately
- [ ] `FocusEngine.delegate` is set to `OverlayManager`
- [ ] `OverlayManager` holds references to `FocusEngine` for callbacks (anchor, dismiss, end session)
- [ ] `MenuBarController` can access `FocusEngine` for session state and `DistractionListManager` for editing
- [ ] Clean teardown on `applicationWillTerminate`: stop monitor, end active session (log event), save state
- [ ] Onboarding completion callback triggers full engine startup

**Verification:**
- [ ] Manual test: fresh install → onboarding → complete → engine starts → full loop works
- [ ] Manual test: subsequent launch → no onboarding → engine starts immediately
- [ ] Manual test: quit app during active session → session_end event is logged
- [ ] Build succeeds

**Dependencies:** Tasks 7, 11, 12, 15

**Files likely touched:**
- `Anchored/App/AppDelegate.swift`

**Estimated scope:** Medium (1 file, but critical integration logic)

---

#### Task 17: Audio Hookup & Final Polish

**Description:** Wire audio cues into all interaction points. Address edge cases: multi-display overlay behavior, full-screen Spaces, rapid app-switching debounce, and Anchored detecting itself as a distraction (exclude own bundle ID).

**Acceptance criteria:**
- [ ] `.tick` sound plays on onboarding button clicks
- [ ] `.pop` sound plays when exit-trigger capsule appears
- [ ] `.chime` sound plays when user anchors a session and when onboarding completes
- [ ] Anchored's own bundle ID is excluded from distraction detection (prevent self-triggering when clicking overlays)
- [ ] Overlay `collectionBehavior` includes `.canJoinAllSpaces` and `.fullScreenAuxiliary` for full-screen coverage
- [ ] Rapid app switches (e.g., CMD+Tab through multiple apps in <1 second) don't produce multiple capsules — debounce to only consider the final settled app after 500ms
- [ ] Menu bar "Edit Distraction List…" opens a floating panel reusing the `DistractionSelectorView` from onboarding
- [ ] Menu bar "Preferences…" opens a floating panel reusing the `PreferencesStepView` from onboarding

**Verification:**
- [ ] Manual test: hear correct sounds at all interaction points
- [ ] Manual test: rapid CMD+Tab through 5 apps → no capsule spam
- [ ] Manual test: enter full-screen Xcode, switch to full-screen Discord, verify overlay covers the screen
- [ ] Manual test: connect/disconnect external display during a dimming session, verify overlay adjusts
- [ ] Full end-to-end test of the complete V1 feature set
- [ ] Build succeeds with zero warnings

**Dependencies:** Tasks 5, 11, 15, 16

**Files likely touched:**
- `Anchored/Overlay/OverlayManager.swift` (add audio calls)
- `Anchored/Overlay/ExitTriggerPanel.swift` (add audio)
- `Anchored/Engine/FocusEngine.swift` (add debounce, exclude self)
- `Anchored/Overlay/DimOverlayWindow.swift` (collection behavior)
- `Anchored/MenuBar/MenuBarController.swift` (wire edit/prefs panels)

**Estimated scope:** Medium (edits to 5 existing files)

---

### ✅ Checkpoint: V1 Complete

- [ ] All unit tests pass
- [ ] `xcodebuild -scheme Anchored build` succeeds with zero warnings
- [ ] Fresh install → onboarding → full behavioral loop works end-to-end
- [ ] Session data persists across app restarts
- [ ] Audio plays at all interaction points
- [ ] Full-screen and multi-display scenarios work
- [ ] Rapid app switching is debounced
- [ ] App launches at login when enabled
- [ ] **Dogfood for 3+ days before considering release.**

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `NSWorkspace` notifications don't fire for certain system apps (e.g., Spotlight, Notification Center) | Low | These aren't distraction apps. Ignore unknown bundle IDs gracefully. |
| Dim overlay doesn't cover full-screen Spaces on macOS 13 | High | Test `.canJoinAllSpaces` + `.fullScreenAuxiliary` on macOS 13 specifically. If `.statusBar` level doesn't work, fall back to `.screenSaver`. This is the highest-risk technical unknown. |
| Spring animations on `NSPanel` are janky or unavailable | Med | SwiftUI `.animation(.spring(...))` within `NSHostingView` handles this. If AppKit-level window position animation is needed, fall back to `NSAnimationContext` with ease-in-out. |
| App name resolution from bundle ID fails for some apps | Low | `NSRunningApplication.localizedName` is the primary source. Fall back to bundle ID string if `nil`. |
| Sound assets not available or too quiet | Low | Start with `NSSound(named:)` system sounds (e.g., `"Tink"`, `"Pop"`, `"Glass"`). Replace with custom assets later if needed. |
| Users don't understand the exit-trigger prompt | Med | The prompt copy is carefully worded. If dogfooding reveals confusion, add a subtitle: "Anchored noticed you were focused. Start a session to stay locked in." |
| `/Applications` scanning for autocomplete is slow | Low | Use `FileManager.contentsOfDirectory` with `.app` filter. Cache results. Only scan when the text field gains focus. |

## Parallelization Opportunities

**Safe to parallelize (no shared state):**
- Tasks 2, 4, 5 can all run in parallel after Task 1 is complete
- Tasks 8, 9, 10 can all run in parallel after Task 1 (they're independent overlay windows)
- Unit tests for models, storage, and engine are independent

**Must be sequential:**
- Task 7 (FocusEngine) depends on Tasks 3, 4, 6
- Task 11 (OverlayManager) depends on Tasks 7, 8, 9, 10
- Task 16 (AppDelegate) depends on nearly everything
- Task 17 (Polish) must be last

**Suggested parallel execution groups (if multiple agents available):**

| Agent A | Agent B | Agent C |
|---|---|---|
| Task 1 (scaffold) | — | — |
| Task 2 (models) | Task 4 (distraction list) | Task 5 (audio) |
| Task 3 (session store) | Task 6 (monitor) | Task 8 (dim overlay) |
| Task 7 (focus engine) | Task 9 (countdown pill) | Task 10 (exit trigger) |
| Task 11 (overlay manager) | Task 12 (menu bar) | Task 14 (login item) |
| Task 13 (logging) | Task 15 (onboarding) | — |
| Task 16 (integration) | — | — |
| Task 17 (polish) | — | — |

## Resolved Design Decisions

- [x] **Sound assets:** Custom `.caf` sound files, designed and bundled from Day 1. Polish matters — this is a premium-feel utility, not a prototype. Task 5 updated to include sound design/sourcing.
- [x] **Exit-trigger duration options:** Three buttons: **[15m] [25m] [45m]**. Gives flexibility without overwhelming. Task 10 updated.
- [x] **Focus threshold default:** **10 minutes.** Balanced — catches most real work sessions without triggering on brief app visits. Task 7 updated (`focusThreshold` default = 600s).



================================================================================
FILE: anchored-v1.md
SIZE: 20591
================================================================================

# Anchored — Ghost Mode

## Problem Statement
**How might we** help knowledge workers stay in flow without requiring them to manually start a focus session, grant invasive permissions, or fight an aggressive blocker they'll just disable?

## Recommended Direction

**Ghost Mode → Permission Gate (Direction B)**

Anchored V1 ships as a zero-configuration, zero-permission macOS menu bar utility. It uses `NSWorkspace` notifications to passively detect app switches — no Accessibility API, no onboarding friction, no privacy prompts. The app is invisible until the moment it matters.

The core behavioral loop:

1. User opens a work app (Xcode, Figma, VS Code). Anchored silently watches.
2. User eventually switches away to a distraction app (Discord, Messages, Steam). Anchored catches the exit.
3. A clean capsule drops from the menu bar: *"You just locked in 32 minutes of focused time in Xcode. Want to protect this momentum?"* with **[Keep Focused: 25m]** and **[Taking a Break]**.
4. If the user anchors, and later strays to a distraction app, a countdown pill appears: *"Focusing… Dimming in 10s."* If they don't return, the screen gradually dims from 0% → 50% opacity over 15 seconds (ambient escalation).
5. The dim overlay is click-through (`ignoresMouseEvents = true`) — the user can still navigate back to work through the overlay, and the dim lifts the moment a non-distraction app regains focus.

**Why this wins:** It eliminates the three failure modes of existing tools:
- **vs. Cold Turkey / Focus:** Not aggressive enough to trigger override impulse — the dim is gentle friction, not a wall.
- **vs. Pomodoro timers:** No ritual to start. The trigger happens at the *exit*, validating work already done rather than demanding a commitment upfront.
- **vs. Screen Time:** Not passive — the ambient escalation has real visual teeth that are hard to ignore.

**V2 upgrade path:** After the user completes ~10 sessions, Anchored surfaces a one-time prompt: *"Want Anchored to track distracting websites too? This requires Accessibility access."* The browser blind spot (Chrome/Safari are neutral in V1) becomes the natural conversion trigger — users who love the app-level blocking will *want* URL-level awareness. The limitation is the upgrade funnel.

---

## Onboarding Flow (4 States)

The onboarding is hosted inside a standalone, borderless floating card centered on the screen. Despite the "zero-config" philosophy, onboarding exists to **educate the user on how the app works** (since it's invisible by default) and to let them customize their distraction list. Target completion: under 30 seconds.

### State 1: Welcome & Value Proposition

| Element | Detail |
|---|---|
| **Visual** | High-contrast app title "Anchored", clean vector monochrome anchor icon, one-line summary: *"Focus without the ritual. Anchored watches your workflow and gently keeps you locked in."* |
| **Primary Action** | Single prominent **"Set Up Anchored"** button |
| **Audio** | Low-frequency tactile "tick" on button click |
| **Transition** | Button press → slide to State 2 |

### State 2: How It Works (Visual Explainer)

> [!NOTE]
> This replaces the original spec's "Permission Handshake" state. In V1, there are no permissions to request. This state builds user confidence by explaining the invisible behavior model.

| Element | Detail |
|---|---|
| **Visual** | A 3-step illustrated sequence (simple iconographic, not animated): |
| | **Step 1:** App icon in menu bar + work app icon → *"Anchored watches when you're in your work apps."* |
| | **Step 2:** Exit arrow + capsule notification → *"When you step away, it asks if you want to protect your momentum."* |
| | **Step 3:** Dim overlay gradient → *"If you stray during a session, the screen gently dims to nudge you back."* |
| **Secondary Copy** | *"No passwords. No permissions. No data leaves your Mac."* |
| **Primary Action** | **"Next"** button |
| **Audio** | Subtle page-turn sound on transition |

### State 3: Distraction App Selector

| Element | Detail |
|---|---|
| **Objective** | Define which apps trigger the nudge. Note: this is an **inverted model** from the original spec — instead of defining "work apps," the user defines "distraction apps." This is simpler because the distraction list is shorter, more universal, and doesn't require the user to think about their entire toolchain. |
| **UI** | A clean grid of pill-shaped buttons showing common distraction apps, pre-selected by default: |
| | **Pre-selected:** Discord, Slack, Messages, Telegram, Twitter/X, Steam, Spotify, Music |
| | **Unselected suggestions:** WhatsApp, Notion, Obsidian, Mail, Calendar |
| **Interaction** | Tap to toggle. Pills light up when active (distraction), dim when excluded. |
| **Custom Add** | Small text entry bar at the bottom: *"Add another app…"* with `.app` bundle autocomplete from `/Applications`. |
| **Primary Action** | **"Next"** button |

### State 4: Preferences & Launch

| Element | Detail |
|---|---|
| **Countdown Duration** | Slider or segmented control: **5s / 10s (default) / 15s / 20s** — how long the "Dimming in Xs" pill counts down before ambient escalation begins. |
| **Focus Threshold** | Minimum continuous work time before the exit-trigger fires: **5 min / 10 min / 15 min (default) / 30 min**. Prevents the capsule from appearing every time the user briefly opens Xcode to check something. |
| **Launch at Login** | Toggle, default **on**. |
| **Primary Action** | **"Save & Launch Anchored"** → Card scales down slightly with a spring animation, fades out, app drops silently into the menu bar. |
| **Audio** | Warm success chime on launch. |

---

## Core Engine — V1 Functional Spec

### A. App Switch Monitor (Zero Permissions)

```
Source: NSWorkspace.shared.notificationCenter
Event:  NSWorkspace.didActivateApplicationNotification
Data:   NSRunningApplication.bundleIdentifier
```

- Runs as `LSUIElement` (no Dock icon, menu bar only).
- On every app switch, the engine receives the new foreground app's bundle ID.
- The engine maintains two internal states:
  - `currentApp: BundleID` — what's in the foreground right now.
  - `workSessionStart: Date?` — when the user first entered a non-distraction app.

**Decision logic per app switch:**

```
let incoming = notification.bundleIdentifier

if incoming is in distractionList:
    if activeSession exists:
        → show countdown pill, begin ambient escalation sequence
    else if workSessionStart != nil AND elapsed > focusThreshold:
        → show exit-trigger capsule ("Want to protect this momentum?")
    else:
        → do nothing (brief work stint, not worth prompting)
    workSessionStart = nil

else: // incoming is a non-distraction app (work or neutral)
    if workSessionStart == nil:
        workSessionStart = now
    if activeSession exists AND was dimming:
        → cancel escalation, lift overlay immediately
```

### B. Exit-Trigger Capsule

- **Appearance:** Borderless, floating `NSPanel` anchored to the menu bar icon position. Slides down with a tight spring animation + subtle audio pop.
- **Content:**
  - *"You just locked in {duration} of focused time in {appName}. Want to protect this momentum?"*
  - **[Keep Focused: 25m]** — Starts a 25-minute anchored session. The time already spent counts retroactively.
  - **[Taking a Break]** — Dismisses. No session created. Resets `workSessionStart`.
- **Auto-dismiss:** If the user ignores the capsule for 15 seconds, it slides back up and away. No session created.
- **Data logged:** `{ timestamp, appBundleID, focusDuration, action: "anchored" | "dismissed" | "timeout", url: nil }` — note the `url: nil` field is architecturally present for V2.

### C. Countdown Pill

- **Trigger:** User switches to a distraction app while an active session exists.
- **Appearance:** Small, tight capsule in the upper-right corner of the primary display. No spring animation — just a clean fade-in.
- **Content:** *"Focusing… Dimming in 10s"* with a countdown that ticks every second.
- **Behavior:**
  - If user switches back to a non-distraction app before countdown hits 0 → pill fades out, no escalation.
  - If countdown reaches 0 → pill fades out, ambient escalation begins.

### D. Ambient Escalation Overlay

- **Window type:** `NSWindow`, `borderless`, `level: .statusBar` (macOS 14+) or `.screenSaver` (macOS 13).
- **Coverage:** Spans all connected displays. One window per screen via `NSScreen.screens`.
- **Input:** `ignoresMouseEvents = true` — fully click-through. User can interact with everything beneath.
- **Animation:** Opacity ramps from `0.0` → `0.5` over 15 seconds using a smooth ease-in curve.
- **Branding:** Tiny "⚓ Anchored" text + "End Session" clickable link in the bottom-right corner of the primary display. This element does **not** ignore mouse events.
- **Lift condition:** The moment `NSWorkspace` reports a non-distraction app gaining focus, the overlay fades out over 300ms and is removed.

### E. Menu Bar Interface

- **Icon:** Monochrome anchor glyph (SF Symbol `anchor` or custom asset), adapting to light/dark mode.
- **States:**
  - *Idle:* Standard anchor icon. Left-click opens a minimal dropdown showing session history (last 5 sessions, duration + app name).
  - *Watching:* Same icon, no visual change. App is silently tracking but no session is active.
  - *Anchored:* Anchor icon gains a small green dot indicator. Dropdown shows remaining session time, "End Session" button.
- **Right-click menu:**
  - Edit Distraction List… (opens the pill-grid editor from onboarding State 3)
  - Preferences… (countdown duration, focus threshold, launch at login)
  - Session History (last 20 sessions)
  - Quit Anchored

### F. Session Data Layer

All session data is stored locally in `~/Library/Application Support/Anchored/sessions.json` (or SQLite for V2).

**Schema per event:**

```json
{
  "id": "uuid",
  "timestamp": "ISO-8601",
  "type": "session_start | session_end | distraction_detected | escalation_triggered",
  "appBundleID": "com.apple.dt.Xcode",
  "appName": "Xcode",
  "url": null,
  "focusDurationSeconds": 1920,
  "sessionDurationSeconds": 1500,
  "distractionAppBundleID": "com.hnc.Discord",
  "action": "anchored | dismissed | timeout | escalated | returned"
}
```

> [!IMPORTANT]
> The `url` field is `null` in V1 but structurally present in every event. This is the architectural seam for V2's browser URL tracking. When the Accessibility permission is granted, the `BrowserURLMonitor` module populates this field without any schema migration.

---

## Architecture — V2 Readiness

### Module Boundaries

```
┌─────────────────────────────────────────────────┐
│                   AppDelegate                   │
│              (NSApplicationDelegate)            │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────┐   ┌────────────────────────┐  │
│  │  Onboarding  │   │    MenuBarController   │  │
│  │   Window     │   │                        │  │
│  └──────────────┘   └────────────────────────┘  │
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │         FocusEngine (Core)              │    │
│  │                                         │    │
│  │  ┌────────────────────────────────────┐ │    │
│  │  │  ActivityMonitor «protocol»        │ │    │
│  │  │                                    │ │    │
│  │  │  ├─ AppSwitchMonitor (V1)          │ │    │
│  │  │  │   NSWorkspace notifications     │ │    │
│  │  │  │                                 │ │    │
│  │  │  └─ BrowserURLMonitor (V2)         │ │    │
│  │  │      AppleScript + AXUIElement     │ │    │
│  │  └────────────────────────────────────┘ │    │
│  │                                         │    │
│  │  ┌──────────────┐  ┌─────────────────┐  │    │
│  │  │ SessionStore │  │ DistractionList │  │    │
│  │  │  (JSON/SQL)  │  │ (UserDefaults)  │  │    │
│  │  └──────────────┘  └─────────────────┘  │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │         OverlayManager                  │    │
│  │                                         │    │
│  │  ├─ ExitTriggerCapsule (NSPanel)        │    │
│  │  ├─ CountdownPill (NSPanel)             │    │
│  │  └─ DimOverlay (NSWindow per screen)    │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │         AudioEngine                     │    │
│  │  (Preloaded .caf system sounds)         │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
└──────────────────────────────────────────────-──┘
```

### The `ActivityMonitor` Protocol (V2 Seam)

```swift
protocol ActivityMonitor {
    /// Fires when the foreground context changes.
    /// - bundleID: always present
    /// - url: nil in V1, populated when BrowserURLMonitor is active
    var onContextChange: ((bundleID: String, url: URL?)) -> Void { get set }
}
```

V1 ships with `AppSwitchMonitor` as the sole conformance. V2 adds `BrowserURLMonitor` which wraps `AppSwitchMonitor` and enriches events with URL data when the active app is a known browser. The `FocusEngine` never knows which monitor is active — it just receives `(bundleID, url?)` tuples.

---

## Key Assumptions to Validate

- [ ] **Users will engage with the exit-trigger capsule rather than dismissing/ignoring it.** Test: ship V1, measure accept vs. dismiss vs. timeout ratio across first 50 sessions. If >60% timeout, the capsule is invisible or poorly timed. Adjust threshold or presentation.
- [ ] **The hardcoded distraction list defaults match real user behavior.** Test: track which apps trigger escalation vs. which the user adds/removes in preferences. If >30% of users edit the list in the first week, the defaults are wrong.
- [ ] **Ambient escalation feels like a feature, not a bug.** Test: the countdown pill ("Dimming in 10s") is the mitigation. If users still report confusion, add a first-time-only tooltip explaining what's happening.
- [ ] **The "browser as neutral" model is acceptable for V1.** Test: monitor how many support requests or GitHub issues mention browser-based distractions. When this becomes the #1 request, ship V2 with the permission gate.
- [ ] **Reddit/HN audience cares about "zero permissions" as a differentiator.** Test: A/B the launch post headline. Lead with behavior ("it watches you work and only shows up when you stray") vs. architecture ("zero permissions required"). See which gets traction.

## MVP Scope

**In (V1 — Ghost Mode):**
- 4-state onboarding flow (welcome → explainer → distraction list → preferences)
- `NSWorkspace`-based app switch monitoring (zero permissions)
- Exit-trigger capsule with retroactive session anchoring
- Countdown pill (configurable 5–20s)
- Ambient escalation overlay (0% → 50% over 15s, click-through)
- Menu bar icon with session state, history, and quick-edit distraction list
- Local session event logging with `url: null` field present
- `ActivityMonitor` protocol for V2 extensibility
- Audio feedback (tick, pop, chime) via preloaded system sounds
- macOS 13.0+ (Ventura) minimum deployment target
- AppKit `NSApplicationDelegate` + `NSHostingView` for SwiftUI content
- Open-source, GitHub-distributed, independent signed build

**In (V2 — Permission Gate):**
- Optional Accessibility permission unlock (prompted after ~10 sessions)
- `BrowserURLMonitor` module (Chromium AppleScript, Safari AppleScript, Firefox AXUIElement)
- Browser URL-aware distraction detection (specific domains, not whole browsers)
- Work profile presets (Coding, Video, Writing, Custom)
- Session history replay timeline
- Session statistics & analytics dashboard (daily/weekly focus time, distraction frequency, streak tracking — all local data already captured by V1's logging layer)
- SQLite migration for session storage

## Not Doing (and Why)

- **macOS 11–12 support** — <5% of Apple Silicon users. The engineering cost (window level fallbacks, animation easing workarounds, SF Symbol compatibility shims) is massive relative to audience. macOS 13+ covers 95%+ of target users.
- **Cross-device phone tethering** — High-friction solution for users who lack the discipline to use it. A QR-code-to-web-timer asks for voluntary disarmament from the exact person who can't stop scrolling. Cut entirely.
- **Fishbowl visual ring** — Requires real-time AXUIElement window coordinate tracking for third-party apps. Causes visual stutter, high CPU overhead, and is architecturally fragile across macOS versions. Not worth the cost.
- **Browser URL tracking in V1** — The single most complex subsystem (AppleScript per browser engine, AXUIElement for Firefox, permission gate UX). Deferring it makes V1 shippable in weeks instead of months and creates a natural V2 upgrade trigger.
- **Session statistics / analytics dashboard in V1** — The data is logged from Day 1, but the visualization UI is deferred to V2. Shipping the dashboard before the core loop is proven adds build time without validating the core assumption.
- **iOS companion app** — Entirely different platform, different distribution model, different codebase. Not in scope until the Mac app has proven product-market fit.
- **Complex work profile system in V1** — Profiles only become meaningful when the app can distinguish between work-Safari and distraction-Safari. Without URL tracking, profiles add configuration complexity with no functional benefit. Deferred to V2.

## Open Questions

- **What's the right focus threshold default?** The spec says 15 minutes, but real-world testing might show that 10 minutes (or even 5) catches more genuine work sessions. Needs dogfooding.
- **Should the exit-trigger capsule offer variable durations?** Current design shows `[Keep Focused: 25m]`. Should this be `[15m] [25m] [45m]` or a freeform input? More options = more friction at the decision point.
- **How should Anchored handle full-screen apps?** If the user is in full-screen Xcode and swipes to a full-screen Chrome Space, the dim overlay needs to work across Spaces. Needs technical investigation on `NSWindow.collectionBehavior` settings.
- **App distribution model:** Direct `.dmg` download from GitHub releases? Homebrew cask? Both? The "independent signed build" note in the original spec implies notarization with a Developer ID — is that available, or will users need to right-click → Open to bypass Gatekeeper?
- **Sound design:** The spec references "mechanical tick," "audio pop," and "warm chime." Are these custom sound assets to be designed, or adapted from system sounds (`NSSound`)? Custom sounds add polish but require audio design work.



================================================================================
FILE: anchored-v2-plan.md
SIZE: 17231
================================================================================

# Implementation Plan: Anchored V2

## Overview

Build the Anchored V2 upgrade: transforming the app from a simple app-level focus guard into a full context-aware focus engine. V2 introduces a Permission Gate for browser URL tracking, customizable Work Profiles with domain-level blocking, an SQLite-backed Focus Dashboard for session analytics, and Smart Auto-Triggers for proactive focus nudges.

**Source spec:** [anchored-v2.md](file:///Users/varun/Development/Anchor/docs/ideas/anchored-v2.md)

## Architecture Decisions

- **Data Storage:** Migrate from flat JSON to SQLite to support aggregation queries for the new Focus Dashboard without loading everything into memory.
- **Browser Automation:** Use AppleScript for Chromium/Safari and `AXUIElement` for Firefox to read URLs, avoiding the need for invasive browser extensions.
- **URL Polling Strategy:** Use a 2.5s polling loop when a browser is the foreground app, rather than hooking into low-level accessibility events, to minimize CPU overhead and battery impact.
- **Trust via Progressive Disclosure:** System accessibility permissions are only requested after 10 successful sessions (the "Permission Gate") to ensure the user has experienced the core value loop first.

## Dependency Graph

```mermaid
graph TD
    A[SQLite Migration] --> B[Dashboard SQL Queries]
    A --> C[ProfileManager]
    C --> D[Preferences UI]
    C --> E[Menu Bar Switcher]
    C --> F[FocusEngine Update]
    G[PermissionGate] --> H[BrowserURLMonitor Loop]
    H --> I[Chromium/Safari AppleScript]
    H --> J[Firefox AXUIElement]
    H --> K[URL Domain Parser]
    I --> F
    J --> F
    K --> F
    B --> L[Dashboard Window]
    L --> M[Timeline Views]
    C --> N[ShadowTrackingEngine]
    N --> O[Sleep/Wake Observers]
    N --> P[Smart Nudges]
```

## Task List

---

### Phase 1: Storage Migration & Foundation

#### Task 1: SQLite Dependency Setup & Model Updates

**Description:** Add the SQLite dependency (GRDB or lightweight wrapper) to the Xcode project. Update the `SessionEvent` model to include `url: String?` and `distraction_domain: String?` fields to support V2 requirements.

**Acceptance criteria:**
- [ ] SQLite dependency is linked and builds successfully.
- [ ] `SessionEvent` model is updated and conforms to standard `Codable`.

**Verification:**
- [ ] Build succeeds: `xcodebuild -scheme Anchored build`
- [ ] Manual check: verify imports for SQLite work.

**Dependencies:** None

**Files likely touched:**
- `Anchored.xcodeproj`
- `Anchored/Models/SessionEvent.swift`

**Estimated scope:** XS (Project config + 1 file)

---

#### Task 2: SQLite Schema & Core CRUD Operations

**Description:** Build the new `SQLiteSessionStore` class that initializes the `anchored.db` file, creates the `sessions` table (with indexes on timestamp and type), and implements the `insert` and `fetchRecent` operations.

**Acceptance criteria:**
- [ ] `sessions` table is created on init if it doesn't exist.
- [ ] Indexes are correctly established.
- [ ] `func log(_ event: SessionEvent)` performs a SQL INSERT.
- [ ] `func recentSessions(limit: Int)` performs a SQL SELECT ordered by timestamp descending.

**Verification:**
- [ ] Unit test: Insert 5 events, fetch 3, verify order.
- [ ] Build succeeds.

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Storage/SQLiteSessionStore.swift`
- `AnchoredTests/Storage/SQLiteSessionStoreTests.swift`

**Estimated scope:** Medium (2 files)

---

#### Task 3: JSON to SQLite Migration Logic

**Description:** Implement the first-launch migration logic. The system must read the legacy `sessions.json` file, parse all events, perform a bulk INSERT into SQLite, and then rename the JSON file to `sessions.json.migrated` as a backup.

**Acceptance criteria:**
- [ ] `func migrateFromJSONIfNeeded()` safely moves all legacy data to SQLite.
- [ ] Does not duplicate data on subsequent launches.
- [ ] Gracefully handles missing or corrupted JSON files.
- [ ] Renames the original JSON file to prevent re-migration.

**Verification:**
- [ ] Unit test: Provide a mock JSON file, run migration, verify SQLite row count matches, verify file is renamed.
- [ ] Build succeeds.

**Dependencies:** Task 2

**Files likely touched:**
- `Anchored/Storage/SQLiteSessionStore.swift`

**Estimated scope:** Small (1 file)

---

### ✅ Checkpoint: Foundation

- [ ] All unit tests pass.
- [ ] App launches, migrates existing JSON data flawlessly to SQLite.
- [ ] V1 functionality works identically using the SQLite backend.

---

### Phase 2: Profile Management

#### Task 4: WorkProfile Model & ProfileManager

**Description:** Define the `WorkProfile` struct (name, distractionApps, distractionDomains, allowedDomains) and build the `ProfileManager` that serializes these to `UserDefaults` and maintains the active profile state.

**Acceptance criteria:**
- [ ] `WorkProfile` is `Codable`.
- [ ] `ProfileManager` provides default profiles (Coding, Writing, Video).
- [ ] `func switchProfile(to name: String)` updates the active profile.
- [ ] Emits updates so the rest of the app can react dynamically.

**Verification:**
- [ ] Unit test: Verify default profiles initialize and serialize correctly.
- [ ] Build succeeds.

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Models/WorkProfile.swift`
- `Anchored/Engine/ProfileManager.swift`

**Estimated scope:** Small (2 files)

---

#### Task 5: Preferences UI - Profile & App Editor

**Description:** Build the split-panel Preferences UI. Implement the left sidebar for selecting/creating profiles, and the right panel section for adding/removing Distraction Apps.

**Acceptance criteria:**
- [ ] Profiles can be selected and edited.
- [ ] App selector UI (similar to V1 onboarding) works for the active profile.
- [ ] Changes immediately save to `ProfileManager`.

**Verification:**
- [ ] Manual check: Open preferences, edit a profile, close and reopen, verify changes persist.

**Dependencies:** Task 4

**Files likely touched:**
- `Anchored/App/PreferencesWindow.swift`
- `Anchored/App/Views/ProfileEditorView.swift`

**Estimated scope:** Medium (3 files)

---

#### Task 6: Preferences UI - Domain Editor

**Description:** Expand the Preferences UI to include text-entry fields for adding/removing `distractionDomains` and `allowedDomains` for the currently selected Work Profile.

**Acceptance criteria:**
- [ ] Users can type domains (e.g. `youtube.com`) and add them to either list.
- [ ] Domains can be removed.
- [ ] UI prevents adding the same domain to both lists simultaneously.

**Verification:**
- [ ] Manual check: Add `twitter.com` to distractions, verify UI updates.

**Dependencies:** Task 5

**Files likely touched:**
- `Anchored/App/Views/DomainEditorView.swift`

**Estimated scope:** Small (1 file)

---

#### Task 7: FocusEngine Profile Integration & Menu Bar

**Description:** Refactor `FocusEngine` to check the active profile's `distractionApps` instead of the global V1 list. Add the quick-switch profile menu to the Menu Bar dropdown.

**Acceptance criteria:**
- [ ] `FocusEngine` observes `ProfileManager` for updates mid-session.
- [ ] Menu Bar right-click shows "Switch Profile > [List of Profiles]".
- [ ] Active profile name is displayed in the menu bar popover.

**Verification:**
- [ ] Manual check: Start session, block app X. Switch profile where app X is allowed, verify overlay lifts immediately.

**Dependencies:** Task 4, Task 6

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/MenuBar/MenuBarController.swift`

**Estimated scope:** Medium (3 files)

---

### ✅ Checkpoint: Profiles

- [ ] Users can edit distinct work profiles.
- [ ] Menu bar allows quick switching.
- [ ] Core blocking rules respect the newly selected profile.

---

### Phase 3: Browser URL Monitoring

#### Task 8: PermissionGateManager State & Prompt UI

**Description:** Build the `PermissionGateManager` that tracks session counts. Build the floating prompt that asks for system Accessibility access exactly after the 10th session.

**Acceptance criteria:**
- [ ] Prompt appears exactly once after 10 sessions.
- [ ] Button opens macOS Privacy -> Accessibility pane.
- [ ] App polls `AXIsProcessTrusted()` and auto-dismisses prompt when granted with a chime.

**Verification:**
- [ ] Manual check: Hack session count to 10, verify prompt triggers.

**Dependencies:** Task 4

**Files likely touched:**
- `Anchored/Engine/PermissionGateManager.swift`
- `Anchored/Overlay/PermissionPromptWindow.swift`

**Estimated scope:** Medium (2 files)

---

#### Task 9: BrowserURLMonitor Core & Polling Loop

**Description:** Implement `BrowserURLMonitor` conforming to `ActivityMonitor`. It runs a 2.5s timer loop *only* when a supported browser is the frontmost app.

**Acceptance criteria:**
- [ ] Timer starts when browser gains focus.
- [ ] Timer stops instantly when non-browser gains focus.
- [ ] Emits `onContextChange` only if the URL domain has changed since last poll.

**Verification:**
- [ ] Manual check: Console logging confirms polling stops in Xcode and starts in Chrome.

**Dependencies:** Task 8

**Files likely touched:**
- `Anchored/Engine/BrowserURLMonitor.swift`

**Estimated scope:** Small (1 file)

---

#### Task 10: AppleScript Chromium & Safari Strategies

**Description:** Implement the `NSAppleScript` fetching logic for Chrome, Arc, Edge, Brave, and Safari. Include error handling for Safari if "Allow JavaScript from Apple Events" is disabled.

**Acceptance criteria:**
- [ ] Accurately fetches the active tab URL for all Chromium browsers.
- [ ] Accurately fetches Safari URL.
- [ ] Safari error triggers a one-time tooltip guiding the user to the Develop menu.

**Verification:**
- [ ] Manual check: Open Chrome and Safari, verify URLs log correctly.

**Dependencies:** Task 9

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`

**Estimated scope:** Medium (1 file, testing required)

---

#### Task 11: Firefox AXUIElement Strategy

**Description:** Implement the accessibility tree-walking logic for Firefox to locate the address bar `AXTextField` and extract its value.

**Acceptance criteria:**
- [ ] Accurately fetches URL from Firefox without AppleScript.
- [ ] Uses heuristic role-matching to survive minor Firefox UI updates.

**Verification:**
- [ ] Manual check: Open Firefox, verify URL logs correctly.

**Dependencies:** Task 9

**Files likely touched:**
- `Anchored/Engine/FirefoxStrategy.swift`

**Estimated scope:** Medium (1 file, complex APIs)

---

#### Task 12: URL Parser & FocusEngine Integration

**Description:** Write the domain parsing logic (subdomain handling). Update `FocusEngine` to consume URL events, matching them against the active profile's `distractionDomains` and `allowedDomains`.

**Acceptance criteria:**
- [ ] Subdomain matching works (e.g. profile blocks `youtube.com`, monitor catches `m.youtube.com`).
- [ ] `FocusEngine` triggers countdown pill for distractions.
- [ ] `FocusEngine` lifts overlay for allowed domains.
- [ ] Unlisted domains are treated as neutral.

**Verification:**
- [ ] Unit test: Domain matching logic.
- [ ] Manual check: Open blocked URL -> pill appears. Open allowed URL -> pill disappears.

**Dependencies:** Task 10, Task 11, Task 7

**Files likely touched:**
- `Anchored/Engine/URLMatcher.swift`
- `Anchored/Engine/FocusEngine.swift`

**Estimated scope:** Medium (2 files)

---

### ✅ Checkpoint: Context Awareness

- [ ] Browser tracking works efficiently.
- [ ] CPU usage remains under 2% during active polling.
- [ ] In-browser tab switches trigger the correct overlay states within 2.5 seconds.

---

### Phase 4: Focus Dashboard

#### Task 13: Dashboard SQL Queries

**Description:** Write the data aggregation queries for the dashboard: Today's total focus time, Timeline block reconstruction, Top Distractions ranking, and Weekly Streak calculation.

**Acceptance criteria:**
- [ ] Queries execute quickly off the main thread.
- [ ] Streak calculation accurately respects midnight boundaries.
- [ ] Timeline query correctly reconstructs sequential gaps and blocks.

**Verification:**
- [ ] Unit tests: Verify query outputs against mock DB states.

**Dependencies:** Task 3

**Files likely touched:**
- `Anchored/Storage/DashboardQueries.swift`
- `AnchoredTests/Storage/DashboardQueriesTests.swift`

**Estimated scope:** Medium (2 files)

---

#### Task 14: Dashboard Window & Layout

**Description:** Build the 600x480 `NSWindow` containing the Dashboard. Wire it up to open from the Menu Bar dropdown.

**Acceptance criteria:**
- [ ] Fixed size window, styled appropriately.
- [ ] Left-click menu bar dropdown contains "View Dashboard" button.

**Verification:**
- [ ] Manual check: Open dashboard window.

**Dependencies:** Task 13

**Files likely touched:**
- `Anchored/App/DashboardWindow.swift`
- `Anchored/MenuBar/MenuBarController.swift`

**Estimated scope:** Small (2 files)

---

#### Task 15: Timeline NSView Component

**Description:** Build the core visual of the Dashboard: the horizontal timeline view rendering colored blocks for focus time and gaps for distractions.

**Acceptance criteria:**
- [ ] Renders proportionally based on the day's total elapsed time.
- [ ] Hover tooltips show the app/duration for specific blocks.

**Verification:**
- [ ] Manual check: Verify blocks match known session lengths visually.

**Dependencies:** Task 14

**Files likely touched:**
- `Anchored/App/Views/TimelineView.swift`

**Estimated scope:** Large (Custom drawing/layout)

---

#### Task 16: History & Distractions Views

**Description:** Complete the dashboard by building the Top Distractions ranked list view and the Weekly History bar chart.

**Acceptance criteria:**
- [ ] Top distractions shows app icons/domain favicons and total interrupted time.
- [ ] Weekly chart shows 7 bars for the last 7 days of focus time.

**Verification:**
- [ ] Manual check: Verify data populates correctly.

**Dependencies:** Task 14

**Files likely touched:**
- `Anchored/App/Views/TopDistractionsView.swift`
- `Anchored/App/Views/WeeklyHistoryView.swift`

**Estimated scope:** Medium (2 files)

---

### ✅ Checkpoint: Analytics

- [ ] Dashboard loads instantly (< 100ms).
- [ ] Timeline accurately reflects the user's day with colored blocks.

---

### Phase 5: Smart Auto-Triggers

#### Task 17: ShadowTrackingEngine & Sleep Observers

**Description:** Build the ambient background tracker that monitors app usage against the profile's allowed apps when a focus session is NOT active. Hook into `NSWorkspace` sleep/wake notifications to pause tracking.

**Acceptance criteria:**
- [ ] Tracks continuous time in allowed/trigger apps.
- [ ] Resets counter when user switches to a neutral/distraction app.
- [ ] Pauses tracking completely during Mac sleep.

**Verification:**
- [ ] Manual check: Put Mac to sleep, verify tracking gaps are respected.

**Dependencies:** Task 7

**Files likely touched:**
- `Anchored/Engine/ShadowTrackingEngine.swift`

**Estimated scope:** Medium (1 file)

---

#### Task 18: Smart Nudge Notifications

**Description:** Integrate macOS `UNUserNotificationCenter` to fire a local "Smart Nudge" push notification when the shadow tracker crosses the threshold (e.g. 5 minutes). Implement the Preferences opt-in toggle.

**Acceptance criteria:**
- [ ] Preferences has toggle: "Enable background app tracking for Smart Nudges".
- [ ] Notification fires correctly after threshold.
- [ ] Clicking the notification programmatically starts a Focus Session via `FocusEngine`.

**Verification:**
- [ ] Manual check: Wait 5 mins in Xcode, verify nudge appears, click it, verify session starts.

**Dependencies:** Task 17

**Files likely touched:**
- `Anchored/Engine/SmartNudgeManager.swift`
- `Anchored/App/PreferencesWindow.swift`

**Estimated scope:** Small (2 files)

---

### ✅ Checkpoint: V2 Complete

- [ ] End-to-end flow works for all V2 features.
- [ ] Shadow tracking halts perfectly when Mac goes to sleep.
- [ ] Smart nudge successfully converts into a real focus session.
- [ ] System is ready for V2 Launch.

---

## Parallelization Opportunities

**Safe to parallelize (no shared state):**
- Tasks 4, 8, 13 can run in parallel after Task 3 is complete.
- Task 9 (Browser Loop) and Task 10/11 (Raw Browser extraction logic) can be built independently and integrated later.
- UI Tasks (14, 15, 16) can be parallelized with Data Tasks (13) by using mock data interfaces.

**Must be sequential:**
- Task 7 (FocusEngine Update) depends on Profiles (4, 6) and URL Parsing (12).
- Task 17/18 (Shadow Tracking) depend on the ProfileManager (4) being stable.

**Suggested parallel execution groups (if multiple agents available):**

| Agent A (Core) | Agent B (UI) | Agent C (Data/Scripts) |
|---|---|---|
| Task 1 (setup) | — | — |
| Task 2 (schema) | — | — |
| Task 3 (migration) | — | — |
| Task 4 (profiles) | Task 5 (prefs ui) | Task 13 (sql queries) |
| Task 7 (engine update) | Task 6 (domain ui) | Task 10 (applescript) |
| Task 9 (polling loop) | Task 8 (prompt ui) | Task 11 (firefox) |
| Task 12 (url matcher) | Task 14 (dashboard layout)| Task 17 (shadow engine)|
| Task 18 (nudges) | Task 15 (timeline view) | — |
| — | Task 16 (history view) | — |



================================================================================
FILE: anchored-v2.5-plan.md
SIZE: 21253
================================================================================

# Implementation Plan: Anchored V2.5 — Context Enrichment & Core Stability

## 1. Overview & Architecture

### Overview
This plan details the implementation of Anchored V2.5. The primary goals are securing background resource cycles through memory leak resolution, eliminating test-suite singleton pollution, and enriching active context telemetry by capturing page and window titles for both web browsers (Safari, Firefox, and Chromium-based browsers) and native macOS applications. This telemetry establishes the crucial text pipeline required to train and feed the CoreML text classifier in V3.

### Architecture Decisions
- **Single Apple Event Script Transactions**: Fetching tab titles and URLs via two separate AppleScript invocations introduces unnecessary execution overhead. Chromium and Safari strategies are modified to execute single transactions returning `<Title>\n<URL>` strings, which are then parsed locally.
- **Fail-Safe Accessibility Fallback**: Since querying window titles of foreground applications via `AXUIElement` requires accessibility permission, the window title queries will degrade gracefully by returning an empty string `""` in the absence of active trust, ensuring foreground application tracking is never blocked.
- **Test Sandbox Isolation**: Rather than referencing and mutating global singleton instances (`DistractionListManager.shared`) directly, tests will preserve original state configurations or leverage test-scoped variables to ensure parallel running safety.

### Dependency Graph

```mermaid
graph TD
    A[Phase 1: Task 1 - Observer leak] --> C[Phase 2: Task 3 - BrowserContext Definition]
    B[Phase 1: Task 2 - Test pollution] --> C
    C --> D[Phase 2: Task 4 - AppContext Update]
    D --> E[Phase 2: Task 5 - ActivityMonitor Signature Update]
    E --> F[Phase 3: Task 6 - Chromium Title Script]
    E --> G[Phase 3: Task 7 - Safari Title Script]
    E --> H[Phase 3: Task 8 - Firefox AXUIElement Walk]
    F --> I[Phase 3: Task 9 - Strategy Unit Testing]
    G --> I
    H --> I
    E --> J[Phase 4: Task 10 - AppSwitchMonitor Native Queries]
    J --> K[Phase 4: Task 11 - FocusEngine Piping]
    K --> L[Phase 4: Task 12 - ShadowTracking Engine Update]
    L --> M[Phase 4: Task 13 - Integration Verification Tests]
    I --> M
    M --> N[Phase 5: Task 14 - Database Query Extensions]
    N --> O[Phase 5: Task 15 - Tidal Wave Bezier Chart]
    N --> P[Phase 5: Task 16 - Constellation Heatmap]
    N --> Q[Phase 5: Task 17 - Fleet Tree Spreadmap]
    O --> R[Phase 5: Task 18 - Unify Menu & Detail Pane]
    P --> R
    Q --> R
```

---


## 2. Task List

### Phase 1: Engine Resource & Test Stability
This phase focuses on patching resource leaks and test suite pollution to guarantee CI stability.

#### Task 1: Fix Workspace Notification Observer Leak in ShadowTrackingEngine

**Description:** Add observer teardown for `NSWorkspace.shared.notificationCenter` in `ShadowTrackingEngine`'s `deinit` to prevent memory leaks and crashes on system sleep/wake actions.

**Acceptance criteria:**
- [ ] Observers added to `NSWorkspace.shared.notificationCenter` for `willSleepNotification` and `didWakeNotification` are explicitly removed in `deinit`.
- [ ] Deallocation of `ShadowTrackingEngine` does not leave dangling listeners in the workspace notification center.

**Verification:**
- [ ] Initialize and release `ShadowTrackingEngine` in a mock test context; verify it does not trigger errors or crashes when sleep/wake notifications are fired.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Engine/ShadowTrackingEngine.swift`

**Estimated scope:** XS

---

#### Task 2: Resolve DistractionListManager Singleton Test Pollution

**Description:** Refactor `ShadowTrackingEngineTests.swift` to back up the initial state of the global `DistractionListManager.shared` in `setUp()` and restore it in `tearDown()`, preventing test configuration leakage.

**Acceptance criteria:**
- [ ] `ShadowTrackingEngineTests` does not permanently mutate `DistractionListManager.shared` for other test cases.
- [ ] The global distraction manager state matches its pristine default after `tearDown()` runs.

**Verification:**
- [ ] Run the full test suite concurrently and verify `testShadowTrackingPausesOnSleep` passes consistently alongside all other tests.
  `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' test`

**Dependencies:** None

**Files likely touched:**
- `AnchoredTests/Engine/ShadowTrackingEngineTests.swift`

**Estimated scope:** XS

---

### Phase 2: Data Models & Protocol Refactoring
This phase refactors interfaces to prepare the pipeline for window title metadata propagation.

#### Task 3: Define BrowserContext and Refactor BrowserStrategy Protocol

**Description:** Introduce a robust `BrowserContext` type to carry title and URL properties, and refactor the `BrowserStrategy` protocol interface to return `BrowserContext?` instead of `URL?`.

**Acceptance criteria:**
- [ ] `BrowserContext` structure defines `title: String` and `url: URL`.
- [ ] `BrowserStrategy` protocol exposes `func getActiveContext() -> BrowserContext?`.
- [ ] Existing strategy classes (`ChromiumBrowserStrategy`, `SafariBrowserStrategy`, `FirefoxBrowserStrategy`) implement the updated signature returning placeholder title data to ensure target compilation.

**Verification:**
- [ ] Target compile succeeds.
  `xcodebuild -project Anchored.xcodeproj -scheme Anchored build`

**Dependencies:** Task 1, Task 2

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`

**Estimated scope:** S

---

#### Task 4: Update AppContext Structure

**Description:** Update the `AppContext` data model to include a `title` property and adjust standard initializer signatures.

**Acceptance criteria:**
- [ ] `AppContext` contains a `let title: String` property.
- [ ] Initializer and decoding blocks support the title property.

**Verification:**
- [ ] Model unit tests verify instantiation and JSON coding logic for `AppContext`.

**Dependencies:** Task 3

**Files likely touched:**
- `Anchored/Models/AppContext.swift`
- `AnchoredTests/Models/AppContextTests.swift`

**Estimated scope:** XS

---

#### Task 5: Refactor ActivityMonitor Callback and AppSwitchMonitor Handlers

**Description:** Update `ActivityMonitor.onContextChange` closure signature to emit title context as the third argument, and modify AppSwitchMonitor and FocusEngine handlers to match.

**Acceptance criteria:**
- [ ] `ActivityMonitor.onContextChange` is updated to `((_ bundleID: String, _ url: URL?, _ title: String) -> Void)?`.
- [ ] `AppSwitchMonitor` emits title updates through the callback.
- [ ] `FocusEngine` initialization wires the new callback parameters.

**Verification:**
- [ ] Anchored application and unit tests targets compile cleanly.

**Dependencies:** Task 4

**Files likely touched:**
- `Anchored/Engine/ActivityMonitor.swift`
- `Anchored/Engine/AppSwitchMonitor.swift`
- `Anchored/Engine/FocusEngine.swift`

**Estimated scope:** S

---

### Phase 3: Browser Strategy Title Extraction
This phase implements page title extraction for Chromium, Safari, and Firefox browser strategy components.

#### Task 6: Implement Chromium Browser Strategy Title Queries

**Description:** Update the AppleScript query target in `ChromiumBrowserStrategy` to fetch both active tab title and URL separated by a newline in a single transaction, and parse the response.

**Acceptance criteria:**
- [ ] AppleScript fetches `(title of active tab) & "\n" & (URL of active tab)`.
- [ ] Script response is split by `\n` to populate `BrowserContext(title: url:)`.
- [ ] Gracefully handles multi-line titles without throwing index range errors.

**Verification:**
- [ ] Verify parsing logic using mocked AppleScript results in strategy tests.

**Dependencies:** Task 3, Task 5

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`

**Estimated scope:** S

---

#### Task 7: Implement Safari Browser Strategy Title Queries

**Description:** Rewrite Safari strategy AppleScript queries (both JavaScript automation verification query and fallback query) to query active tab title and URL.

**Acceptance criteria:**
- [ ] JavaScript string runs `document.title + '\n' + window.location.href`.
- [ ] Fallback AppleScript queries `(name of current tab of window 1) & "\n" & (URL of current tab of window 1)`.
- [ ] Safely parses both values into a `BrowserContext` structure.

**Verification:**
- [ ] Verify using mocked executor results in strategy tests.

**Dependencies:** Task 3, Task 5

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`

**Estimated scope:** S

---

#### Task 8: Implement Firefox Browser Strategy Title Queries

**Description:** Update `FirefoxBrowserStrategy` accessibility walk to extract the window's `kAXTitleAttribute` as the tab title, combined with the address bar URL value.

**Acceptance criteria:**
- [ ] Obtains active tab title from window attributes via accessibility tree.
- [ ] Extracts URL via heuristic address bar text field attribute checks.
- [ ] Returns valid `BrowserContext` on success.

**Verification:**
- [ ] Switch to Firefox with an open tab and verify the correct tab title is printed in logs or tests.

**Dependencies:** Task 3, Task 5

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`

**Estimated scope:** M

---

#### Task 9: Unit Test Browser Strategy Context Parsing

**Description:** Write unit tests for title/URL parsing in `BrowserStrategiesTests` using the mock `AppleScriptExecutor`.

**Acceptance criteria:**
- [ ] Tests verify parsing logic with newline-separated inputs.
- [ ] Tests check fallback handling when page titles contain multiple newlines or delimiters.

**Verification:**
- [ ] Run `BrowserStrategiesTests` and verify all tests pass.

**Dependencies:** Task 6, Task 7, Task 8

**Files likely touched:**
- `AnchoredTests/Engine/BrowserStrategiesTests.swift`

**Estimated scope:** S

---

### Phase 4: Native App Title Extraction & FocusEngine Piping
This phase extracts native window titles and routes the enriched telemetry through the engine.

#### Task 10: Implement Native Window Title Extraction in AppSwitchMonitor

**Description:** Query application window references via `AXUIElement` in `AppSwitchMonitor` to capture native app window titles.

**Acceptance criteria:**
- [ ] Query targets focused window reference (`kAXFocusedWindowAttribute`) and reads `kAXTitleAttribute`.
- [ ] Returns empty string `""` if query fails or accessibility permission is missing.

**Verification:**
- [ ] Print window titles to console during app switches (e.g. switching between Xcode and Terminal) and check accuracy.

**Dependencies:** Task 5

**Files likely touched:**
- `Anchored/Engine/AppSwitchMonitor.swift`

**Estimated scope:** S

---

#### Task 11: Propagate Enriched AppContext via FocusEngine

**Description:** Modify `FocusEngine` to capture window/tab titles during context updates, mapping them to `AppContext` and inclusion in notification userInfo.

**Acceptance criteria:**
- [ ] `FocusEngine` instantiates the updated `AppContext` containing `title`.
- [ ] `.focusEngineContextDidChange` notification user info dictionary includes the `"title"` string key.

**Verification:**
- [ ] Focus engine notifications are posted with the correct title metadata values.

**Dependencies:** Task 5, Task 10

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`

**Estimated scope:** S

---

#### Task 12: Update ShadowTrackingEngine to Consume Title Context

**Description:** Adapt `ShadowTrackingEngine`'s focus engine context observer block to extract the title string from notification userInfo.

**Acceptance criteria:**
- [ ] Observer parses `"title"` key from `.focusEngineContextDidChange` updates.
- [ ] Target tracking remains compile and runtime safe.

**Verification:**
- [ ] Ensure Shadow tracking continues to accumulate time accurately during active focus states.

**Dependencies:** Task 11

**Files likely touched:**
- `Anchored/Engine/ShadowTrackingEngine.swift`

**Estimated scope:** XS

---

#### Task 13: Add Tests for Context Title Extraction and Propagation

**Description:** Write unit tests verifying that window titles are correctly piped through `FocusEngine` and context notifications.

**Acceptance criteria:**
- [ ] `FocusEngineTests` verify context switches accurately track the title.
- [ ] `ShadowTrackingEngineTests` verify title presence does not disrupt focus duration accumulation.

**Verification:**
- [ ] Run full test suite; verify all tests pass.

**Dependencies:** Task 9, Task 11, Task 12

**Files likely touched:**
- `AnchoredTests/Engine/FocusEngineTests.swift`
- `AnchoredTests/Engine/ShadowTrackingEngineTests.swift`

**Estimated scope:** S

---

### Phase 5: The Captain's Charts (Unified Dashboard & Analytics)
This phase implements the new visual analytics widgets, data queries, and unifies the MenuBar dashboard menu item.

#### Task 14: Implement Database Query Extensions for Analytics

**Description:** Add helper queries to `DashboardQueries.swift` to extract hourly focus times for the last 24 hours, daily focus times for 7/14/30 day ranges, and hierarchical app-domain focus distribution.

**Acceptance criteria:**
- [ ] `focusTimePerHourForLast24Hours` returns ordered hourly buckets with sum of focus time.
- [ ] `focusTimePerDay(since:to:)` returns ordered daily focus duration sums.
- [ ] Queries must run asynchronously or performantly on the background utility queue.

**Verification:**
- [ ] Add unit tests verifying calculation accuracy with mock database entries.

**Dependencies:** None (Standalone Store extension)

**Files likely touched:**
- `Anchored/Storage/DashboardQueries.swift`

**Estimated scope:** S

---

#### Task 15: Implement the Tidal Wave Chart (Bezier Activity Graph)

**Description:** Create a custom line graph in SwiftUI using `Path` drawing with cubic Bezier control points, supporting 1 Day, 1 Week, 2 Weeks, and 30 Days ranges.

**Acceptance criteria:**
- [ ] Renders a smooth curve passing through each focus data point.
- [ ] Includes a horizontal segmented picker styling a sleek top selector.
- [ ] Displays area gradient under the curve matching the deep ocean theme.

**Verification:**
- [ ] Review visually in SwiftUI Preview with populated test data.

**Dependencies:** Task 14

**Files likely touched:**
- `Anchored/App/Views/WeeklyHistoryView.swift`

**Estimated scope:** S

---

#### Task 16: Implement the Constellation Chart (GitHub-style Heatmap)

**Description:** Create a 7x20 grid layout of cells in SwiftUI representing daily focus intensity over the last 20 weeks.

**Acceptance criteria:**
- [ ] X-axis represents weeks, Y-axis represents weekdays.
- [ ] Cells color-scale from dark transparent green/teal to glowing gold/green depending on focus time.
- [ ] Smooth tooltip displays date and duration on hover.

**Verification:**
- [ ] Verify visually in settings pane.

**Dependencies:** Task 14

**Files likely touched:**
- `Anchored/MenuBar/SettingsView.swift`

**Estimated scope:** S

---

#### Task 17: Implement the Fleet Tree (GitHub-style Spreadmap)

**Description:** Implement a custom node-link tree hierarchy widget showing focus spread from a central Voyage hub out to App nodes and browser domains.

**Acceptance criteria:**
- [ ] Central hub node connects to App nodes (e.g. Xcode, Safari).
- [ ] Browser nodes branch out to individual domains (e.g. github.com).
- [ ] Line connectors draw smooth bezier paths.
- [ ] Nodes display proportional sizes or glowing intensities based on focus time.

**Verification:**
- [ ] Verify visual alignment and responsive resizing in the Detail pane.

**Dependencies:** Task 14

**Files likely touched:**
- `Anchored/MenuBar/SettingsView.swift`

**Estimated scope:** M

---

#### Task 18: Unify Menu Item & Detail Pane Layout

**Description:** Update MenuBar "Peer into Captain's Log..." to open the Settings window's `.analytics` pane, integrate the new charts into `AnalyticsSettingsPane`, and clean up deprecated dashboard windows.

**Acceptance criteria:**
- [ ] `MenuBarController.openDashboard()` calls `showSettingsWindow(section: .analytics)`.
- [ ] Deprecate/remove `DashboardWindow.swift` and `DashboardView.swift` safely if they are no longer in use.
- [ ] `AnalyticsSettingsPane` hosts the Tidal Wave Chart, Constellation Heatmap, and Fleet Tree Spreadmap.

**Verification:**
- [ ] Verify clicking "Peer into Captain's Log..." opens Settings at the "Voyage Logs" tab.
- [ ] Verify the application builds and launches cleanly.

**Dependencies:** Task 15, Task 16, Task 17

**Files likely touched:**
- `Anchored/MenuBar/MenuBarController.swift`
- `Anchored/MenuBar/SettingsView.swift`
- `Anchored/App/DashboardWindow.swift`
- `Anchored/App/Views/DashboardView.swift`

**Estimated scope:** S

---


## 3. Checkpoints

### ✅ Checkpoint: Phase 1 (Core Stability)
- [ ] Observers on `NSWorkspace.shared.notificationCenter` are cleaned up correctly in `ShadowTrackingEngine`.
- [ ] Global distraction manager state is restored correctly during test suite execution.
- [ ] The entire `AnchoredTests` suite runs and passes cleanly without failures.

### ✅ Checkpoint: Phase 2 (Refactoring & Types)
- [ ] The updated signatures of `BrowserStrategy`, `AppContext`, and `ActivityMonitor` compile successfully.
- [ ] Basic app switch monitoring functions correctly with title parameters wired.

### ✅ Checkpoint: Phase 3 (Browser Strategies)
- [ ] AppleScript strategy implementations correctly extract tab titles and URLs in single transactions.
- [ ] Accessibility queries for Firefox resolve titles and URLs safely.
- [ ] Mock strategy tests verify parsing rules across various edge cases.

### ✅ Checkpoint: Phase 4 (Integration & End-to-End)
- [ ] Native macOS window titles are successfully extracted during active app switches.
- [ ] Window/tab titles are correctly propagated through the `FocusEngine` and context notification piping.
- [ ] All unit and regression tests pass successfully on the runner.

### ✅ Checkpoint: Phase 5 (The Captain's Charts)
- [ ] Database extensions for hourly and daily focus values correctly query and aggregate events.
- [ ] Segmented activity bar updates the Bezier Tidal Wave chart dynamically.
- [ ] Constellation Heatmap rendering shows correct daily densities.
- [ ] Fleet Tree renders app and domain nodes with bezier connections.
- [ ] "Peer into Captain's Log..." menu item successfully forwards to Settings Voyage Logs section.


---

## 4. Risks and Mitigations

| Risk | Impact (Low/Med/High) | Mitigation |
|---|---|---|
| **AppleScript Latency**: Querying titles increases Apple Event transaction time, potentially stalling the thread. | Med | Use single transaction strings instead of multiple separate calls, and run queries with a fast script timeout configuration. |
| **Accessibility API Fragility**: Firefox/Native UI element structures can vary between versions, breaking attribute lookups. | Med | Implement defensive lookup checking and return empty titles gracefully instead of blocking application flow. |
| **Missing Accessibility Access**: App cannot query native titles if accessibility permission is disabled. | Low | Gracefully fall back to returning empty string `""` for window title metadata when `AXIsProcessTrusted() == false`. |
| **Sparse Database Records**: Graphs look empty or broken when there are no logs. | Low | Implement robust mock data injection for previews and visual empty state fallbacks. |
| **Custom Tree Drawing Complexity**: Drawing a clean tree hierarchy for the Fleet Tree without libraries might overflow bounds. | Med | Use calculated relative position coordinates within geometry bounds, scaling node sizes based on duration. |


---

## 5. Parallelization Opportunities

### Safe to parallelize:
- **Phase 3 (Browser Strategies)** and **Phase 4 (Native App Title Extraction)** are decoupled and can be implemented in parallel once Phase 2 (Protocol Refactoring) is complete.
- **Task 9 (Strategy Unit Testing)** can be written concurrently with strategy implementations using mock interfaces.

### Must be sequential:
- **Phase 2 (Protocol Refactoring)** must wait for **Phase 1 (Stability)** to be stable.
- **Task 11 (FocusEngine Piping)** depends on **Task 10 (AppSwitchMonitor Native Queries)**.

### Suggested Execution Table

| Agent A (Telemetry Core) | Agent B (Browser Strategies) | Agent C (Quality Assurance & Charts) |
|---|---|---|
| **Task 1**: ShadowTracking observer fix | **Task 3**: BrowserStrategy Refactoring | **Task 2**: Test Pollution Restoration |
| **Task 4**: AppContext Update | **Task 6**: Chromium Title AppleScript | **Task 9**: Strategy Unit Testing |
| **Task 5**: ActivityMonitor Refactoring | **Task 7**: Safari Title AppleScript | **Task 13**: Integration Tests |
| **Task 10**: Native Window Queries | **Task 8**: Firefox Accessibility Queries | **Task 14**: Database Query Extensions |
| **Task 11**: FocusEngine Wiring | | **Task 15**: Tidal Wave Bezier Chart |
| **Task 12**: ShadowTracking updates | | **Task 16**: Constellation Heatmap |
| | | **Task 17**: Fleet Tree Spreadmap |
| | | **Task 18**: Unify Menu & Detail Pane |



================================================================================
FILE: anchored-v2.5.md
SIZE: 14358
================================================================================

# Anchored V2.5 — Enriched Context & Stability

> **Prerequisite:** This spec assumes [Anchored V2 (Permission Gate)](file:///Users/varun/Development/Anchor/docs/ideas/anchored-v2.md) has shipped and is stable. V2.5 acts as a bridge update, focusing on core engine stability and enriched context tracking (titles) before the CoreML and iCloud Sync integration in V3.

## Problem Statement
**How might we** ensure the core engine remains stable, leak-free, and correctly tested, while enriching the context pipeline to capture tab/window titles across all major browsers and native apps, laying the baseline telemetry required for V3's intent-aware local AI classifier?

## V2.5 Summary

V2.5 is a core stability and context telemetry update. It resolves background resources leaks, cleans up test-suite pollution, and upgrades the active tracking mechanisms to extract window and browser tab titles. The three major additions:

1. **Engine Resource & Test Stability** — Patching notification observer leaks in `ShadowTrackingEngine` and resolving singleton test-pollution in `DistractionListManager`.
2. **Browser Strategy Title Enrichment** — Upgrading AppleScript payloads (Safari, Chrome, Arc, Brave, Edge, Orion) and Accessibility traversals (Firefox) to capture both Page Titles and URLs in a single transaction.
3. **Native Window Title Propagation** — Leveraging the accessibility API (`AXUIElement`) to fetch window titles for native macOS applications (e.g., Xcode, Terminal, Figma Desktop), updating the central `AppContext` metadata.

---

## 1. Engine Resource & Test Stability

### The Observer Leak
In V2, the `ShadowTrackingEngine` registered workspace sleep and wake observers on `NSWorkspace.shared.notificationCenter`:

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    self,
    selector: #selector(handleWorkspaceWillSleep),
    name: NSWorkspace.willSleepNotification,
    object: nil
)
```

However, its `deinit` block only cleared observers on the default NotificationCenter:
```swift
deinit {
    stopTimer()
    NotificationCenter.default.removeObserver(self)
}
```

Because observers registered on `NSWorkspace.shared.notificationCenter` were not cleared, the workspace notification center retained a dangling reference to the deallocated `ShadowTrackingEngine` instance. When the system posted a sleep or wake event, it attempted to call the selector on a garbage memory address, resulting in sporadic crashes, memory leaks, and undefined behavior.

**V2.5 Fix:** Extend `deinit` to explicitly tear down all `NSWorkspace` observers:
```swift
deinit {
    stopTimer()
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
}
```

### Test Pollution in DistractionListManager
During testing, `ShadowTrackingEngineTests` directly mutates the singleton `DistractionListManager.shared` by adding and removing applications:

```swift
override func setUp() {
    ...
    DistractionListManager.shared.add("com.spotify.client")
    DistractionListManager.shared.remove("com.apple.dt.Xcode")
}
```

However, the test class did not restore the state of `DistractionListManager.shared` in its `tearDown()`. Because the test suite is executed in a single test runner process, these mutations leaked into subsequent test classes (such as `FocusEngineTests`), causing assertions to fail depending on test runner order.

**V2.5 Fix:** Refactor `ShadowTrackingEngineTests.swift` to back up and restore the exact state of `DistractionListManager.shared` (or leverage a dedicated test-scoped mock instead of modifying the global singleton):
```swift
private var originalDistractions: [String] = []

override func setUp() {
    super.setUp()
    originalDistractions = DistractionListManager.shared.allDistractions
    ...
}

override func tearDown() {
    // Restore the singleton state
    let currentDistractions = DistractionListManager.shared.allDistractions
    for app in currentDistractions {
        DistractionListManager.shared.remove(app)
    }
    for app in originalDistractions {
        DistractionListManager.shared.add(app)
    }
    ...
    super.tearDown()
}
```

---

## 2. Browser Strategy Title Enrichment

To support CoreML text classification, we need a single dense telemetry input mapping to `Title | URL`. Rather than executing two separate AppleScript calls (which doubles execution latency), V2.5 updates the scripts to query both parameters in a single Apple Event transaction.

### Interface Changes
We will update `BrowserStrategy` to return a `BrowserContext` structure containing both the URL and tab Title:

```swift
public struct BrowserContext: Equatable {
    public let title: String
    public let url: URL
}

public protocol BrowserStrategy {
    var bundleIdentifier: String { get }
    func getActiveContext() -> BrowserContext?
}
```

### A. Chromium Strategy (Chrome, Arc, Edge, Brave, Orion)
The AppleScript query is rewritten to return the title and URL separated by a unique newline delimiter:

```applescript
tell application "Google Chrome"
    if window 1 exists then
        tell window 1
            return (title of active tab) & "\n" & (URL of active tab)
        end tell
    end if
end tell
```

*Note: The script target is dynamically resolved using the `appName` string parameter (e.g., "Arc", "Google Chrome").*

**Parsing Logic:**
```swift
public func getActiveContext() -> BrowserContext? {
    let scriptSource = """
    tell application "\(appName)"
        if window 1 exists then
            tell window 1
                return (title of active tab) & "\\n" & (URL of active tab)
            end tell
        end if
    end tell
    """
    
    guard let result = try? executor.execute(scriptSource).trimmingCharacters(in: .whitespacesAndNewlines),
          !result.isEmpty else { return nil }
          
    let parts = result.components(separatedBy: "\n")
    guard parts.count >= 2,
          let urlString = parts.last,
          let url = URL(string: urlString) else {
        return nil
    }
    
    // Join any accidental newlines in title if they occur
    let title = parts.dropLast().joined(separator: "\n")
    return BrowserContext(title: title, url: url)
}
```

### B. Safari Strategy
Safari employs a similar multi-line transaction query:

```applescript
tell application "Safari"
    if window 1 exists then
        tell window 1
            return (name of current tab) & "\n" & (URL of current tab)
        end tell
    end if
end tell
```

**Allow JavaScript Verification:**
Safari's JavaScript verification payload is also updated. If JavaScript events are allowed, we query the location and document title directly via JavaScript:

```applescript
tell application "Safari"
    if window 1 exists then
        tell window 1
            do JavaScript "document.title + '\\n' + window.location.href" in current tab
        end tell
    end if
end tell
```
If this falls back due to JS permissions, we use the standard AppleScript `name` and `URL` properties as fallback context metrics.

### C. Firefox Strategy (Accessibility Tree)
Firefox requires traversing the `AXUIElement` hierarchy. We need to:
1. Locate the frontmost window `AXUIElement` reference.
2. Query its `kAXTitleAttribute` attribute to get the page title (which Firefox maps directly to the active tab title).
3. Recursively traverse child components to locate the text field containing the active URL.

```swift
public func getActiveContext() -> BrowserContext? {
    guard let firefoxApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
        return nil
    }
    
    let appRef = AXUIElementCreateApplication(firefoxApp.processIdentifier)
    var windowRef: AnyObject?
    let windowError = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
    
    guard windowError == .success, let activeWindow = windowRef else { return nil }
    let windowElement = activeWindow as! AXUIElement
    
    // 1. Extract Page Title from Window Attributes
    var titleValue: AnyObject?
    let titleError = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue)
    let title = (titleError == .success ? titleValue as? String : nil) ?? ""
    
    // 2. Traverse tree to locate address bar URL
    guard let url = findURLInUIElement(windowElement) else { return nil }
    
    return BrowserContext(title: title, url: url)
}
```

---

## 3. Native Window Title Propagation

To capture the context of native apps (e.g. knowing if a Terminal window is running a local build vs. SSH'd into an unrelated server, or if Xcode is focused on a specific project file), the `AppSwitchMonitor` will also capture the window title of native applications.

### Accessibility-Based Title Extraction
When a native app is activated, or during monitoring switches, we inspect the application's frontmost window:

```swift
func fetchNativeWindowTitle(processIdentifier: pid_t) -> String {
    let appRef = AXUIElementCreateApplication(processIdentifier)
    var windowRef: AnyObject?
    
    guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
          let activeWindow = windowRef else {
        return ""
    }
    
    var titleRef: AnyObject?
    guard AXUIElementCopyAttributeValue(activeWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
          let titleStr = titleRef as? String else {
        return ""
    }
    
    return titleStr.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

### Protocol Signature Refactoring
The data-flow signature for context change updates must propagate the title:

```swift
// ActivityMonitor.swift
protocol ActivityMonitor: AnyObject {
    /// Callback fired when the foreground context changes.
    /// - Parameter bundleID: The active application's bundle identifier.
    /// - Parameter url: The active URL, if applicable.
    /// - Parameter title: The active window/tab title, if applicable (or empty string).
    var onContextChange: ((_ bundleID: String, _ url: URL?, _ title: String) -> Void)? { get set }
    
    func start()
    func stop()
}
```

`AppContext` is expanded to hold the title state:
```swift
// AppContext.swift
struct AppContext: Codable, Equatable {
    let bundleIdentifier: String
    let localizedName: String
    let title: String
}
```

---

## 4. FocusEngine Decision Logic Update

While V2.5 does not include the CoreML classifier, the `FocusEngine` must consume the title during context updates, mapping them to `AppContext` and preparing the logging store.

```
let incoming = notification.bundleIdentifier
let title = notification.windowTitle
let url = browserURLMonitor?.currentURL

// Create enriched AppContext
let context = AppContext(
    bundleIdentifier: incoming,
    localizedName: getAppName(for: incoming),
    title: title
)

// Post enriched notifications for sub-engines (like ShadowTracking)
NotificationCenter.default.post(
    name: .focusEngineContextDidChange,
    object: self,
    userInfo: [
        "bundleID": incoming,
        "url": url as Any,
        "title": title,
        "isFocus": isFocusContext(bundleID: incoming, url: url)
    ]
)
```

---

## 5. Testing & Quality Assurance Plan

### AppleScript Strategy Unit Testing
We will mock `AppleScriptExecutor` in `BrowserStrategiesTests` to return delimited title/URL payloads, validating parsing logic across edge cases:
- Title containing newline characters (should join them correctly).
- Empty title but valid URL.
- Failure of Apple Event execution.

### Memory Leak Verification Test
Write a test to ensure observers are successfully de-registered on workspace notification centers:
- Initialize a `ShadowTrackingEngine` instance.
- Deallocate it (`shadowEngine = nil`).
- Verify that posting sleep/wake notifications does not crash or trigger leaks in memory instruments.

---

## 6. V2.5 Scope Summary

**In (V2.5):**
- Fix workspace observer memory leak in `ShadowTrackingEngine`
- Fix test pollution of `DistractionListManager.shared` in `ShadowTrackingEngineTests`
- Update `BrowserStrategy` protocol interface to return `BrowserContext` structure
- Refactor Chromium AppleScript strategy to extract Page Title + URL in a single script transaction
- Refactor Safari AppleScript strategy to extract Page Title + URL in a single script transaction
- Update Firefox Accessibility traversal to query window title and address bar URL
- Implement `AXUIElement` window title query for native applications in `AppSwitchMonitor`
- Update `ActivityMonitor.onContextChange` closure signature to include page/window title
- Enrich `AppContext` struct with `title: String` field

**Not In V2.5 (Deferred to V3):**
- **CoreML Text Classifier Model** — Telemetry pipeline only; actual AI classification is deferred.
- **Model Retraining (`MLUpdateTask`)** — Delayed until V3.
- **"The Bouncer" (Hardcore App Hiding)** — Delayed until V3.
- **iCloud Settings Key-Value Sync** — Delayed until V3.
- **AI-Dynamic Modulation of Nudge Thresholds** — Delayed until V3.
- **V3 SQLite Database Migration** — Migration to add `ai_category` column is deferred.

---

## 7. Open Questions

1. **Accessibility Permissions for Native Titles**: Querying `kAXFocusedWindowAttribute` for native application window titles requires Accessibility permissions (`AXIsProcessTrusted() == true`). If permissions are not yet granted, we should fallback gracefully to returning an empty title `""`. Is this acceptable?
2. **Title Length Cap**: Some window titles or webpage titles can be extremely long (e.g. 500+ characters). Should we truncate the title string (e.g., to 250 characters) at context capture time in `AppSwitchMonitor` to prevent memory blowup and reduce SQLite database page writes?

---

## 8. Implementation Progress
- [ ] Fix `ShadowTrackingEngine` memory leak & `deinit`
- [ ] Fix `DistractionListManager` test suite pollution
- [ ] Update `BrowserStrategy` protocol & return values
- [ ] Update Chromium & Safari AppleScript strategies to query title
- [ ] Update Firefox Strategy accessibility walk to query title
- [ ] Implement native application window title extraction
- [ ] Propagate enriched `title` through `ActivityMonitor` and `FocusEngine`



================================================================================
FILE: anchored-v2.6-async-context-plan.md
SIZE: 14967
================================================================================

# Implementation Plan: Non-Blocking Async Context Collection (V2.6 Core)

> **Source specification:** [Non-Blocking Async Context Collection Spec](./anchored-v2.6-async-context-spec.md)

## 1. Overview and Planning Decisions

This plan implements a reliable, non-blocking asynchronous context collection pipeline for Anchored V2.6. By moving browser (AppleScript) and native window (Accessibility) queries off the main thread, we prevent UI freezing and menu-bar lag while extending tracking precision. Deduplication will be based on normalized context identities (composing bundle ID, sanitized URL, and normalized title) rather than raw URL changes.

No CoreML text classification (V3) or app hiding (Bouncer) logic is included in this phase.

### Decisions Locked for This Plan

- **Thread Isolation**: All AppleScript runs on background queues using compiled `NSAppleScript` runners. The AppKit main/UI thread remains unblocked at all times.
- **Deadline Enforcement**: AppleScript calls are capped at a maximum execution time of 750 ms.
- **Stale Rejection**: Collector generation counts guarantee that late-arriving results from background threads cannot overwrite newer foreground app switches.
- **Title Normalization**: Titles are stripped of leading/trailing spaces, control characters, and whitespace runs to ensure accurate deduplication without lowercasing.
- **Deduplication Boundary**: Consecutive identical snapshots (same bundle, sanitized URL, and normalized title) are suppressed, preventing redundant engine updates.

### Dependency Graph

```mermaid
graph TD
    A[Task 1: Validate Apple Event Executor] --> C[Task 4: Implement AppleEventExecutor]
    B[Task 2: Define ContextSnapshot & Source Enum] --> D[Task 3: Define ContextIdentity]
    D --> E[Task 6: Adapt Browser Strategies to Async]
    C --> F[Task 5: Unit Test AppleEventExecutor]
    F --> E
    
    B --> G[Task 7: Adapt Firefox & Native to Accessibility]
    E --> H[Task 8: Create ContextCollector]
    G --> H
    H --> I[Task 9: Unit Test ContextCollector]
    
    I --> J[Task 10: Refactor AppSwitchMonitor]
    J --> K[Task 11: Wire FocusEngine to ContextSnapshot]
```

---

## 2. Task List

### Phase 0: Technical Decision Gate

#### Task 1: Validate the Apple Event Execution Mechanism

**Description:** Build a minimal test harness for background AppleScript execution. Validate behavior under main-thread loads, cancellation, and release builds. Record findings to confirm that `NSAppleScript` running asynchronously on a serial `DispatchQueue` behaves reliably on macOS 13 without UI blocks.

**Acceptance criteria:**
- [ ] Implement a prototype runner validating non-blocking async execution of simple scripts against Safari/Chrome.
- [ ] Demonstrate a 750 ms timeout capability with successful thread cancellation.
- [ ] Confirm no main thread blocking is introduced under high-frequency activation loops.

**Verification:**
- [ ] Review execution times and confirm menus remain interactive when target apps are artificially paused.
- [ ] Validate signing compatibility with the app's current profile.

**Dependencies:** None

**Files likely touched:**
- `AnchoredTests/Engine/AppleEventExecutorTests.swift`
- `docs/decisions/anchored-v2.6-apple-event-executor.md`

**Estimated scope:** S

---

### Phase 1: Canonical Context Foundation

#### Task 2: Define ContextSnapshot & Source Enum

**Description:** Implement the structured model representing a single point-in-time system state observations.

**Acceptance criteria:**
- [ ] Define `ContextSnapshot` struct with `bundleIdentifier: String`, `localizedName: String`, `url: URL?`, `title: String`, `source: Source`, and `observedAt: Date`.
- [ ] Create `ContextSnapshot.Source` enum with cases: `application`, `chromium`, `safari`, `firefox`.
- [ ] Add `Codable` and `Equatable` conformance for `ContextSnapshot`.

**Verification:**
- [ ] Run unit tests: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/ContextSnapshotTests test`
- [ ] Project compiles with no errors.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Models/ContextSnapshot.swift`
- `AnchoredTests/Models/ContextSnapshotTests.swift`

**Estimated scope:** XS

---

#### Task 3: Define ContextIdentity and Normalization Rules

**Description:** Build the value type deduplication key and normalization utilities for URLs and titles.

**Acceptance criteria:**
- [ ] Create `ContextIdentity` struct wrapping `bundleID`, `sanitizedURL`, and `normalizedTitle`.
- [ ] Implement `normalizedTitle` utilizing `ContextSanitizer.sanitizeTitle(_:)` (collapsing whitespaces, dropping control characters, capping at 512 clusters).
- [ ] Implement `sanitizedURL` utilizing `ContextSanitizer.sanitizePersistedURL(_:)` (removing credentials, queries, and fragments).
- [ ] Equip `ContextSnapshot` with `var identity: ContextIdentity`.
- [ ] Conformance to `Equatable` for `ContextIdentity` must ignore timestamps and sources.

**Verification:**
- [ ] Tests confirm that matching normalized contexts are evaluated as equal, regardless of sub-second timestamps or source parameters.
- [ ] Assert unicode compliance under multi-byte characters and tabs.

**Dependencies:** Task 2

**Files likely touched:**
- `Anchored/Models/ContextSnapshot.swift`
- `AnchoredTests/Models/ContextSnapshotTests.swift`

**Estimated scope:** S

---

### Phase 2: Asynchronous AppleScript Execution

#### Task 4: Implement AppleEventExecutor

**Description:** Build the production background serial queue compiler and execution pipeline for AppleScripts.

**Acceptance criteria:**
- [ ] Implement `AppleEventExecutor` class using background serial queue dispatch.
- [ ] Expose `func execute(_ scriptSource: String, timeout: TimeInterval, completion: @escaping (Result<String, ExecutorError>) -> Void)`.
- [ ] Integrate task deadlines returning `.failure(.timedOut)` if execution exceeds 750 ms.
- [ ] Handle syntax/runtime script errors returning `.failure(.execFailed(message))`.

**Verification:**
- [ ] Execution output prints background queue labels indicating thread isolation.

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Engine/AppleEventExecutor.swift`

**Estimated scope:** M

---

#### Task 5: Unit Test AppleEventExecutor

**Description:** Add high-coverage test cases proving timeout, serialization, and error recovery of the execution block.

**Acceptance criteria:**
- [ ] Test slow-script simulation returning `.timedOut` exactly at deadline boundaries.
- [ ] Test overlapping execution queues verifying serial order.
- [ ] Test thread safety under massive execution loops (e.g. 50 parallel requests).

**Verification:**
- [ ] `xcodebuild test -only-testing:AnchoredTests/AppleEventExecutorTests` passes cleanly.

**Dependencies:** Task 4

**Files likely touched:**
- `AnchoredTests/Engine/AppleEventExecutorTests.swift`

**Estimated scope:** S

---

### Phase 3: Safe Accessibility Context Provider

#### Task 6: Adapt Browser Strategies to Async AppleEventExecutor

**Description:** Refactor existing synchronous browser stratégies to invoke the `AppleEventExecutor` asynchronously.

**Acceptance criteria:**
- [ ] Refactor `BrowserStrategy` protocol to return callback/Result structures.
- [ ] Migrate `ChromiumBrowserStrategy` and `SafariBrowserStrategy` to use `AppleEventExecutor` for AppleScript payloads.
- [ ] Split strategy inputs by the script's `Title | URL` output format and wrap in a `Result`.

**Verification:**
- [ ] Strategies tests pass with mocked script outputs.
- [ ] Check Chromium and Safari live strategy runs in local build.

**Dependencies:** Tasks 5

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`
- `AnchoredTests/Engine/BrowserStrategiesTests.swift`

**Estimated scope:** M

---

#### Task 7: Adapt Firefox and Native Apps to Safe Accessibility Provider

**Description:** Connect Firefox and native macOS apps to the `SystemAccessibilityContextProvider` to fetch contexts safely off the main thread.

**Acceptance criteria:**
- [ ] Inject `SystemAccessibilityContextProvider` as the active provider interface.
- [ ] Traverse window accessibility elements safely with strict visited-nodes depth recursion caps.
- [ ] Safely capture `.permissionDenied` or `.windowUnavailable` errors without raising crashes.

**Verification:**
- [ ] Run unit tests: `xcodebuild test -only-testing:AnchoredTests/AccessibilityContextProviderTests` succeeds.

**Dependencies:** Task 2

**Files likely touched:**
- `Anchored/Engine/AccessibilityContextProvider.swift`
- `AnchoredTests/Engine/AccessibilityContextProviderTests.swift`

**Estimated scope:** S

---

### Phase 4: Async Context Collector Orchestration

#### Task 8: Create ContextCollector & Generation Validation

**Description:** Implement the central manager coordinating native and browser collectors, enforcing request generation limits.

**Acceptance criteria:**
- [ ] Implement `ContextCollector` adopting `ContextCollecting` protocol.
- [ ] Manage `currentGeneration: Int` internally.
- [ ] Cancel/discard completion responses whose callback generation is less than the active `currentGeneration`.
- [ ] Prevent multiple parallel provider checks.

**Verification:**
- [ ] Test that rapid collection requests return only the newest active context snapshot.

**Dependencies:** Tasks 6, 7

**Files likely touched:**
- `Anchored/Engine/ContextCollector.swift`

**Estimated scope:** M

---

#### Task 9: Unit Test ContextCollector

**Description:** Build test suites verifying collector generation checks, timeout discards, and strategy routing.

**Acceptance criteria:**
- [ ] Mock strategy latency and prove out-of-order responses are rejected.
- [ ] Verify timed-out requests return expected `.timedOut` errors.

**Verification:**
- [ ] `xcodebuild test -only-testing:AnchoredTests/ContextCollectorTests` runs with zero failures.

**Dependencies:** Task 8

**Files likely touched:**
- `AnchoredTests/Engine/ContextCollectorTests.swift`

**Estimated scope:** S

---

### Phase 5: Pipeline & Engine Wiring

#### Task 10: Refactor AppSwitchMonitor to Async Pattern

**Description:** Refactor the live app activation monitor to poll the collector asynchronously and emit structured deduplicated snapshots.

**Acceptance criteria:**
- [ ] Refactor `AppSwitchMonitor` to invoke `ContextCollector.collectContext` on active bundle IDs.
- [ ] Change `onContextChange` callback signature to accept `ContextSnapshot`.
- [ ] Store `lastPolledIdentity: ContextIdentity` to deduplicate incoming snapshots.
- [ ] Release timers, suspend polling, and handle locks or wake events.

**Verification:**
- [ ] Unit tests mock fast switches and verify correct deduplicated snapshot emissions.

**Dependencies:** Task 9

**Files likely touched:**
- `Anchored/Engine/ActivityMonitor.swift`
- `Anchored/Engine/AppSwitchMonitor.swift`
- `AnchoredTests/Engine/AppSwitchMonitorTests.swift`

**Estimated scope:** M

---

#### Task 11: Wire FocusEngine to ContextSnapshot

**Description:** Connect the `ContextSnapshot` stream to `FocusEngine` and update downstream pipeline modules (history, shadow tracking, overlay).

**Acceptance criteria:**
- [ ] Refactor `FocusEngine.swift` initializer and callback bindings to consume `ContextSnapshot`.
- [ ] Map snapshot credentials/sanitizations through the existing focus rules to maintain backward compatibility.
- [ ] Refactor `ContextHistoryPipeline` to extract attributes directly from the snapshot parameters.
- [ ] Fix all positional signature compilation issues across engine tests.

**Verification:**
- [ ] Full application compiles cleanly.
- [ ] All 138 unit tests run and pass without failures: `xcodebuild test -project Anchored.xcodeproj -scheme AnchoredTests` succeeds.

**Dependencies:** Task 10

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Engine/ShadowTrackingEngine.swift`
- `Anchored/Engine/ContextHistoryPipeline.swift`
- `AnchoredTests/Engine/FocusEngineTests.swift`
- `AnchoredTests/Engine/ShadowTrackingEngineTests.swift`
- `AnchoredTests/Engine/ContextHistoryPipelineTests.swift`
- `AnchoredTests/Overlay/OverlayManagerTests.swift`

**Estimated scope:** L

---

## 3. Checkpoints

### ✅ Checkpoint: Phase 1 (Foundation)
- [ ] Value types compile and represent context accurately.
- [ ] Sanitization and title normalization tests pass.
- [ ] Deduplication checks cover Unicode variations.

### ✅ Checkpoint: Phase 2 & 3 (Execution & Provider)
- [ ] AppleScript compiles on serial background queues.
- [ ] Script timeouts trigger at 750 ms.
- [ ] Accessibility providers traverse Firefox and native app window lists safely.

### ✅ Checkpoint: Phase 4 (Collector)
- [ ] `ContextCollector` isolates asynchronous tasks.
- [ ] Slow strategy responses are filtered by generation parameters.
- [ ] Thread safety and memory leak tests pass.

### ✅ Checkpoint: Phase 5 (Integration)
- [ ] Application compiles successfully with no positional tuple arguments.
- [ ] deduplicated active context events are successfully written to SQLite.
- [ ] Full unit test suite returns green status.

---

## 4. Risks and Mitigations

| Risk | Impact | Mitigation |
| :--- | :---: | :--- |
| UI thread blocks during compilation or loading of AppleScript files. | High | Always dispatch NSAppleScript creation and compilation to background queues inside `AppleEventExecutor`. |
| Rapid browser tab switching causes memory leaks or task accumulation. | Med | Store references to Dispatch work items and cancel prior generation items immediately on context switch. |
| Window accessibility updates cause performance spikes. | Med | Cache native window references and cap accessibility tree traversals at a depth of 16 and a visited-nodes threshold of 256. |
| deduplication misses single-page application tab updates. | High | Evaluate both sanitized URL path and normalized window title in `ContextIdentity.==` comparison. |

---

## 5. Parallelization Opportunities

- **Safe to Parallelize**:
  - Task 2 & Task 3 (Core Models) can be written alongside Task 4 & Task 5 (AppleEventExecutor) since their interfaces are decoupled.
  - Task 7 (Accessibility Provider refactoring) can run concurrently with Task 6 strategy updates.
- **Must be Sequential**:
  - Task 8 (Collector) requires strategy changes (Task 6) and executor changes (Task 4) to compile.
  - Task 10 & 11 (Monitor & Engine wiring) must run sequentially after the collector is stable.

### Suggested Execution Table

| Agent | Task Assignation | Focus Area |
| :--- | :--- | :--- |
| **Agent A** | Tasks 2, 3, 7 | Focus on Snapshot, Identity, and Accessibility context retrieval structures. |
| **Agent B** | Tasks 1, 4, 5, 6 | Focus on serial background AppleScript compiler queue and strategy migration. |
| **Agent C** | Tasks 8, 9, 10, 11 | Focus on Collector generation orchestrator, AppSwitchMonitor, and downstream FocusEngine integrations. |



================================================================================
FILE: anchored-v2.6-async-context-spec.md
SIZE: 4719
================================================================================

# Spec: Non-Blocking Async Context Collection (V2.6 Core)

## Objective
Anchored collects active application bundle IDs, URLs, and window titles to evaluate focus status. Currently, context collection runs synchronously on the main thread. This has two major drawbacks:
1. Synchronous AppleScript execution (used for Chrome and Safari) blocks the UI thread, causing visible menu-bar lags or spinning pinwheels when a browser is busy or slow.
2. The context identity is URL-only, which misses dynamic title-only changes (same-URL tab switching, single-page app state transitions).

This feature introduces a reliable, non-blocking asynchronous context collection pipeline:
- Defines `ContextSnapshot` and `ContextIdentity` to support structured, deduplicated tracking of bundle ID, URL, and title.
- Introduces an asynchronous `AppleEventExecutor` that executes AppleScript commands off the main thread with a 750 ms deadline and cancellation.
- Implements `ContextCollector` to orchestrate background collection and safely reject stale results from late-running scripts.
- Refactors `AppSwitchMonitor` to consume `ContextCollector` asynchronously and publish deduplicated context events.

## Tech Stack
- Language: Swift 5.7
- Frameworks: AppKit, ApplicationServices, Foundation
- Platforms: macOS 13.0+

## Commands
- Build project:
  ```bash
  xcodegen generate
  xcodebuild -project Anchored.xcodeproj -scheme Anchored -destination 'platform=macOS' build
  ```
- Run unit tests:
  ```bash
  xcodebuild test -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  ```

## Project Structure
All new models, collectors, and execution engines will reside in the core directories:
- `Anchored/Models/ContextSnapshot.swift` -> Value type representing a single context snapshot.
- `Anchored/Engine/ContextNormalizer.swift` -> Normalization logic for titles and URLs.
- `Anchored/Engine/AppleEventExecutor.swift` -> Background executor for AppleScript.
- `Anchored/Engine/ContextCollector.swift` -> Orchestrator for asynchronous collection.
- `AnchoredTests/Engine/ContextCollectorTests.swift` -> Verification of timeouts, cancellation, and stale-rejection.
- `AnchoredTests/Engine/AppleEventExecutorTests.swift` -> Verification of AppleScript timeout and thread isolation.

## Code Style
Standard Anchored conventions: 4-space indentation, standard naming, explicit types, and dependency injection.

```swift
// Example: Asynchronous context provider contract
protocol ContextCollecting: AnyObject {
    func collectContext(for bundleID: String, completion: @escaping (Result<ContextSnapshot, CollectionError>) -> Void)
}

enum CollectionError: Error, Equatable {
    case timedOut
    case permissionDenied
    case execFailed(String)
}
```

## Testing Strategy
- **Framework**: XCTest
- **Coverage**: 100% unit test coverage for `ContextCollector` orchestration, `AppleEventExecutor` timeout boundaries, and `ContextNormalizer` string sanitation rules.
- **Isolation**: Use `TestScheduler` or dependency injection to inject mock execution behaviors. Never write tests that require sleeping for a hardcoded time (e.g. `Thread.sleep(forTimeInterval:)`).

## Boundaries
- **Always**:
  - Perform all UI and engine state updates on the main queue (`DispatchQueue.main.async`).
  - Clamp timeouts to a maximum of 750 ms for AppleScript requests.
  - Release resources, cancel outstanding timers, and discard late results when switching applications.
- **Ask First**:
  - Changing the polling frequency (currently 2.5s) of the browser URL check.
  - Modifying the existing accessibility permission check logic (`AXIsProcessTrusted`).
- **Never**:
  - Execute AppleScript commands synchronously on the main thread.
  - Allow a late-running background request to overwrite a newer active application context snapshot.

## Success Criteria
- [ ] AppleScript execution runs on a background serial queue and does not block the AppKit menu or interface interactions.
- [ ] A request that fails to respond within 750 ms is cancelled and returns `.timedOut`.
- [ ] `AppSwitchMonitor` emits a single context update when the user switches tabs to a page with a different title but the same URL.
- [ ] Duplicate polls (where app, URL, and normalized title are unchanged) do not trigger engine evaluations or database logs.
- [ ] All unit tests compile, run, and pass.

## Open Questions
1. Should `AppleEventExecutor` fall back to native Accessibility APIs (`AXUIElement`) immediately if an AppleScript permission error occurs?
2. Do we want to persist the raw (unsanitized) window titles in the context history logs, or should they be sanitized/truncated in memory prior to persistence?



================================================================================
FILE: anchored-v2.6-plan.md
SIZE: 38459
================================================================================

# Implementation Plan: Anchored V2.6 — Context Reliability & Privacy-Ready History

> **Source specification:** [Anchored V2.6](./anchored-v2.6.md)

## 1. Overview and Planning Decisions

V2.6 hardens the V2.5 title/URL pipeline before CoreML work begins. Implementation proceeds through a thin, testable context stream first: validate the Apple Event execution mechanism, define canonical context values, collect without blocking, reject stale results, and propagate snapshots through `FocusEngine`. Once that live path is stable, the release adds deterministic dependency injection, sanitized opt-in persistence, privacy controls, asynchronous analytics, and privacy-safe diagnostics.

No V3 classifier, model update, cloud sync, or enforcement work is included.

### Decisions Locked for This Plan

- **Privacy navigation:** Add a dedicated **Privacy & Data** settings section. Consent to store context must not be hidden under general or about settings.
- **Persisted browser location:** Retain sanitized HTTP(S) paths, capped at 1,024 characters. Credentials, queries, and fragments are always removed.
- **History visibility:** V2.6 exposes consent, retention, count, oldest-record date, and deletion controls. It does not add a detailed history browser.
- **Polling cadence:** Use the existing 2.5-second cadence for browser and native contexts initially. Energy and latency measurements at the final checkpoint determine whether native polling needs a slower interval.
- **Migration recovery UI:** Defer a full repair/reset UI. V2.6 must return recoverable initialization errors and preserve the original database on migration failure.
- **Concurrency style:** Use completion-based APIs compatible with Swift 5.7 and deliver engine/UI mutations on the main queue.
- **Storage ownership:** Keep detailed observations in a dedicated `context_observations` table rather than extending `SessionEvent`.

### Fail-Fast Decision Gate

The Apple Event execution mechanism is not selected in advance. Task 1 must prove that the chosen mechanism is compatible with the app's signing/distribution model, can avoid main-thread blocking, and has workable timeout/cancellation semantics. Tasks 4–7 must not begin until that checkpoint is approved.

### Dependency Graph

```mermaid
graph TD
    A[Task 1: Validate Apple Event Executor] --> D[Task 4: Async AppleScript Strategies]
    B[Task 2: Context Snapshot & Identity] --> C[Task 3: Collector Orchestration]
    C --> D
    C --> E[Task 5: Safe AX Collection]
    D --> F[Task 6: AppSwitchMonitor Stream]
    E --> F
    F --> G[Task 7: FocusEngine Integration]

    G --> H[Task 8: List Provider Injection]
    H --> I[Task 9: Singleton-Free Engine Tests]
    J[Task 10: Deterministic Storage Writes] --> L[Task 12: GRDB Migrations]

    B --> K[Task 11: Persistence Sanitizer]
    K --> L
    L --> M[Task 13: Context History Recording]
    M --> N[Task 14: Retention & Deletion]
    G --> O[Task 15: History Pipeline Wiring]
    M --> O
    N --> P[Task 16: Privacy Settings]
    O --> P

    J --> Q[Task 17: Async Analytics Contracts]
    Q --> R[Task 18: Async Chart Migration]

    G --> S[Task 19: Diagnostics & Release Verification]
    I --> S
    P --> S
    R --> S
```

---

## 2. Task List

### Phase 0: Technical Decision Gate

#### Task 1: Validate the Apple Event Execution Mechanism

**Description:** Build a minimal test harness for candidate Apple Event execution mechanisms and select the implementation used by `ContextCollector`. Validate main-thread behavior, timeout handling, cancellation or late-result rejection, error fidelity, and compatibility with the current unsigned/development and intended release signing configurations. Record the decision and rejected alternatives before production refactoring begins.

**Acceptance criteria:**

- [ ] The selected executor runs browser context collection without synchronously blocking the main thread.
- [ ] A 750 ms response budget and non-overlapping request policy are demonstrated with success, timeout, and late-result cases.
- [ ] A short decision record documents signing assumptions, cancellation limitations, and why alternatives were rejected.

**Verification:**

- [ ] Run the executor harness against Safari and one Chromium browser.
- [ ] Confirm menus remain interactive while the harness simulates a blocked request.
- [ ] Review and approve the decision record before Task 4 starts.

**Dependencies:** None

**Files likely touched:**

- `AnchoredTests/Engine/AppleEventExecutorTests.swift`
- `docs/decisions/anchored-v2.6-apple-event-executor.md`

**Estimated scope:** S

### Checkpoint: Executor Gate

- [ ] Executor behavior is measured rather than assumed.
- [ ] Distribution/signing constraints are documented.
- [ ] Human review approves the selected mechanism.

---

### Phase 1: Canonical Context Foundation

#### Task 2: Define ContextSnapshot and ContextIdentity

**Description:** Add the canonical runtime context model, source enum, normalized identity, and deterministic normalization rules. Keep observation time out of equality used for deduplication, and cover Unicode, whitespace, control characters, title-only changes, and runtime URL identity.

**Acceptance criteria:**

- [ ] `ContextSnapshot` contains bundle ID, localized name, URL, title, source, and observation time.
- [ ] `ContextIdentity` detects bundle, URL, and normalized-title changes while suppressing equivalent snapshots.
- [ ] Normalization removes control characters and whitespace noise without lowercasing or corrupting user-visible titles.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/ContextSnapshotTests test`
- [ ] App target builds with the new models included.

**Dependencies:** None

**Files likely touched:**

- `Anchored/Models/ContextSnapshot.swift`
- `Anchored/Engine/ContextNormalizer.swift`
- `AnchoredTests/Models/ContextSnapshotTests.swift`
- `AnchoredTests/Engine/ContextNormalizerTests.swift`

**Estimated scope:** M

---

#### Task 3: Implement Collector Orchestration Primitives

**Description:** Define `ContextCollecting`, typed collection errors, cancellable request handles, a serial orchestration queue, a controllable scheduler, and generation-based stale-result rejection. Use mock providers only in this task so timeout and ordering semantics are proven independently from AppleScript and Accessibility APIs.

**Acceptance criteria:**

- [ ] The collector permits at most one active provider request and returns typed success/failure results.
- [ ] Requests exceeding 750 ms report `.timedOut`, and their later results are discarded.
- [ ] A newer generation cancels or invalidates older work while results are delivered on the configured callback queue.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/ContextCollectorTests test`
- [ ] Tests use a controllable scheduler and contain no real-time sleeps.

**Dependencies:** Task 2

**Files likely touched:**

- `Anchored/Engine/ContextCollector.swift`
- `Anchored/Engine/ContextCollectionRequest.swift`
- `AnchoredTests/Engine/ContextCollectorTests.swift`
- `AnchoredTests/Support/TestScheduler.swift`

**Estimated scope:** M

### Checkpoint: Context Foundation

- [ ] Context equality and normalization tests pass.
- [ ] Timeout, cancellation, and stale-generation behavior is deterministic.
- [ ] Application and test targets build cleanly.

---

### Phase 2: Reliable Live Context Stream

#### Task 4: Adapt Chromium and Safari Strategies to the Async Executor

**Description:** Integrate the Task 1 executor with Chromium and Safari strategies while retaining the existing single-transaction title/URL response format and Safari fallback behavior. Strategy failures become typed errors rather than silent `nil` values, and parsing remains independently unit-testable.

**Acceptance criteria:**

- [ ] Chromium and Safari collection runs through the selected non-blocking executor.
- [ ] Multi-line titles, empty titles, malformed URLs, permission errors, and Safari fallback are mapped deterministically.
- [ ] A timed-out or cancelled execution cannot publish a late browser context.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/BrowserStrategiesTests test`
- [ ] Manual check succeeds in Safari and one Chromium browser.

**Dependencies:** Tasks 1, 3

**Files likely touched:**

- `Anchored/Engine/BrowserStrategies.swift`
- `Anchored/Engine/AppleEventExecutor.swift`
- `AnchoredTests/Engine/BrowserStrategiesTests.swift`

**Estimated scope:** M

---

#### Task 5: Centralize Safe Accessibility Collection

**Description:** Create checked Accessibility value helpers and a standalone context provider shared by Firefox and native applications. Remove force casts, bound Firefox tree traversal, and distinguish permission denial, unavailable windows, invalid responses, and successful empty titles. Keep this task in new provider files so it can run in parallel with Task 4; `AppSwitchMonitor` performs the provider integration in Task 6.

**Acceptance criteria:**

- [ ] Accessibility values are validated through one helper with no unchecked `as!` or `unsafeBitCast` conversions.
- [ ] Firefox and native providers return typed results and bound recursive traversal by depth or visited-node count.
- [ ] Permission loss degrades to `.permissionDenied` without crashing or publishing a false empty context.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/AccessibilityContextProviderTests test`
- [ ] Manual check succeeds in Firefox, Xcode, and Terminal.

**Dependencies:** Tasks 2, 3

**Files likely touched:**

- `Anchored/Engine/AccessibilityValue.swift`
- `Anchored/Engine/AccessibilityContextProvider.swift`
- `AnchoredTests/Engine/AccessibilityContextProviderTests.swift`

**Estimated scope:** M

---

#### Task 6: Publish a Deduplicated Stream from AppSwitchMonitor

**Description:** Refactor `AppSwitchMonitor` to request contexts asynchronously, poll browsers and native apps, compare `ContextIdentity`, reject stale generations, and preserve app-only tracking before permission is granted. Inject collector and scheduler dependencies so behavior can be tested without real timers or applications.

**Acceptance criteria:**

- [ ] Title-only, URL-only, app, and native-window changes each emit one snapshot; identical polls emit none.
- [ ] App switches invalidate prior collection, and a late browser result cannot overwrite the current native context.
- [ ] Start, stop, sleep, wake, lock, and permission-loss paths release or suspend timers and requests correctly.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/AppSwitchMonitorTests test`
- [ ] App target builds and activation handling returns without synchronous collection.

**Dependencies:** Tasks 4, 5

**Files likely touched:**

- `Anchored/Engine/ActivityMonitor.swift`
- `Anchored/Engine/AppSwitchMonitor.swift`
- `AnchoredTests/Engine/AppSwitchMonitorTests.swift`
- `AnchoredTests/Support/MockContextCollector.swift`

**Estimated scope:** M

### Checkpoint: Live Monitor

- [ ] Safari, Chromium, Firefox, Xcode, and Terminal manual checks pass.
- [ ] Context collection does not block menus or overlays.
- [ ] Polling emits title-only changes and suppresses duplicates.
- [ ] Monitor tests pass without real timers or fixed waits.

---

#### Task 7: Integrate ContextSnapshot with FocusEngine

**Description:** Replace positional monitor callback arguments with `ContextSnapshot`, update `FocusEngine` state and notifications, and update mocks and downstream consumers. Preserve existing focus/distraction decisions by continuing to use the runtime URL while making the complete snapshot available to future consumers.

**Acceptance criteria:**

- [ ] `FocusEngine` consumes one `ContextSnapshot` and updates current app, URL, title, and context atomically.
- [ ] `.focusEngineContextDidChange` includes the snapshot and preserves compatibility keys needed by current observers during V2.6.
- [ ] Title-only events propagate without resetting focus timers or creating duplicate distraction events.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/FocusEngineTests -only-testing:AnchoredTests/ShadowTrackingEngineTests -only-testing:AnchoredTests/OverlayManagerTests test`
- [ ] Full application target builds.

**Dependencies:** Task 6

**Files likely touched:**

- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Engine/ShadowTrackingEngine.swift`
- `AnchoredTests/Engine/FocusEngineTests.swift`
- `AnchoredTests/Engine/ShadowTrackingEngineTests.swift`
- `AnchoredTests/Overlay/OverlayManagerTests.swift`

**Estimated scope:** M

---

### Phase 3: Deterministic Dependency and Test Boundaries

#### Task 8: Inject Focus and Distraction List Providers

**Description:** Introduce minimal read protocols for focus and distraction decisions, make `FocusListManager` accept injected defaults and distraction providers, remove XCTest detection from production code, and inject both providers into `FocusEngine`. Shared instances remain wired only at the application composition root.

**Acceptance criteria:**

- [ ] No production file checks `NSClassFromString("XCTest")` or otherwise changes behavior under tests.
- [ ] `FocusEngine` and `FocusListManager` use injected provider protocols for decisions.
- [ ] Production composition preserves current user-visible focus and distraction behavior.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/FocusEngineTests -only-testing:AnchoredTests/DistractionListManagerTests test`
- [ ] Search returns no XCTest detection in `Anchored/`.

**Dependencies:** Task 7

**Files likely touched:**

- `Anchored/Storage/FocusListManager.swift`
- `Anchored/Storage/DistractionListManager.swift`
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/App/AppDelegate.swift`
- `AnchoredTests/Engine/FocusEngineTests.swift`

**Estimated scope:** M

---

#### Task 9: Remove Shared Manager Mutation from Engine Tests

**Description:** Replace singleton backup/restore patterns with isolated `UserDefaults` suites and injected list providers in focus and shadow-tracking tests. Ensure teardown removes suites and temporary files without modifying application-global state.

**Acceptance criteria:**

- [ ] Engine tests never mutate `DistractionListManager.shared`, `FocusListManager.shared`, or `PreferencesManager.shared`.
- [ ] Every test fixture owns an isolated defaults suite and removes it during teardown.
- [ ] Reversed and parallel test execution produces the same results.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -parallel-testing-enabled YES -only-testing:AnchoredTests/FocusEngineTests -only-testing:AnchoredTests/ShadowTrackingEngineTests test`
- [ ] Search confirms no shared-manager mutation remains in those test files.

**Dependencies:** Task 8

**Files likely touched:**

- `AnchoredTests/Engine/FocusEngineTests.swift`
- `AnchoredTests/Engine/ShadowTrackingEngineTests.swift`
- `AnchoredTests/Support/TestDefaults.swift`

**Estimated scope:** S

---

#### Task 10: Add Deterministic Storage Write Completion

**Description:** Add completion-based storage writes and update tests to wait on actual database completion instead of arbitrary delayed expectations. Preserve the existing fire-and-forget convenience only where callers intentionally do not need acknowledgement.

**Acceptance criteria:**

- [ ] SQLite write success and failure are observable through a completion callback.
- [ ] Storage tests contain no `asyncAfter` or fixed sleep used to await writes.
- [ ] Write ordering remains serial and existing session APIs retain their results.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/SQLiteSessionStoreTests -only-testing:AnchoredTests/SessionStoreTests -only-testing:AnchoredTests/DashboardQueriesTests test`

**Dependencies:** None

**Files likely touched:**

- `Anchored/Storage/SQLiteSessionStore.swift`
- `Anchored/Storage/SessionStore.swift`
- `AnchoredTests/Storage/SQLiteSessionStoreTests.swift`
- `AnchoredTests/Storage/SessionStoreTests.swift`
- `AnchoredTests/Storage/DashboardQueriesTests.swift`

**Estimated scope:** M

### Checkpoint: Deterministic Core

- [ ] Engine tests use injected providers and isolated defaults.
- [ ] Storage tests synchronize on real completions.
- [ ] Relevant tests pass with parallel testing enabled.
- [ ] Production behavior no longer depends on XCTest presence.

---

### Phase 4: Sanitized Optional Context History

#### Task 11: Implement the Persistence Sanitizer

**Description:** Add a pure sanitizer for persisted titles and URLs, separate from runtime matching normalization. It must cap titles and paths, retain only HTTP(S), remove credentials/query/fragment, normalize hosts, and produce values suitable for both context observations and `SessionEvent.url` writes.

**Acceptance criteria:**

- [ ] Titles are normalized and capped at 512 extended grapheme clusters without splitting visible characters.
- [ ] Persisted URLs retain scheme, normalized host, and capped path while removing credentials, query, and fragment.
- [ ] Invalid and non-HTTP(S) URLs produce `nil` rather than partially trusted output.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/ContextSanitizerTests test`

**Dependencies:** Task 2

**Files likely touched:**

- `Anchored/Engine/ContextSanitizer.swift`
- `AnchoredTests/Engine/ContextSanitizerTests.swift`

**Estimated scope:** S

---

#### Task 12: Replace Ad Hoc Setup with Versioned GRDB Migrations

**Description:** Introduce a versioned `DatabaseMigrator`, create `context_observations` and its timestamp index, sanitize legacy non-null session URLs in place, and make migration failure recoverable without deleting or replacing the source database. Keep JSON import behavior intact.

**Acceptance criteria:**

- [ ] A V2.5 fixture migrates with all session rows and metadata preserved while unsafe URL components are removed.
- [ ] Running migrations repeatedly is idempotent and does not duplicate or rewrite valid rows.
- [ ] Migration errors are returned to the caller and never trigger a runtime `fatalError` after database creation begins.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/SQLiteMigrationTests test`
- [ ] Inspect migrated fixture SQL to confirm queries, fragments, and credentials are absent.

**Dependencies:** Tasks 10, 11

**Files likely touched:**

- `Anchored/Storage/SQLiteSessionStore.swift`
- `Anchored/Storage/DatabaseMigrations.swift`
- `AnchoredTests/Storage/SQLiteMigrationTests.swift`
- `AnchoredTests/Fixtures/anchored-v2.5.db`

**Estimated scope:** M

---

#### Task 13: Record Opt-In Context Observations

**Description:** Add the persisted observation model and a `ContextHistoryStore` that writes sanitized, deduplicated snapshots only when consent is enabled. Route all future `SessionEvent.url` writes through the same URL sanitizer without changing runtime URL matching.

**Acceptance criteria:**

- [ ] No observation row is written when detailed history is disabled.
- [ ] Enabled writes contain only sanitized fields and suppress consecutive identical sanitized identities.
- [ ] New session events never persist credentials, queries, fragments, or unsupported URL schemes.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/ContextHistoryStoreTests -only-testing:AnchoredTests/SessionEventTests test`

**Dependencies:** Task 12

**Files likely touched:**

- `Anchored/Models/PersistedContextObservation.swift`
- `Anchored/Storage/ContextHistoryStore.swift`
- `Anchored/Storage/SQLiteSessionStore.swift`
- `AnchoredTests/Storage/ContextHistoryStoreTests.swift`

**Estimated scope:** M

### Checkpoint: Safe Persistence

- [ ] V2.5 migration preserves event counts and aggregate results.
- [ ] Existing and future persisted URLs are sanitized.
- [ ] Detailed history remains off by default.
- [ ] No raw title or unsafe URL component appears in the fixture database.

---

#### Task 14: Implement Retention, Clearing, and History Summary

**Description:** Add transactional retention cleanup, immediate clearing, observation count, and oldest-record queries. Inject a clock so launch cleanup and the once-per-24-hours guard can be tested deterministically.

**Acceptance criteria:**

- [ ] One-, seven-, and thirty-day retention removes only expired observations.
- [ ] Clearing removes all context observations while preserving every session row and dashboard aggregate.
- [ ] Count and oldest-date queries complete asynchronously and return typed failures.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/ContextHistoryStoreTests test`

**Dependencies:** Task 13

**Files likely touched:**

- `Anchored/Storage/ContextHistoryStore.swift`
- `Anchored/Storage/SQLiteSessionStore.swift`
- `AnchoredTests/Storage/ContextHistoryStoreTests.swift`
- `AnchoredTests/Support/TestClock.swift`

**Estimated scope:** M

---

#### Task 15: Wire Context History into the Engine Pipeline

**Description:** Add a dedicated context-history pipeline that observes accepted `FocusEngine` context notifications and persists snapshots after live focus decisions complete. Keep persistence out of `FocusEngine` so failures and future storage changes cannot affect decision logic. Enabling or disabling consent must take effect without restarting the app.

**Acceptance criteria:**

- [ ] Accepted context notifications are offered to the history recorder asynchronously after live focus evaluation.
- [ ] Consent changes begin or stop writes immediately while runtime monitoring remains unchanged.
- [ ] Storage failure cannot clear current context, alter focus state, or block the main thread.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/FocusEngineTests -only-testing:AnchoredTests/ContextHistoryStoreTests test`
- [ ] Manual check confirms opt-in writes and opt-out suppression without relaunching.

**Dependencies:** Tasks 7, 13

**Files likely touched:**

- `Anchored/Engine/ContextHistoryPipeline.swift`
- `Anchored/Storage/ContextHistoryStore.swift`
- `Anchored/App/AppDelegate.swift`
- `AnchoredTests/Engine/ContextHistoryPipelineTests.swift`

**Estimated scope:** M

---

### Phase 5: Privacy Controls

#### Task 16: Add the Privacy & Data Settings Pane

**Description:** Add an explicit settings section with opt-in, retention picker, asynchronous history summary, and confirmed destructive clearing. Extend `PreferencesManager` with injected-defaults-backed settings, add supported translations, and keep Accessibility permission copy distinct from storage consent.

**Acceptance criteria:**

- [ ] Detailed history defaults off, and enabling it shows the local-storage disclosure before consent is saved.
- [ ] Retention offers 1, 7, and 30 days; disabling or clearing requires confirmation and preserves session analytics.
- [ ] The pane exposes loading, loaded, empty, and failure states for count/oldest-date summary with accessible labels and English fallback.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/PreferencesManagerTests -only-testing:AnchoredTests/ContextHistoryStoreTests test`
- [ ] Manual keyboard and VoiceOver check passes for the new pane and confirmation flow.
- [ ] App target builds with every `SettingsSection` switch exhaustive.

**Dependencies:** Tasks 14, 15

**Files likely touched:**

- `Anchored/Storage/PreferencesManager.swift`
- `Anchored/MenuBar/SettingsView.swift`
- `Anchored/Onboarding/LanguageManager.swift`
- `AnchoredTests/Storage/PreferencesManagerTests.swift`

**Estimated scope:** M

### Checkpoint: User-Controlled History

- [ ] Permission to read context and consent to store history are separate controls.
- [ ] Opt-in, retention, summary, opt-out, and clear flows work without relaunch.
- [ ] Session charts and streaks survive detailed-history clearing.
- [ ] New settings copy is localized with English fallback.

---

### Phase 6: Non-Blocking Analytics

#### Task 17: Introduce Async Dashboard Query Contracts

**Description:** Replace tuple-based synchronous chart boundaries with named bucket/distribution models and a `DashboardQuerying` protocol. Execute reads on the storage utility queue, return results on a documented callback queue, preserve injected calendar semantics, and add large-fixture and daylight-saving tests.

**Acceptance criteria:**

- [ ] Hourly, daily, and app/domain distribution APIs return named values asynchronously with typed errors.
- [ ] Existing totals and ordering remain unchanged for current fixtures, including DST boundaries and missing durations.
- [ ] Query callers can identify and discard stale responses without cancelling database integrity work.

**Verification:**

- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/DashboardQueriesTests test`
- [ ] A 100,000-event fixture query does not block the main thread.

**Dependencies:** Task 10

**Files likely touched:**

- `Anchored/Models/DashboardModels.swift`
- `Anchored/Storage/DashboardQueries.swift`
- `AnchoredTests/Storage/DashboardQueriesTests.swift`

**Estimated scope:** M

---

#### Task 18: Migrate Captain's Charts to Async Load States

**Description:** Inject `DashboardQuerying` into the Tidal Wave, Constellation, and Fleet Tree views; add explicit idle/loading/loaded/empty/failed states; and use request generations so rapid range changes cannot display stale results. Preview mock data must remain preview-only.

**Acceptance criteria:**

- [ ] Voyage Logs performs no synchronous SQLite query from `body`, `onAppear`, or range-change handlers.
- [ ] All three charts render loading, empty, loaded, and retryable failure states without substituting production mock data.
- [ ] Rapid Tidal Wave range changes display only the newest request's result.

**Verification:**

- [ ] App target builds: `xcodebuild -project Anchored.xcodeproj -scheme Anchored -destination 'platform=macOS' build`
- [ ] Tests pass: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -only-testing:AnchoredTests/DashboardQueriesTests test`
- [ ] Manual check covers empty, populated, failed, and rapid-range scenarios.

**Dependencies:** Task 17

**Files likely touched:**

- `Anchored/App/Views/TidalWaveChartView.swift`
- `Anchored/App/Views/ConstellationHeatmapView.swift`
- `Anchored/App/Views/FleetTreeSpreadmapView.swift`
- `AnchoredTests/Storage/DashboardQueriesTests.swift`

**Estimated scope:** M

### Checkpoint: Responsive Analytics

- [ ] Voyage Logs stays interactive during large reads.
- [ ] Chart totals match pre-V2.6 fixture results.
- [ ] Empty and error states are distinct.
- [ ] Stale chart responses are discarded.

---

### Phase 7: Diagnostics and Release Verification

#### Task 19: Add Privacy-Safe Diagnostics and Complete Release Verification

**Description:** Add rate-limited collection/storage diagnostics containing only source, outcome, duration, and counters; then complete the full automated, manual, performance, migration, and soak-test matrix. Raw titles and URLs must never be interpolated into logs or signposts.

**Acceptance criteria:**

- [ ] Diagnostics report collection duration/outcome, stale/duplicate counts, persistence counts, and retention deletions without content values.
- [ ] Main-thread profiling, 100,000-row analytics checks, migration checks, and the eight-hour polling soak meet the spec targets.
- [ ] The full test suite passes with parallel execution and no fixed-wait synchronization.

**Verification:**

- [ ] Full suite: `xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' -parallel-testing-enabled YES test`
- [ ] Release build: `xcodebuild -project Anchored.xcodeproj -scheme Anchored -configuration Release -destination 'platform=macOS' build`
- [ ] Manual matrix passes for Safari, one Chromium browser, Firefox, Xcode, Terminal, Privacy & Data, and Voyage Logs.
- [ ] Search release logs and source to confirm no raw title/full URL logging paths exist.

**Dependencies:** Tasks 9, 16, 18

**Files likely touched:**

- `Anchored/Engine/ContextDiagnostics.swift`
- `Anchored/Engine/ContextCollector.swift`
- `Anchored/Storage/ContextHistoryStore.swift`
- `AnchoredTests/Engine/ContextDiagnosticsTests.swift`
- `docs/ideas/anchored-v2.6-plan.md`

**Estimated scope:** M

### Checkpoint: V2.6 Complete

- [ ] Every success criterion in `anchored-v2.6.md` is checked against evidence.
- [ ] Debug and release builds succeed.
- [ ] Full parallel test suite passes.
- [ ] Migration and deletion preserve session data.
- [ ] Main-thread and soak targets pass.
- [ ] No raw context is logged or persisted outside explicit consent boundaries.
- [ ] Release is ready for code review and manual acceptance.

---

## 3. Parallelization Approach

The work is organized into execution waves. Tasks inside a track remain sequential; tracks within the same wave run concurrently. Each wave ends at a merge gate where the listed tests and build must pass before dependent work starts.

### Execution Wave Table

| Wave | Runtime Context Track | Context & Privacy Track | Storage, Analytics & Quality Track | Merge gate |
|---|---|---|---|---|
| **0 — Foundations** | **Task 1:** Validate Apple Event executor | **Task 2 → Task 3:** Context models, then collector primitives | **Task 10:** Deterministic storage completion | Executor approved; context/collector tests pass; storage tests pass |
| **1 — Providers** | **Task 4:** Chromium/Safari async provider | **Task 5:** Firefox/native Accessibility provider | **Task 11 → Task 12:** Sanitizer, then migrations | Browser/AX providers pass independently; V2.5 migration fixture passes |
| **2 — Vertical slices** | **Task 6 → Task 7:** Monitor stream, then FocusEngine propagation | **Task 13 → Task 14:** Opt-in recording, then retention/deletion | **Task 17:** Async analytics contracts | Live stream passes end-to-end; storage boundary is consent-safe; query tests pass |
| **3 — Product integration** | **Task 8 → Task 9:** Provider injection, then singleton-free tests | **Task 15 → Task 16:** History pipeline, then Privacy & Data UI | **Task 18:** Migrate all charts | Parallel test suite passes; privacy flow works; Voyage Logs is non-blocking |
| **4 — Convergence** | **Task 19:** Diagnostics and release verification | Support Task 19 migration/privacy checks | Support Task 19 analytics/performance checks | Full release build, parallel suite, manual matrix, and soak test pass |

### Wave Details

#### Wave 0: Three Independent Foundations

- The **Runtime Context Track** validates the riskiest external API first.
- The **Context & Privacy Track** defines `ContextSnapshot` and collector behavior without waiting for the real executor.
- The **Storage, Analytics & Quality Track** removes fixed storage waits, unblocking migrations and analytics tests.
- Task 3 starts only after Task 2, but both remain independent of Tasks 1 and 10.

#### Wave 1: Provider and Persistence Work

- Tasks 4 and 5 run in parallel because Task 5 is isolated in new Accessibility provider files; Task 4 owns `BrowserStrategies.swift` during this wave.
- Tasks 11 and 12 run sequentially on the storage track because migrations depend on the finalized sanitizer.
- Task 12 owns `SQLiteSessionStore.swift` until the wave merges.

#### Wave 2: Three End-to-End Slices

- The context track delivers activation/polling through `FocusEngine` before dependency-injection cleanup begins.
- The privacy track delivers actual opt-in storage, retention, deletion, and summary queries.
- The analytics track changes query contracts in `DashboardQueries.swift` without touching chart UI.
- These tracks have no planned shared production files in this wave.

#### Wave 3: User-Facing Integration

- Task 8 lands its application-composition changes before Task 15 edits `AppDelegate.swift`; Task 9 can continue in parallel after Task 8's production changes merge.
- Task 15 uses a notification-driven `ContextHistoryPipeline`, avoiding concurrent changes to `FocusEngine.swift`.
- Task 16 owns `SettingsView.swift`; Task 18 modifies only the three chart view files and query tests.
- The wave is partially staggered around `AppDelegate.swift`, but test cleanup, privacy UI, and chart migration otherwise proceed concurrently.

#### Wave 4: Single Convergence Owner

Task 19 has one integration owner. Other tracks assist with evidence collection and fixes, but only the integration owner changes shared diagnostics or plan/checklist state. This prevents last-mile verification from producing competing edits across core files.

### Critical Path

The longest dependency chain is:

```text
Task 2 → Task 3 → Tasks 4/5 → Task 6 → Task 7
                                      └→ Task 15 → Task 16 → Task 19

Task 2 → Task 11 ─┐
                  ├→ Task 12 → Task 13 → Task 14 → Task 16
Task 10 ──────────┘
```

Task 1 gates Task 4. Task 17 → Task 18 forms a shorter parallel analytics path that must converge before Task 19.

### Shared-File Ownership

| File | Owning task/wave | Coordination rule |
|---|---|---|
| `BrowserStrategies.swift` | Task 4 / Wave 1 | Task 5 stays in new Accessibility provider files; integration occurs in Task 6. |
| `FocusEngine.swift` | Tasks 7 then 8 | Sequential ownership; Task 15 observes notifications instead of editing the engine. |
| `SQLiteSessionStore.swift` | Tasks 10, 12, 13, 14 | Storage tasks merge sequentially; analytics stays in `DashboardQueries.swift`. |
| `AppDelegate.swift` | Tasks 8 then 15 | Task 8 composition changes merge before Task 15 wiring begins. |
| `SettingsView.swift` | Task 16 | Task 18 stays inside chart files to avoid a UI merge conflict. |

### Must Remain Sequential

- Task 1 before Task 4.
- Task 2 before Task 3 and Task 11.
- Tasks 4 and 5 before Task 6; Task 6 before Task 7.
- Task 7 before Task 8 and Task 15.
- Task 8 production composition before Task 15 application wiring.
- Tasks 11 → 12 → 13 → 14 in order.
- Task 15 and Task 14 before Task 16.
- Task 17 before Task 18.
- All feature checkpoints before Task 19.

---

## 4. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Apple Event APIs cannot be safely cancelled or moved off the main thread under the intended distribution model. | High | Resolve in Task 1; use serial non-overlapping work and late-result rejection where hard cancellation is unavailable. Do not begin monitor refactoring without approval. |
| V2.5 databases contain raw URLs with sensitive query data. | High | Sanitize legacy rows transactionally during a tested, idempotent migration; preserve a recoverable failure path. |
| Polling native windows every 2.5 seconds increases energy use. | Medium | Query only the frontmost process, suppress duplicates, suspend on sleep/lock, measure at Task 19, and slow native cadence if targets fail. |
| Firefox Accessibility traversal becomes slow or cyclic. | Medium | Bound recursion by visited-node count/depth, validate types, enforce collector budgets, and add malformed-tree fixtures. |
| Snapshot signature refactoring causes broad test churn. | Medium | Land `ContextSnapshot` first, retain compatibility notification keys for V2.6, and update one vertical monitor-to-engine path before storage/UI work. |
| Migration failure prevents app launch. | High | Use explicit migrations, fixture tests, recoverable initialization errors, and never delete/replace the original database automatically. |
| Context history consent is accidentally bypassed. | High | Enforce opt-in inside the storage boundary, not only UI/engine callers; test disabled writes directly. |
| Async chart results arrive out of order. | Medium | Use per-view request generations and test rapid range changes with controlled query doubles. |
| Existing dirty worktree changes overlap planned files. | Medium | Review `git diff` before each task, preserve unrelated edits, and avoid broad formatting rewrites. |

---

## 5. Deferred Decisions and Non-Goals

The following are explicitly deferred unless implementation evidence forces reconsideration:

- A user-facing detailed context history browser.
- Domain-only persistence instead of sanitized paths; the approved plan uses sanitized paths.
- A full corrupt-database repair/reset UI.
- CoreML labels, inference, training, and feedback collection.
- iCloud or any remote synchronization.
- Third-party logging, analytics, or crash-reporting dependencies.
- Changes to the ten-session Accessibility permission gate.

If Task 1 cannot identify a viable executor, V2.6 implementation is blocked at the Executor Gate and the spec must be revised before proceeding.

---

## 6. Plan Approval

- [ ] Task ordering and dependency graph approved.
- [ ] Apple Event executor spike approved as the first implementation task.
- [ ] Dedicated Privacy & Data settings section approved.
- [ ] Sanitized-path persistence policy approved.
- [ ] Implementation may begin with Task 1 only.



================================================================================
FILE: anchored-v2.6.md
SIZE: 30823
================================================================================

# Anchored V2.6 — Context Reliability & Privacy-Ready History

> **Prerequisite:** This specification assumes [Anchored V2.5](./anchored-v2.5.md) has shipped and its title/URL context pipeline and Captain's Charts are stable. V2.6 hardens that pipeline before the CoreML classifier, local model updates, iCloud sync, and enforcement features proposed for [Anchored V3](./anchored-v3.md).

## Assumptions

1. V2.6 is a reliability and privacy release, not the first CoreML release.
2. Browser and native-window context remains available only after the existing Accessibility permission gate is satisfied.
3. Full runtime URLs may be used transiently for matching, but credentials, query strings, and fragments must not be persisted. Raw titles must not be persisted without explicit user consent.
4. Detailed context history is disabled by default, remains entirely on-device, and has a bounded retention period.
5. Existing V2.5 session history must survive all V2.6 database migrations.
6. macOS 13 and Swift 5.7 remain the minimum supported platform and language versions.

If product direction requires detailed history to be enabled by default, that is a separate privacy decision and must be approved before implementation.

---

## Problem Statement

**How might we** make Anchored's enriched context stream reliable enough for future intent classification without blocking the UI, missing title-only navigation, leaking state across tests, or silently retaining sensitive window and page content?

V2.5 added page titles, native window titles, and URL propagation, but four architectural gaps remain:

- Browser polling publishes only when the URL changes. Dynamic document titles, single-page application navigation, and same-URL tab changes may be lost.
- AppleScript and Accessibility collection can execute synchronously on the activation or timer path, creating visible stalls when another application is slow or unresponsive.
- Detailed title context is transient and has no defined privacy, normalization, retention, or migration contract.
- Dashboard reads and singleton-dependent tests still use synchronous or globally mutable patterns that reduce responsiveness and test determinism.

## V2.6 Summary

V2.6 introduces five related improvements:

1. **Canonical Context Stream** — Replace URL-only deduplication with a stable context identity that detects changes to bundle ID, URL, and normalized title.
2. **Non-Blocking Context Collection** — Move browser/native metadata retrieval behind an asynchronous collector with stale-result rejection and bounded execution.
3. **Privacy-Ready Local Context History** — Add an opt-in, sanitized, retention-limited SQLite history suitable for future on-device learning and debugging.
4. **Asynchronous Analytics Reads** — Replace main-thread-blocking dashboard reads with completion-based background APIs and explicit loading/error states.
5. **Deterministic Test Isolation** — Remove production behavior that depends on detecting XCTest and stop mutating shared list-manager singletons in tests.

V2.6 does not classify, upload, synchronize, or enforce based on titles. It establishes a reliable and reviewable boundary for those future capabilities.

---

## 1. Canonical Context Stream

### Current Limitation

`AppSwitchMonitor` currently tracks only `lastPolledURL`. During browser polling, it emits a new context when the URL changes:

```swift
if currentURL != lastPolledURL {
    lastPolledURL = currentURL
    onContextChange?(bundleID, currentURL, title)
}
```

This misses meaningful changes such as:

- a YouTube or music page updating the document title while retaining its URL;
- a single-page application replacing content without producing a materially different URL;
- switching between tabs that expose the same URL but different titles;
- a native application changing its focused document or terminal window without being reactivated.

### ContextSnapshot

V2.6 defines one value type for monitor-to-engine communication:

```swift
struct ContextSnapshot: Equatable {
    enum Source: String, Codable {
        case application
        case chromium
        case safari
        case firefox
    }

    let bundleIdentifier: String
    let localizedName: String
    let url: URL?
    let title: String
    let source: Source
    let observedAt: Date
}
```

`ActivityMonitor` publishes snapshots instead of parallel positional arguments:

```swift
protocol ActivityMonitor: AnyObject {
    var onContextChange: ((ContextSnapshot) -> Void)? { get set }
    func start()
    func stop()
}
```

This avoids signature churn when V3 adds classification metadata and makes test fixtures readable.

### Context Identity and Deduplication

`observedAt` must not participate in deduplication. The monitor derives a `ContextIdentity` from normalized content:

```swift
struct ContextIdentity: Equatable {
    let bundleIdentifier: String
    let canonicalURL: String?
    let normalizedTitle: String
}
```

Normalization rules:

1. Trim leading and trailing whitespace and newlines.
2. Replace internal runs of whitespace with one space.
3. Remove control characters and null bytes.
4. Compare URL schemes and hosts case-insensitively.
5. Remove an empty trailing URL fragment, but retain non-empty paths, queries, and fragments for **runtime change detection only**.
6. Do not lowercase titles; title case can carry meaningful context.

The monitor publishes when any identity field changes. Identical polls are suppressed.

### Native Window Refresh

Native app titles currently refresh only on application activation. V2.6 refreshes the active native window on the same polling cadence used for browsers while Accessibility access remains trusted.

To control energy use:

- default poll interval remains 2.5 seconds;
- polling stops when the screen sleeps, the session is locked, or monitoring stops;
- only the frontmost process is queried;
- duplicate snapshots are suppressed before reaching `FocusEngine`;
- no polling occurs before Accessibility permission is granted.

### Acceptance Criteria

- A title-only browser change emits exactly one new `ContextSnapshot`.
- A native focused-window title change emits without requiring an app switch.
- Repeated identical polls do not notify `FocusEngine`.
- Context events preserve their original collection order.
- The current Anchored application is excluded from tracking.
- Revoking Accessibility permission stops privileged polling without stopping basic application-switch tracking.

---

## 2. Non-Blocking Context Collection

### Collector Boundary

Browser strategy execution is isolated behind an asynchronous interface:

```swift
protocol ContextCollecting {
    @discardableResult
    func collect(
        for application: NSRunningApplication,
        completion: @escaping (Result<ContextSnapshot, ContextCollectionError>) -> Void
    ) -> ContextCollectionRequest
}

protocol ContextCollectionRequest {
    func cancel()
}
```

The implementation uses a dedicated serial utility queue for collection orchestration. Results are delivered on the main queue because `FocusEngine`, timers, and UI-facing notifications currently assume main-thread ordering.

Apple Event execution must use a mechanism proven safe outside the main run loop. If the existing `NSAppleScript` implementation cannot satisfy that requirement, implementation must switch to a cancellable Apple Event executor rather than dispatching `NSAppleScript` blindly to a concurrent queue.

### Generation-Based Stale Result Rejection

Slow collection can return after the user has already switched applications. `AppSwitchMonitor` assigns each request a monotonically increasing generation:

```swift
generation += 1
let requestGeneration = generation

collector.collect(for: app) { [weak self] result in
    guard let self, requestGeneration == self.generation else { return }
    self.consume(result)
}
```

Starting a newer request cancels the previous request where cancellation is supported. Generation validation remains mandatory because cancellation may race with process completion.

### Time Budget and Failure Semantics

- Collection budget: **750 ms** per poll.
- A timeout produces `.timedOut`; it does not publish an empty context over the last known valid context.
- Permission failures produce `.permissionDenied` and stop privileged polling until trust changes.
- Missing windows or tabs produce `.contextUnavailable` and may be retried on the next poll.
- Invalid or unsupported URLs produce `.invalidResponse` and must not crash parsing.
- Failures are rate-limited in logs so a broken browser does not generate unbounded console output.

The 750 ms budget is a response budget, not permission to forcibly terminate unsafe framework work. Executors that cannot be cancelled must discard late results and avoid starting overlapping work.

### Performance Targets

- App activation handling returns to the main run loop within **16 ms**, excluding AppKit's own notification delivery.
- No AppleScript, Accessibility-tree walk, SQLite read, or title normalization loop runs synchronously on the main thread.
- At most one collection request is active at a time.
- Idle memory growth remains below **5 MB** over an eight-hour monitoring run.
- Median context collection completes under **150 ms** on a supported local browser; the 95th percentile remains under **500 ms** in release builds.

### Acceptance Criteria

- A deliberately blocked mock executor does not freeze menus, overlays, or settings.
- Switching from Browser A to App B before Browser A returns cannot overwrite App B's context.
- A timeout does not clear or misclassify the last valid context.
- Polling never creates overlapping Apple Event transactions.
- Start/stop cycles release timers, requests, and notification observers.

---

## 3. Privacy-Ready Local Context History

### Privacy Model

Window titles may contain repository names, document names, private messages, search terms, customer names, or terminal hostnames. V2.6 treats them as sensitive local data.

Detailed history follows these rules:

- disabled by default;
- enabled only through an explicit Settings toggle labeled **Store Detailed Context History**;
- accompanied by plain-language disclosure that titles and sanitized URLs are stored locally;
- never uploaded, synchronized, exported, or included in diagnostics in V2.6;
- deletable immediately through **Clear Detailed History**;
- automatically deleted after the selected retention period;
- excluded from existing session statistics when history is disabled or cleared.

The URL sanitization rule applies to every new database write, including existing `SessionEvent.url` fields. Detailed-history consent governs title/history retention; it does not make unsafe URL components acceptable in session events.

Supported retention values are 1 day, 7 days, and 30 days. The default after opting in is 7 days.

### Separation from Session Events

Detailed observations are not added to `SessionEvent`. Session events represent durable product events such as starts, ends, and escalations; context observations are higher-frequency and have different privacy and retention requirements.

V2.6 adds a dedicated table:

```sql
CREATE TABLE context_observations (
    id TEXT PRIMARY KEY NOT NULL,
    observedAt DATETIME NOT NULL,
    bundleID TEXT NOT NULL,
    appName TEXT NOT NULL,
    source TEXT NOT NULL,
    title TEXT NOT NULL,
    sanitizedURL TEXT,
    domain TEXT,
    sessionState TEXT NOT NULL
);

CREATE INDEX idx_context_observations_observedAt
ON context_observations(observedAt);
```

The schema intentionally omits raw URLs, query parameters, fragments, user information, cookies, DOM content, and classification labels.

### Persistence Sanitization

Runtime matching continues to receive the full in-memory URL. Persistence uses a separate sanitizer:

```swift
struct PersistedContextObservation {
    let observedAt: Date
    let bundleID: String
    let appName: String
    let source: ContextSnapshot.Source
    let title: String
    let sanitizedURL: String?
    let domain: String?
    let sessionState: SessionState
}
```

Before writing:

1. Normalize title whitespace and remove control characters.
2. Truncate titles to **512 extended grapheme clusters** without splitting user-visible characters.
3. Accept only `http` and `https` URLs for browser persistence.
4. Remove username, password, query, and fragment components.
5. Lowercase and IDNA-normalize the host.
6. Retain the path, capped at **1,024 characters**, because paths often distinguish work from distraction.
7. Store native-app observations with `sanitizedURL = nil`.
8. Skip observations whose sanitized identity matches the most recently stored identity.

Examples:

| Runtime value | Persisted value |
|---|---|
| `https://user:pass@example.com/issues/42?token=secret#comment` | `https://example.com/issues/42` |
| `https://www.youtube.com/watch?v=abc123` | `https://www.youtube.com/watch` |
| Native Xcode window title | Normalized title with no URL |

### Retention and Deletion

Retention cleanup runs:

- after application launch;
- after the user changes retention settings;
- at most once every 24 hours during normal operation.

Deletion is performed on the storage utility queue in one transaction. Turning the feature off deletes all detailed observations immediately after confirmation; it does not delete aggregate session events.

### Migration Requirements

- Use an explicit, idempotent GRDB migration rather than ad hoc column inspection.
- Creating `context_observations` must not rewrite or delete the existing `sessions` table.
- Sanitize non-null legacy `sessions.url` values in place during migration so previously retained credentials, queries, and fragments do not remain indefinitely.
- Route all future `SessionEvent.url` writes through the same persistence sanitizer.
- A failed migration must leave the previous database readable and surface a recoverable storage error rather than calling `fatalError` for runtime migration failures.
- Tests must cover migration from the current V2.5 schema and a second launch against the migrated schema.

### Acceptance Criteria

- No observation is written while detailed history is disabled.
- Opting in writes only normalized titles and sanitized URLs.
- Query strings, fragments, credentials, and unsupported URL schemes never reach SQLite.
- Existing unsafe `sessions.url` values are sanitized without changing their associated event metadata.
- Retention removes only expired detailed observations.
- Clearing detailed history leaves session totals, streaks, and charts intact.
- Database migration preserves all existing `SessionEvent` rows.

---

## 4. Asynchronous Analytics Reads

### Current Limitation

The V2.5 chart queries dispatch synchronously to a utility queue. Calling them from SwiftUI's `onAppear` still blocks the caller until the query and aggregation finish.

V2.6 exposes asynchronous query methods:

```swift
protocol DashboardQuerying {
    func focusTimePerHourForLast24Hours(
        relativeTo date: Date,
        completion: @escaping (Result<[FocusBucket], Error>) -> Void
    )

    func focusTimePerDay(
        since startDate: Date,
        to endDate: Date,
        completion: @escaping (Result<[FocusBucket], Error>) -> Void
    )
}

struct FocusBucket: Equatable {
    let startDate: Date
    let duration: TimeInterval
}
```

Named result types replace tuple-heavy public boundaries, making ordering and equality testable.

### View State

Each chart uses explicit state:

```swift
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed
}
```

Requirements:

- Chart views show lightweight placeholders while loading.
- Empty datasets show the existing empty-state treatment, not preview mock data.
- Preview-only mock data remains restricted to SwiftUI previews.
- Failed reads show a non-blocking retry affordance.
- Stale query results are discarded when the user changes chart range rapidly.

### Aggregation Correctness

- Hourly and daily buckets are ordered oldest to newest.
- Calendar arithmetic honors daylight-saving transitions and the injected calendar/time zone.
- A session contributes according to the timestamp semantics already defined for `sessionEnd`; V2.6 does not change historical attribution rules.
- Missing durations contribute zero rather than crashing or creating negative values.

### Acceptance Criteria

- Opening Voyage Logs does not perform synchronous SQLite work on the main thread.
- Rapidly switching chart ranges cannot display results for the previously selected range.
- Charts correctly represent empty, loading, loaded, and failed states.
- Existing analytics totals remain unchanged for the same fixture data.

---

## 5. Deterministic Test Isolation

### Remove XCTest-Dependent Production Behavior

Production classes must not change behavior by checking for the presence of XCTest:

```swift
// Remove this pattern from production code.
if NSClassFromString("XCTest") != nil {
    return !DistractionListManager.shared.isDistraction(bundleID)
}
```

`FocusListManager` and `DistractionListManager` instead expose injectable instances backed by injected `UserDefaults`. Consumers receive protocols:

```swift
protocol FocusListProviding {
    func isFocusApp(_ bundleID: String) -> Bool
}

protocol DistractionListProviding {
    func isDistraction(_ bundleID: String) -> Bool
}
```

The application composition root may continue to provide `.shared`. Tests must construct isolated providers.

### Test Storage Synchronization

Tests must not sleep or use arbitrary delayed expectations to wait for SQLite writes. Storage exposes a completion or testable synchronous transaction boundary:

```swift
func log(
    _ event: SessionEvent,
    completion: @escaping (Result<Void, Error>) -> Void
)
```

### Isolation Rules

- Every test receives a unique temporary database and `UserDefaults` suite.
- Tests do not mutate `DistractionListManager.shared`, `FocusListManager.shared`, or `PreferencesManager.shared`.
- Temporary suites and directories are removed in `tearDown`.
- Time-sensitive components receive an injected clock or explicit reference date.
- Polling tests use a controllable scheduler rather than real 2.5-second timers.

### Acceptance Criteria

- The full test suite passes with test parallelization enabled.
- Reversing test execution order does not change results.
- No production type branches on XCTest availability.
- Storage tests contain no fixed sleeps used as synchronization.
- Context collector timeout and stale-result tests complete deterministically.

---

## 6. Settings and User Experience

V2.6 adds a **Privacy & Data** section under Settings → Rigging or Crew Info, depending on the final navigation decision.

Controls:

- **Store Detailed Context History** toggle, off by default.
- **Keep History For** picker: 1 day, 7 days, or 30 days.
- **Clear Detailed History…** destructive button with confirmation.
- A short disclosure: “When enabled, Anchored stores normalized window titles and sanitized web addresses on this Mac. Query strings, fragments, and credentials are not stored.”
- Current storage count and oldest retained observation, fetched asynchronously.

The permission gate must not imply that granting Accessibility permission automatically enables persistence. Permission to read context and consent to retain context are separate decisions.

### Accessibility and Localization

- All controls have stable accessibility labels and keyboard focus behavior.
- New copy is added for every language supported by `LanguageManager`.
- Missing translations fall back to English rather than raw localization keys.
- Destructive actions use standard macOS confirmation semantics.

---

## 7. Observability and Diagnostics

V2.6 adds privacy-safe operational signals for development builds:

- collection duration;
- source type;
- success, timeout, permission denied, unavailable, or invalid response;
- stale result discarded count;
- duplicate snapshot suppressed count;
- persisted observation count and retention deletion count.

Logs must never include raw titles, full URLs, query strings, or fragments. Release logging should be rate-limited and limited to error categories and durations.

Suggested signposts:

```swift
ContextCollection.begin(source: .safari)
ContextCollection.end(source: .safari, outcome: .success, durationMS: 84)
```

No third-party analytics or crash-reporting dependency is introduced in V2.6.

---

## 8. Testing and Quality Assurance

### Unit Tests

**Context identity**

- detects title-only, URL-only, bundle-only, and source changes;
- suppresses identical normalized contexts;
- handles empty and multi-line titles;
- strips control characters without corrupting Unicode.

**URL persistence sanitizer**

- strips credentials, query, and fragment;
- rejects non-HTTP(S) schemes;
- normalizes host case;
- preserves and caps paths;
- handles malformed URLs safely.

**Collector orchestration**

- rejects stale generations;
- enforces one active request;
- handles timeout, cancellation, and permission loss;
- delivers ordered results on the expected queue.

**Storage and migration**

- migrates a V2.5 fixture database without data loss;
- remains idempotent on a second launch;
- honors opt-in and retention settings;
- clears detailed history without deleting session events.

**Analytics**

- preserves existing aggregation results;
- handles daylight-saving transitions;
- rejects stale range responses;
- maps database errors to failed view state.

### Integration Tests

- `AppSwitchMonitor` → `FocusEngine` propagates title-only changes.
- Browser-to-native switches cannot be overwritten by a late browser result.
- Enabling history begins persistence; disabling it deletes history and stops writes.
- Permission revocation degrades to app-only monitoring.
- Voyage Logs remains interactive while a large fixture database is queried.

### Manual Verification Matrix

| Application | Verification |
|---|---|
| Safari | Tab switch, same-page title change, JS-events fallback, timeout |
| Chrome/Brave/Edge/Arc | Tab switch, same URL with new title, closed-window behavior |
| Firefox | Focused-window title, address-bar traversal failure, permission revocation |
| Xcode/Terminal | Focused document/window title changes without app reactivation |
| Settings | Opt-in disclosure, retention selection, deletion confirmation |
| Voyage Logs | Loading, empty, populated, failure, and rapid range changes |

### Performance Verification

- Use Instruments Time Profiler to confirm no collection or database aggregation blocks the main thread.
- Run an eight-hour synthetic poll soak test and verify timer/request counts remain stable.
- Test a fixture containing at least 100,000 session events and 100,000 context observations.
- Confirm retention deletion completes without a visible UI stall.

---

## 9. Commands and Project Conventions

### Build and Test Commands

```bash
# Build the application
xcodebuild -project Anchored.xcodeproj -scheme Anchored -destination 'platform=macOS' build

# Run the full test suite
xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' test

# Run context-monitor tests only
xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' \
  -only-testing:AnchoredTests/AppSwitchMonitorTests test

# Run storage and analytics tests only
xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' \
  -only-testing:AnchoredTests/SQLiteSessionStoreTests \
  -only-testing:AnchoredTests/DashboardQueriesTests test
```

### Expected Project Structure

```text
Anchored/
├── Engine/
│   ├── ActivityMonitor.swift              # ContextSnapshot callback contract
│   ├── AppSwitchMonitor.swift             # Polling, deduplication, generations
│   ├── BrowserStrategies.swift            # Browser-specific context retrieval
│   ├── ContextCollector.swift              # Async orchestration and timeout boundary
│   └── ContextSanitizer.swift              # Normalization and persistence sanitization
├── Models/
│   ├── ContextSnapshot.swift               # Runtime context value
│   └── PersistedContextObservation.swift   # Storage-safe context value
├── Storage/
│   ├── SQLiteSessionStore.swift            # Migrations and writes
│   ├── ContextHistoryStore.swift           # Retention and deletion API
│   └── DashboardQueries.swift              # Async analytics reads
└── MenuBar/
    └── SettingsView.swift                  # Privacy & Data controls

AnchoredTests/
├── Engine/
│   ├── AppSwitchMonitorTests.swift
│   ├── ContextCollectorTests.swift
│   └── ContextSanitizerTests.swift
└── Storage/
    ├── ContextHistoryStoreTests.swift
    └── DashboardQueriesTests.swift
```

### Code Style

- Prefer value types for snapshots, identities, buckets, and sanitized records.
- Inject collaborators through initializers; production singletons belong only in application composition.
- Keep AppKit callbacks and engine state mutation on the main thread.
- Keep I/O and collection work off the main thread.
- Return typed errors across asynchronous boundaries; do not use empty strings to represent every failure mode.
- Avoid force casts from Accessibility values.

```swift
guard error == .success,
      let window = AccessibilityValue.element(from: value) else {
    return .failure(.contextUnavailable)
}
```

`AccessibilityValue.element(from:)` represents a centralized, unit-tested type-validation helper. The implementation must not use unchecked casts or `unsafeBitCast` to convert arbitrary Accessibility values.

---

## 10. Engineering Boundaries

### Always

- Preserve app-only tracking when privileged context is unavailable.
- Sanitize data at the persistence boundary, even if upstream values were normalized.
- Keep context history local and disabled by default.
- Use injected stores, clocks, schedulers, and list providers in tests.
- Run the full test suite before marking V2.6 complete.
- Update this specification when a privacy or schema decision changes.

### Ask First

- Enable detailed history by default.
- Store query strings, URL fragments, credentials, full terminal content, or DOM content.
- Add a network service, analytics SDK, crash-reporting SDK, or new package dependency.
- Change the 30-day maximum retention period.
- Export or synchronize detailed history.
- Change the minimum macOS version or Swift language version.

### Never

- Upload titles or URLs in V2.6.
- Log raw titles or full URLs.
- Block the main thread on AppleScript, Accessibility traversal, or SQLite aggregation.
- Infer consent to store context from Accessibility permission.
- Mutate global shared managers in tests.
- Delete existing session history as part of migration or detailed-history cleanup.
- Weaken a failing test by adding sleeps or removing assertions.

---

## 11. V2.6 Scope Summary

**In V2.6:**

- Canonical `ContextSnapshot` monitor-to-engine contract.
- Title-aware and URL-aware context deduplication.
- Native focused-window polling while trusted.
- Asynchronous, generation-safe context collection.
- Collection time budget, cancellation, and stale-result rejection.
- Optional local detailed context history.
- Title normalization and URL persistence sanitization.
- Explicit GRDB migration, retention, and deletion behavior.
- Asynchronous chart queries and explicit view loading states.
- Protocol-based list providers and removal of XCTest-aware production behavior.
- Deterministic storage and polling tests.
- Privacy-safe operational diagnostics.

**Not in V2.6:**

- CoreML model bundling, inference, or training.
- `MLUpdateTask` personalization.
- Automatic classification from title or URL.
- The Bouncer or application hiding.
- iCloud or cross-device synchronization.
- Cloud telemetry or remote diagnostics.
- Full DOM, clipboard, keystroke, shell-history, or document-content capture.
- Automatic export of detailed context history.
- Changes to the permission gate threshold.

---

## 12. Success Criteria

V2.6 is complete when:

- [ ] Title-only and native-window-only changes reliably reach `FocusEngine`.
- [ ] Duplicate polls do not produce duplicate context events.
- [ ] Context collection and dashboard queries do not block the main thread.
- [ ] Slow or stale browser results cannot overwrite newer application context.
- [ ] Detailed context is never persisted before explicit opt-in.
- [ ] Persisted URLs contain no credentials, queries, or fragments.
- [ ] Existing V2.5 session URLs are sanitized during migration.
- [ ] Retention and manual deletion preserve aggregate session history.
- [ ] A V2.5 database migrates without data loss and migration is idempotent.
- [ ] Voyage Logs handles loading, empty, failure, and rapid range changes.
- [ ] Production behavior contains no XCTest detection.
- [ ] Tests do not mutate global singleton state or wait using arbitrary sleeps.
- [ ] The full suite passes with parallel test execution enabled.
- [ ] Manual verification passes for Safari, Firefox, one Chromium browser, and two native apps.
- [ ] An eight-hour soak test shows no unbounded timers, requests, observers, or memory growth.

---

## 13. Open Questions

1. **Settings location:** Should Privacy & Data be its own settings section or live under Crew Info?
2. **Path persistence:** Is retaining sanitized URL paths acceptable, or should V2.6 persist domain-only values for a stricter privacy posture?
3. **History use:** Should detailed history initially be visible to users, or remain an internal foundation until V3 provides classification feedback?
4. **Native polling:** Is a fixed 2.5-second interval acceptable for native windows, or should native polling use a slower cadence than browser polling?
5. **Collection executor:** Which Apple Event execution mechanism satisfies cancellation, timeout, signing, and thread-safety requirements for the current distribution model?
6. **Migration recovery:** If an existing database is corrupt, should Anchored offer an in-app repair/reset flow in V2.6 or defer that recovery UI?

These questions do not prevent review of the overall scope, but questions 2 and 5 must be resolved before implementation begins.

---

## 14. Specification Approval

- [ ] Product scope approved.
- [ ] Privacy defaults and URL-path policy approved.
- [ ] Context collection executor selected and validated.
- [ ] Database schema and retention behavior approved.
- [ ] Implementation plan may be created.



================================================================================
FILE: anchored-v2.md
SIZE: 35008
================================================================================

# Anchored V2 — Permission Gate

> **Prerequisite:** This spec assumes [Anchored V1 (Ghost Mode)](file:///Users/varun/Development/Anchor/docs/ideas/anchored-v1.md) has shipped and is stable. V2 builds on V1's architecture without breaking any existing behavior.

## Problem Statement
**How might we** close the browser blind spot — where users can freely browse distracting websites without consequence — by progressively earning the system permissions needed for URL-level awareness, without sacrificing the zero-friction trust that made V1 compelling?

## V2 Summary

V2 transforms Anchored from an app-level focus guard into a full context-aware focus engine. The three major additions:

1. **Permission Gate** — An opt-in Accessibility permission unlock that feels earned, not demanded.
2. **Browser URL Monitor** — Real-time detection of distracting websites within Chrome, Safari, Arc, Edge, Brave, Firefox, and Orion.
3. **Focus Dashboard** — A session analytics view that turns raw logged data (captured since V1 Day 1) into actionable self-awareness.

Supporting features: work profiles, distraction domain lists, SQLite storage migration, and an upgraded menu bar experience.

---

## 1. The Permission Gate

### Philosophy

V1 proved the product works. V2 asks for trust. The permission prompt must feel like the app *offering more value*, not *demanding more access*. The user should think: "Yes, I want this."

### Trigger Condition

The permission prompt surfaces **once** when the user has completed **10 anchored sessions** (not 10 app launches — 10 sessions where they clicked "Keep Focused"). This ensures:
- The user has experienced the core value loop multiple times.
- They've likely encountered the browser blind spot organically ("I wish it caught my YouTube tabs too").
- They trust the app enough to consider granting system access.

> [!IMPORTANT]
> The prompt fires exactly once. If dismissed, it never auto-resurfaces. The user can manually opt in later via Preferences → "Enable Website Tracking."

### Prompt UX

**Presentation:** Same borderless floating `NSPanel` as the exit-trigger capsule. Slides down from the menu bar icon with a spring animation. Familiar visual language — the user already knows this UI pattern.

**Content:**

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ⚓ Anchored can now track distracting websites too.         │
│                                                              │
│  You've completed 10 focus sessions — nice work.             │
│  Right now, Anchored can't see what you're doing inside      │
│  Chrome or Safari. Want to change that?                      │
│                                                              │
│  This requires macOS Accessibility access. Anchored uses     │
│  it solely to read browser URLs. No data leaves your Mac.    │
│                                                              │
│  [ Enable Website Tracking ]      [ Not Now ]                │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Permission Flow

1. User clicks **"Enable Website Tracking"** → App triggers `AXIsProcessTrustedWithOptions` with the prompt flag set to `true`. macOS shows the native System Settings → Privacy & Security → Accessibility pane.
2. The app enters a background polling loop checking `AXIsProcessTrusted()` every 800ms.
3. The moment the user toggles the switch in System Settings:
   - **Audio:** Warm success chime (same as onboarding State 4).
   - **Visual:** Prompt text updates to green "✓ Website tracking enabled" for 1.5 seconds.
   - **Engine:** `BrowserURLMonitor` activates immediately. The `FocusEngine` begins receiving URL-enriched context events.
   - **Auto-dismiss:** Prompt slides away after the 1.5s confirmation.
4. If the user clicks **"Not Now"**:
   - Prompt dismisses immediately.
   - A flag is set: `hasDeclinedPermissionGate = true`.
   - The prompt never auto-surfaces again.
   - The menu bar Preferences gains a new row: "Enable Website Tracking…" for manual opt-in at any time.

### Post-Permission Onboarding

Once Accessibility is granted, a one-time follow-up panel appears (same visual style, auto-dismissed after action):

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ⚓ Choose a work profile to get started.                     │
│                                                              │
│  Profiles define which websites are safe during focus.       │
│                                                              │
│  [ 💻 Coding ]  [ 🎬 Video ]  [ ✍️ Writing ]  [ ⚙️ Custom ]   │
│                                                              │
│                    [ Set Up Later ]                          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

Selecting a profile pre-populates the distraction domain list (see Section 3). "Set Up Later" defaults to the **Coding** profile.

---

## 2. Browser URL Monitor

### Architecture

The `BrowserURLMonitor` conforms to the `ActivityMonitor` protocol established in V1. It wraps `AppSwitchMonitor` and enriches events:

```swift
class BrowserURLMonitor: ActivityMonitor {
    private let appSwitchMonitor: AppSwitchMonitor
    private var urlPollingTimer: Timer?
    
    /// Known browser bundle IDs → fetching strategy
    private let browserStrategies: [String: BrowserURLStrategy] = [
        "com.google.Chrome":        .chromiumAppleScript,
        "com.apple.Safari":         .safariAppleScript,
        "company.thebrowser.Browser": .chromiumAppleScript,  // Arc
        "com.microsoft.edgemac":    .chromiumAppleScript,
        "com.brave.Browser":        .chromiumAppleScript,
        "org.mozilla.firefox":      .accessibilityAPI,
        "com.kagi.kagimacOS":       .chromiumAppleScript,    // Orion
    ]
    
    var onContextChange: ((bundleID: String, url: URL?)) -> Void
}
```

### URL Fetching Strategies

#### A. Chromium-Based Browsers (Chrome, Arc, Edge, Brave, Orion)

**Method:** AppleScript via `NSAppleScript`.

```applescript
tell application "Google Chrome"
    get URL of active tab of front window
end tell
```

The bundle-to-AppleScript-target mapping:

| Bundle ID | AppleScript Target |
|---|---|
| `com.google.Chrome` | `"Google Chrome"` |
| `company.thebrowser.Browser` | `"Arc"` |
| `com.microsoft.edgemac` | `"Microsoft Edge"` |
| `com.brave.Browser` | `"Brave Browser"` |
| `com.kagi.kagimacOS` | `"Orion"` |

All Chromium browsers support the same `URL of active tab of front window` command. The only variation is the application name target string.

**Error handling:** If the AppleScript fails (browser not running, no windows open, automation permission revoked), return `url: nil` gracefully. Never crash the engine on a URL fetch failure.

#### B. Safari

**Method:** Safari-specific AppleScript.

```applescript
tell application "Safari"
    get URL of current tab of front window
end tell
```

> [!NOTE]
> Safari requires the user to enable "Allow JavaScript from Apple Events" in Safari → Develop menu. If this is not enabled, the AppleScript will fail silently. V2 should detect this failure and show a one-time tooltip: *"To track Safari URLs, enable 'Allow JavaScript from Apple Events' in Safari's Develop menu."*

#### C. Firefox

**Method:** macOS Accessibility API (`AXUIElement`).

Firefox does not expose tab URLs via AppleScript. The monitor must:

1. Get the Firefox application's `AXUIElement` reference via its PID.
2. Walk the accessibility tree to locate the address bar element.
3. The address bar is typically an `AXTextField` with a role description matching URL input patterns.
4. Extract the `AXValue` attribute from that element.

```swift
func fetchFirefoxURL(pid: pid_t) -> URL? {
    let appElement = AXUIElementCreateApplication(pid)
    
    // Walk the tree: AXWindow → AXToolbar → AXTextField (address bar)
    guard let toolbar = findChild(of: appElement, role: .toolbar),
          let addressBar = findChild(of: toolbar, role: .textField),
          let urlString = getAttribute(addressBar, .value) as? String,
          let url = URL(string: urlString) else {
        return nil
    }
    
    return url
}
```

**Fragility warning:** Firefox's accessibility tree structure can change between versions. The address bar locator should use heuristic matching (look for a text field within the toolbar that contains a URL-like string) rather than hardcoded tree positions.

### Polling Behavior

- **When to poll:** Only when the foreground app is a known browser (checked via bundle ID from `NSWorkspace`).
- **Polling interval:** Every 2.5 seconds while a browser holds focus.
- **Start/stop:** Polling timer starts when a browser gains focus, stops immediately when any non-browser app gains focus. Zero CPU cost when the user is in Xcode.
- **Deduplication:** If the URL hasn't changed since the last poll, no event is emitted. Only tab/page changes trigger `onContextChange`.

### URL → Distraction Resolution

When a URL is fetched, the `FocusEngine` extracts the domain and checks it against the distraction domain list:

```swift
func isDistractingSite(url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    
    return distractionDomains.contains { domain in
        host == domain || host.hasSuffix(".\(domain)")
    }
}
```

**Subdomain handling:** If `twitter.com` is in the distraction list, `mobile.twitter.com` and `x.com` both match. The domain list stores canonical domains, not full URLs.

**Browser-as-neutral upgrade:** In V2 with permissions granted, the browser is no longer uniformly neutral. Instead:
- Browser showing an **allowed domain** (GitHub, StackOverflow, docs) → treated as work. No nudge.
- Browser showing a **distraction domain** (YouTube, Twitter, Reddit) → triggers countdown pill + escalation.
- Browser showing an **unlisted domain** → treated as neutral. No nudge. (Permissive default — only explicitly listed distractions trigger the system.)

---

## 3. Work Profiles & Distraction Domains

### Profile Definitions

Each profile bundles a **distraction app list** (carried over from V1) with a **distraction domain list** (new in V2) and an **allowed domain list** (sites explicitly safe during focus).

#### 💻 Coding Profile

| Distraction Apps | Distraction Domains | Allowed Domains |
|---|---|---|
| Discord, Slack, Messages, Telegram, Steam, Spotify, Music | youtube.com, twitter.com, x.com, reddit.com, instagram.com, tiktok.com, facebook.com, twitch.tv, netflix.com | github.com, stackoverflow.com, developer.apple.com, docs.python.org, npmjs.com, crates.io, pkg.go.dev |

#### 🎬 Video Creation Profile

| Distraction Apps | Distraction Domains | Allowed Domains |
|---|---|---|
| Discord, Messages, Telegram, Steam, Slack | twitter.com, x.com, reddit.com, instagram.com, tiktok.com, facebook.com, netflix.com | youtube.com (creator exception), studio.youtube.com, frame.io, vimeo.com |

> [!NOTE]
> YouTube is **allowed** in the Video Creation profile because creators need it for reference footage, competitor research, and uploading. This is a deliberate profile-level decision — the same domain can be a distraction in one profile and essential in another.

#### ✍️ Writing & Research Profile

| Distraction Apps | Distraction Domains | Allowed Domains |
|---|---|---|
| Discord, Slack, Messages, Telegram, Steam, Spotify, Music | youtube.com, twitter.com, x.com, reddit.com, instagram.com, tiktok.com, twitch.tv, netflix.com | docs.google.com, wikipedia.org, scholar.google.com, notion.so, medium.com |

#### ⚙️ Custom Profile

| Distraction Apps | Distraction Domains | Allowed Domains |
|---|---|---|
| *(empty — user configures)* | *(empty — user configures)* | *(empty — user configures)* |

### Profile Editing UI

Accessible via menu bar → Preferences → "Edit Profile…"

**Layout:** A split-panel interface (same visual language as V1 onboarding State 3):

```
┌─────────────────────────────────────────────────────────┐
│  Profile: [ 💻 Coding ▼ ]                               │
├────────────────────────┬────────────────────────────────┤
│  Distraction Apps      │  Distraction Domains           │
│                        │                                │
│  ● Discord        [−]  │  ● youtube.com           [−]  │
│  ● Slack          [−]  │  ● twitter.com           [−]  │
│  ● Messages       [−]  │  ● reddit.com            [−]  │
│  ● Steam          [−]  │  ● instagram.com         [−]  │
│  ● Spotify        [−]  │  ● tiktok.com            [−]  │
│                        │                                │
│  [ + Add app… ]        │  [ + Add domain… ]             │
├────────────────────────┴────────────────────────────────┤
│  Allowed Domains (safe during focus)                    │
│                                                         │
│  ● github.com [−]  ● stackoverflow.com [−]              │
│  ● developer.apple.com [−]                              │
│                                                         │
│  [ + Add domain… ]                                      │
├─────────────────────────────────────────────────────────┤
│                                        [ Save Profile ] │
└─────────────────────────────────────────────────────────┘
```

### Profile Switching

- Active profile is shown in the menu bar dropdown.
- Quick-switch via right-click menu: "Switch Profile → Coding | Video | Writing | Custom."
- Profile can be switched mid-session. The new distraction/allowed lists take effect immediately.

### Storage

Profiles are stored in `UserDefaults` as a serialized dictionary keyed by profile name:

```json
{
  "activeProfile": "coding",
  "profiles": {
    "coding": {
      "distractionApps": ["com.hnc.Discord", "com.tinyspeck.slackmacgap", ...],
      "distractionDomains": ["youtube.com", "twitter.com", ...],
      "allowedDomains": ["github.com", "stackoverflow.com", ...]
    }
  }
}
```

---

## 4. Focus Dashboard

### Philosophy

The dashboard doesn't judge — it reflects. The goal is self-awareness, not gamification. No "scores," no "grades," no guilt. Just clean data that helps the user understand their own patterns.

### Access

- **Primary entry:** Menu bar left-click → "View Dashboard" button at the bottom of the dropdown.
- **Window type:** Standard `NSWindow` (not floating, not borderless). This is a utility window the user explicitly opens — it should feel like a proper Mac app window with a title bar.
- **Size:** Fixed 600×480pt. Not resizable. Clean and opinionated.

### Dashboard Layout

```
┌──────────────────────────────────────────────────────────┐
│  ⚓ Anchored — Focus Dashboard                     [×]   │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Today                              This Week            │
│  ┌──────────────────┐              ┌──────────────────┐  │
│  │  3h 42m focused  │              │  18h 15m focused │  │
│  │  ██████████░░░░░░ │              │  ████████░░░░░░░ │  │
│  │  4 sessions      │              │  22 sessions     │  │
│  └──────────────────┘              └──────────────────┘  │
│                                                          │
│  Focus Streak: 🔥 7 days                                 │
│  (Streak = at least 1 completed session per day)         │
│                                                          │
│  ── Today's Timeline ──────────────────────────────────  │
│                                                          │
│  9:15a  ██████████████████░░██████████████  11:02a       │
│         Xcode (1h 47m)    Discord (3m)  Xcode (42m)     │
│                                                          │
│  1:30p  ████████████████████████████████    3:15p        │
│         VS Code (1h 45m)                                 │
│                                                          │
│  4:00p  ████████░░░░████████████           5:10p         │
│         Figma (32m) Twitter (8m) Figma (30m)            │
│                                                          │
│  ── Top Distractions This Week ────────────────────────  │
│                                                          │
│  1. Discord        12 interruptions    avg 4m each      │
│  2. twitter.com     8 interruptions    avg 6m each      │
│  3. Messages        5 interruptions    avg 2m each      │
│                                                          │
│  ── Weekly History ────────────────────────────────────  │
│                                                          │
│  Mon  ████████████████████  4h 12m  (5 sessions)        │
│  Tue  ██████████████        3h 05m  (4 sessions)        │
│  Wed  ████████████████████████  5h 30m  (6 sessions)    │
│  Thu  ██████████            2h 18m  (3 sessions)        │
│  Fri  ████████████████      3h 42m  (4 sessions)  ← today│
│  Sat  —                                                  │
│  Sun  —                                                  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Data Sources

All dashboard data is derived from the session event log that V1 has been writing since Day 1. No new data collection is needed — only a read/aggregation layer.

**Computed metrics:**
- **Total focus time:** Sum of `focusDurationSeconds` for all `session_end` events in the time window.
- **Session count:** Count of `session_end` events.
- **Streak:** Consecutive calendar days with at least one `session_end` event. Resets at midnight local time.
- **Timeline:** Reconstructed from sequential `session_start`, `distraction_detected`, and `session_end` events. Focus blocks are solid, distraction interruptions are gaps.
- **Top distractions:** Aggregated from `distraction_detected` events, grouped by `distractionAppBundleID` or domain (from `url` field in V2). Sorted by frequency.

### Rendering

- Timeline bars are rendered as simple colored `NSView` blocks — no charting library needed.
- Focus blocks: accent color (system tint or custom anchor blue `#2563EB`).
- Distraction gaps: muted red-orange (`#F97316`, 40% opacity).
- Bar chart for weekly history: same accent color, proportional width.

---

## 5. SQLite Migration

### Why Migrate

V1 writes session events to `~/Library/Application Support/Anchored/sessions.json` — a flat JSON file. This works fine for V1's simple "last 20 sessions" menu bar list, but the dashboard needs:
- Aggregation queries (sum focus time by day, count distractions by app).
- Date range filtering (this week, this month).
- Indexed lookups that don't require loading the entire history into memory.

### Migration Strategy

On first V2 launch:

1. Check if `sessions.json` exists.
2. If yes, read all events, insert them into the new SQLite database, and rename the JSON file to `sessions.json.migrated` (kept as backup, never deleted).
3. All future events are written to SQLite only.

### Schema

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,           -- ISO-8601
    type TEXT NOT NULL,                -- session_start | session_end | distraction_detected | escalation_triggered
    app_bundle_id TEXT NOT NULL,
    app_name TEXT NOT NULL,
    url TEXT,                          -- NULL in V1 events, populated in V2
    focus_duration_seconds INTEGER,
    session_duration_seconds INTEGER,
    distraction_app_bundle_id TEXT,
    distraction_domain TEXT,           -- NEW: extracted from url for easy querying
    action TEXT                        -- anchored | dismissed | timeout | escalated | returned
);

CREATE INDEX idx_sessions_timestamp ON sessions(timestamp);
CREATE INDEX idx_sessions_type ON sessions(type);
CREATE INDEX idx_sessions_date ON sessions(date(timestamp));
```

**New field:** `distraction_domain` is extracted from `url` at write time for fast aggregation in dashboard queries. This avoids parsing URLs on every dashboard render.

### Database Location

`~/Library/Application Support/Anchored/anchored.db`

---

## 6. Updated Menu Bar Experience

V2 expands the menu bar interaction to accommodate new features without cluttering the V1 experience.

### Left-Click Dropdown (Updated)

```
┌────────────────────────────────────┐
│  ⚓ Anchored                       │
│  Profile: 💻 Coding               │
├────────────────────────────────────┤
│  ● Anchored — 18m remaining       │
│    in Xcode                        │
│  [ End Session ]                   │
├────────────────────────────────────┤
│  Today: 3h 42m focused (4 sessions)│
│  Streak: 🔥 7 days                │
├────────────────────────────────────┤
│  Recent Sessions                   │
│  ├ Xcode      1h 47m    9:15 AM   │
│  ├ VS Code    1h 45m    1:30 PM   │
│  └ Figma      1h 02m    4:00 PM   │
├────────────────────────────────────┤
│  [ View Dashboard ]                │
└────────────────────────────────────┘
```

### Right-Click Menu (Updated)

```
Edit Distraction List…
Edit Profile…
Switch Profile   ▶  💻 Coding  ✓
                    🎬 Video
                    ✍️ Writing
                    ⚙️ Custom
─────────────────────
Preferences…
Enable Website Tracking…   ← only shown if permission not granted
View Dashboard
─────────────────────
Quit Anchored
```

---

## 7. Architecture Changes from V1

### Module Boundary Updates

```diff
  ┌──────────────────────────────────────────┐
  │         FocusEngine (Core)               │
  │                                           │
  │  ┌─────────────────────────────────────┐ │
  │  │  ActivityMonitor «protocol»         │ │
  │  │                                      │ │
  │  │  ├─ AppSwitchMonitor (V1)           │ │
  │  │  │   NSWorkspace notifications       │ │
  │  │  │                                   │ │
- │  │  └─ BrowserURLMonitor (V2)          │ │
+ │  │  └─ BrowserURLMonitor (V2) ✦ NEW   │ │
+ │  │      ├─ ChromiumStrategy            │ │
+ │  │      ├─ SafariStrategy              │ │
+ │  │      └─ FirefoxStrategy             │ │
  │  └─────────────────────────────────────┘ │
  │                                           │
- │  ┌──────────────┐  ┌──────────────────┐  │
- │  │ SessionStore │  │ DistractionList  │  │
- │  │  (JSON/SQL)  │  │   (UserDefaults) │  │
- │  └──────────────┘  └──────────────────┘  │
+ │  ┌──────────────┐  ┌──────────────────┐  │
+ │  │ SessionStore │  │  ProfileManager  │  │
+ │  │  (SQLite)    │  │  (UserDefaults)  │  │
+ │  └──────────────┘  └──────────────────┘  │
  └──────────────────────────────────────────┘

+ ┌──────────────────────────────────────────┐
+ │         DashboardWindow                   │
+ │  ├─ TodaySummaryView                     │
+ │  ├─ TimelineView                         │
+ │  ├─ TopDistractionsView                  │
+ │  └─ WeeklyHistoryView                   │
+ └──────────────────────────────────────────┘

+ ┌──────────────────────────────────────────┐
+ │         PermissionGateManager             │
+ │  ├─ Session counter (UserDefaults)       │
+ │  ├─ AXIsProcessTrusted() polling         │
+ │  └─ Post-permission onboarding flow      │
+ └──────────────────────────────────────────┘
```

### FocusEngine Decision Logic (Updated)

The V1 decision logic is extended to handle URL-based distraction detection:

```
let incoming = notification.bundleIdentifier
let url = browserURLMonitor?.currentURL  // nil if not a browser or no permission

if incoming is in distractionAppList:
    → same V1 behavior (countdown pill → escalation)

else if incoming is a known browser AND url != nil:
    if isDistractingDomain(url):
        → same behavior as distraction app (countdown pill → escalation)
    else if isAllowedDomain(url):
        → treat as work app (reset workSessionStart if needed, lift overlay)
    else:
        → treat as neutral (no action)

else:
    → same V1 behavior (non-distraction app, treat as work/neutral)
```

**Key difference from V1:** Browsers are no longer uniformly neutral. They are contextually evaluated based on the active URL.

### Handling In-Browser Tab Switches

A critical V2 edge case: the user is in Chrome (which is focused) and switches from GitHub (allowed) to YouTube (distraction) **without switching apps**. `NSWorkspace` does NOT fire because the app didn't change.

**Solution:** The 2.5-second URL polling loop handles this. When the browser retains focus:
1. Every 2.5s, the `BrowserURLMonitor` fetches the current URL.
2. If the domain has changed from allowed/neutral to distraction, it emits a new `onContextChange` event.
3. The `FocusEngine` processes this event identically to an app switch — showing the countdown pill if a session is active.

> [!WARNING]
> This means there can be up to a 2.5-second delay between the user opening a distracting tab and the countdown pill appearing. This is an acceptable trade-off for CPU efficiency. Polling faster than 2.5s risks visible energy impact in Activity Monitor, which damages user trust for a background utility.

---

## 8. Smart Auto-Triggers & Shadow Tracking

### Philosophy
How might we proactively detect when a user enters a work context and encourage them to focus, without silently trapping them in a blocked state without their explicit consent?

### Recommended Direction
**Shadow Nudges with Opt-In 24/7 Tracking.** 
Anchored will introduce a "Shadow Tracking" engine that monitors app usage categories in the background (pausing automatically when the Mac sleeps). When the engine detects sustained usage of a trigger app (e.g., 5+ minutes in Xcode), it sends a non-intrusive "Smart Nudge" notification: *"You've been coding for a bit. Drop the anchor?"*

To respect privacy and battery life, 24/7 tracking is strictly an opt-in setting in Preferences. If enabled, this ambient data also feeds the Dashboard to show total category time versus actual focused time.

### MVP Scope
- A new `ShadowTrackingEngine` that monitors the foreground app against the active profile's allowed apps.
- Opt-in toggle in Preferences: "Enable background app tracking for Smart Nudges".
- Nudge logic: Fire a macOS local notification after *N* continuous minutes in an allowed/trigger app.
- System sleep/wake observers (`NSWorkspace.workspaceDidSleepNotification`) to pause the tracker.

---

## 9. V2 Scope Summary

**In (V2):**
- Permission Gate UX (one-time prompt after 10 sessions, with manual opt-in fallback)
- `BrowserURLMonitor` with Chromium AppleScript, Safari AppleScript, Firefox AXUIElement strategies
- URL polling at 2.5s intervals while a browser holds focus
- Domain-level distraction resolution (subdomain-aware matching)
- Work profiles (Coding, Video, Writing, Custom) with per-profile distraction apps, distraction domains, and allowed domains
- Profile editor UI and quick-switch from menu bar
- Focus Dashboard window (today summary, timeline, top distractions, weekly history, streak)
- SQLite migration from V1's JSON log (with backup preservation)
- Updated menu bar dropdown with profile indicator, today stats, and dashboard link
- Safari "Allow JavaScript from Apple Events" detection and user guidance tooltip
- **Smart Auto-Triggers (Opt-in 24/7 background tracking and Nudges)**

**Not In V2 (Deferred to V3+):**
- **Monthly/yearly analytics views** — Weekly is sufficient to validate dashboard value. Expand time ranges only if users request it.
- **Goal setting ("Focus 4 hours today")** — Adds complexity and judgment. The dashboard should reflect, not prescribe. Defer until user feedback indicates demand.
- **Profile auto-switching based on time of day** — Interesting (auto-switch to "Writing" at 9am, "Coding" at 2pm) but adds a scheduling system. Defer.
- **Export/share session data** — No user has asked for this. Data stays local until there's a reason to move it.
- **Custom distraction escalation per profile** — Different countdown durations for different profiles adds configuration surface area with marginal value. One setting covers all profiles for now.
- **Notification integration (macOS Notification Center)** — Anchored's custom capsules and pills are more elegant and less dismissable than system notifications. Don't downgrade to the system notification tray. (Except for the new Smart Nudges, which will use the notification center).

## 10. Open Questions

- **Smart Nudge Cooldown:** If a user ignores the Smart Nudge, how long should we wait before nudging them again for the same app?
- **Safari automation permission UX:** Safari requires "Allow JavaScript from Apple Events" which is hidden behind the Develop menu (which itself is hidden by default in Safari settings). How aggressively should Anchored guide the user through enabling this? A tooltip? A step-by-step modal? Or just gracefully degrade and skip Safari tracking?
- **Firefox accessibility tree stability:** Firefox's AX tree structure may vary between versions. Should V2 ship with Firefox support, or defer it to V2.1 after testing across Firefox stable/beta/nightly? Chromium + Safari covers ~85% of macOS browser usage.
- **Dashboard refresh frequency:** Should the dashboard update in real-time while open during an active session, or only refresh when opened? Real-time feels alive but requires a timer loop. Static-on-open is simpler.
- **Profile data portability:** If the user wants to back up or share their profile (distraction list + allowed domains), should there be an export/import mechanism, or is manual editing of UserDefaults acceptable for power users?
- **Streak timezone handling:** Streaks reset at midnight, but midnight in which timezone? Use system timezone? What if the user travels? Edge case, but streaks create emotional attachment — breaking a streak due to timezone math would feel terrible.

---

## 11. Implementation Progress
- [ ] Permission Gate UX
- [ ] Browser URL Monitor
- [ ] Profiles & Distraction Domains 
- [ ] Focus Dashboard
- [ ] SQLite Migration
- [ ] Smart Auto-Triggers & Shadow Tracking

*(Note: A codebase scan confirms that none of the V2 features have been implemented yet. The implementation is currently purely in the spec phase).*



================================================================================
FILE: anchored-v3-plan.md
SIZE: 31572
================================================================================

# Implementation Plan: Anchored V3 — The Intelligence Update

## Overview

Build the complete Anchored V3 (The Intelligence Update) upgrade: transforming the app from a simple domain matcher into an intent-aware, syncing ecosystem. V3 introduces a local AI content awareness layer (CoreML), an aggressive "Bouncer" enforcement mode, iCloud Key-Value synchronization for multi-device workflows, and AI-dynamic smart nudges. This plan breaks down the 500+ line specification into highly granular, executable tasks suitable for parallel agent development.

**Source spec:** [anchored-v3.md](file:///Users/varun/Development/Anchor/docs/ideas/anchored-v3.md)

## Architecture Decisions

- **On-Device Machine Learning:** Use an updatable CoreML text classifier (`MLUpdateTask`) to ensure all NLP categorization runs locally, protecting user privacy and avoiding cloud latency. The model is retrained seamlessly as the user interacts with overrides.
- **Window Management APIs:** Use `NSWorkspace.shared.runningApplications` to implement "The Bouncer" by hiding applications rather than killing them (`killall`) to prevent user data loss.
- **Lightweight Synchronization:** Use `NSUbiquitousKeyValueStore` instead of CloudKit/CoreData for ecosystem sync, synchronizing only configurations (profiles, domains, overrides) while keeping all analytics databases locally isolated to prevent merge conflicts.
- **Global Carbon Hotkeys:** Use `NSEvent.addGlobalMonitorForEvents` or Carbon's `RegisterEventHotKey` for the Global Bypass to ensure the override works regardless of the active application state.
- **V2 Database Migration:** V3 must non-destructively migrate V2 SQLite schemas to support AI categories, mapping old events gracefully to Dashboard components.

## Macro Dependency Graph

```mermaid
graph TD
    A[Phase 1: CoreML Pipeline] --> B[Phase 2: Focus Engine Update]
    B --> C[Phase 3: The Bouncer]
    C --> D[Phase 4: Global Overrides]
    A --> D
    E[Phase 5: iCloud Sync] --> F[Phase 7: Dashboard Migration]
    B --> G[Phase 6: AI-Dynamic Nudges]
    G --> F
    F --> H[Phase 8: Polish & QA]
```

## Task List

---

### Phase 1: CoreML Training & Baseline Infrastructure

This phase establishes the ability to read intent from the browser and pass it to a local AI model for scoring.

#### Task 1: Dataset Generation & ML Model Training Setup

**Description:** Before we can integrate CoreML, we need a baseline model. Create a Python/CreateML pipeline to train `AnchoredTextClassifier.mlmodel` on a synthetic dataset of 5,000 URLs and Titles mapping to the 7 predefined categories.

**Acceptance criteria:**
- [ ] Curate or generate a dataset of typical `Title | URL` strings.
- [ ] Train a CoreML Text Classifier (e.g. `MLTextClassifier`).
- [ ] Export the model as an Updatable `.mlmodel`.
- [ ] Bundle `AnchoredTextClassifier.mlmodelc` into the Xcode project resources.

**Verification:**
- [ ] Run the model through Xcode's CoreML previewer; verify accuracy is > 85%.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Resources/AnchoredTextClassifier.mlmodel`
- `scripts/train_model.py` (optional external script)

**Estimated scope:** M

#### Task 2: CoreML Model Integration (ContentClassifier.swift)

**Description:** Build the Swift layer that loads the `.mlmodelc`, manages initialization, and executes standard predictions against the text classifier.

**Acceptance criteria:**
- [ ] Create `Category.swift` enum for the 7 AI categories.
- [ ] Create `ContentClassifier` singleton/class.
- [ ] Implement `categorize(title:url:) -> Category?` using `model.prediction`.
- [ ] Extract and evaluate the `categoryProbability` dictionary; return `nil` if the top confidence is below 0.75.

**Verification:**
- [ ] Write `ContentClassifierTests.swift` passing in synthetic strings and verifying expected categories.

**Dependencies:** Task 1

**Files likely touched:**
- `Anchored/Engine/ContentClassifier.swift`
- `Anchored/Models/Category.swift`
- `AnchoredTests/Engine/ContentClassifierTests.swift`

**Estimated scope:** S

#### Task 3: Context Extraction in Chromium AppleScript

**Description:** Update the V2 Chromium (Chrome, Brave, Arc, Edge) AppleScript payload in `BrowserStrategies.swift` to extract the `name of active tab` alongside the `URL of active tab`.

**Acceptance criteria:**
- [ ] Modify AppleScript string to return `Title|URL` format.
- [ ] Update Swift parsing logic to split the result by the delimiter.
- [ ] Ensure non-blocking execution with a tight timeout.

**Verification:**
- [ ] Launch app, switch to a Chrome tab, verify both URL and title are logged to console.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`

**Estimated scope:** S

#### Task 4: Context Extraction in Safari AppleScript

**Description:** Update the V2 Safari AppleScript payload to extract the `name of current tab of front window` alongside the URL.

**Acceptance criteria:**
- [ ] Modify Safari AppleScript string to return `Title|URL` format.
- [ ] Update Swift parsing logic to handle Safari's specific document object model.
- [ ] Maintain the V2 error handling for missing JavaScript execution rights.

**Verification:**
- [ ] Launch app, switch to Safari, verify both URL and title are logged to console.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Engine/BrowserStrategies.swift`

**Estimated scope:** S

#### Task 5: Context Extraction in Firefox AXUIElement

**Description:** Firefox does not support AppleScript for tabs. Update the V2 `AXUIElement` tree-walking strategy to also find the `AXTitle` of the main window or tab bar in addition to the `AXTextField` URL.

**Acceptance criteria:**
- [ ] Walk the accessibility tree to find the frontmost tab's title.
- [ ] Combine it with the existing URL extraction logic.
- [ ] Return gracefully if the UI hierarchy has changed unexpectedly.

**Verification:**
- [ ] Launch app, switch to Firefox, verify both URL and title are logged to console.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Engine/FirefoxStrategy.swift`

**Estimated scope:** M

#### Task 6: Context Pipeline Aggregation & AppContext Update

**Description:** Update the `AppContext` data model and the `ActivityMonitor` protocols to propagate the newly extracted window titles through the engine pipeline.

**Acceptance criteria:**
- [ ] Add `title: String` to `AppContext`.
- [ ] Ensure `AppSwitchMonitor` emits window titles for native macOS apps using `AXUIElement` on the frontmost window.
- [ ] Update all `onContextChange` delegate signatures.

**Verification:**
- [ ] Switch between Xcode (native) and Chrome (browser); verify titles are extracted correctly for both.

**Dependencies:** Tasks 3, 4, 5

**Files likely touched:**
- `Anchored/Models/AppContext.swift`
- `Anchored/Engine/ActivityMonitor.swift`
- `Anchored/Engine/AppSwitchMonitor.swift`
- `Anchored/Engine/BrowserURLMonitor.swift`

**Estimated scope:** M

#### Task 7: MLUpdateTask Integration (On-Device Retraining)

**Description:** Implement the background retraining loop that updates the CoreML weights based on user overrides, achieving the "Silent Scholar" goal.

**Acceptance criteria:**
- [ ] Implement `func updateModelLocally(title:url:correctCategory:)` in `ContentClassifier`.
- [ ] Construct an `MLDictionaryFeatureProvider` mapping the text input to the corrected label.
- [ ] Execute `MLUpdateTask`, handling the completion context to overwrite the `.mlmodelc` in Application Support.
- [ ] Ensure the running instance reloads the newly updated model.

**Verification:**
- [ ] Write a unit test that mocks an update task, then verifies the model predicts the new category for that specific string.

**Dependencies:** Task 2

**Files likely touched:**
- `Anchored/Engine/ContentClassifier.swift`

**Estimated scope:** L

#### Task 8: Async Priority Queue for ML Inferences

**Description:** CoreML execution, while fast, should never block the main UI thread, especially during rapid app switching or tab cycling.

**Acceptance criteria:**
- [ ] Wrap all `categorize` calls in a dedicated background `DispatchQueue`.
- [ ] Add a debouncer to drop redundant inferences if the user rapid-cycles tabs.
- [ ] Return the classification to the main thread via completion handler or `async/await`.

**Verification:**
- [ ] Rapidly switch between 20 tabs; verify no main thread stalling occurs via Xcode Instruments.

**Dependencies:** Task 2, Task 6

**Files likely touched:**
- `Anchored/Engine/ContentClassifier.swift`
- `Anchored/Engine/BrowserURLMonitor.swift`

**Estimated scope:** S

### ✅ Checkpoint: Phase 1
- [ ] CoreML subsystem builds and runs.
- [ ] Browser scripts do not cause CPU spikes or memory leaks when fetching titles.
- [ ] CoreML predictions run in <50ms asynchronously.
- [ ] `MLUpdateTask` successfully modifies the model on disk.

---

### Phase 2: Intent-Aware Focus Engine Updates

This phase wires the CoreML brains into the core decision-making state machine.

#### Task 9: AI Category Enum & Profile Schema Update

**Description:** Update `WorkProfile` to include category-based allowance lists, migrating away from pure domain blocking.

**Acceptance criteria:**
- [ ] Add `allowedCategories: [Category]` to `WorkProfile`.
- [ ] Add `distractionCategories: [Category]` to `WorkProfile`.
- [ ] Ensure serialization handles backward compatibility with V2 profiles (seed default categories if missing).

**Verification:**
- [ ] Load a legacy V2 JSON profile; verify it initializes with default AI categories seamlessly.

**Dependencies:** Task 2

**Files likely touched:**
- `Anchored/Models/WorkProfile.swift`
- `Anchored/Engine/ProfileManager.swift`

**Estimated scope:** S

#### Task 10: V2 Domain Fallback Logic Integration

**Description:** V3 must still respect hardcoded URLs if the AI fails or is overridden. Implement the cascading resolution logic.

**Acceptance criteria:**
- [ ] Create `func resolveContext(context: AppContext, profile: WorkProfile) -> ResolutionState` in `FocusEngine`.
- [ ] Logic flow: Check explicit V2 URL list -> if nil -> Check CoreML Category -> if low confidence -> Fallback to V2 neutral behavior.
- [ ] `ResolutionState` is an enum: `.work`, `.distraction`, `.neutral`.

**Verification:**
- [ ] Unit test the cascading logic: explicit allowed domain trumps a ML distraction category.

**Dependencies:** Task 9

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`

**Estimated scope:** M

#### Task 11: FocusEngine State Machine Refactor

**Description:** Refactor the core `FocusEngine` state transitions to use the new `ResolutionState` rather than simple boolean `isDistraction` checks.

**Acceptance criteria:**
- [ ] Replace `URLMatcher` calls with `resolveContext`.
- [ ] Ensure neutral contexts do not trigger overlays but also do not lift them if an escalation is active.
- [ ] Handle state transitions gracefully without breaking V1/V2 timer behaviors.

**Verification:**
- [ ] Run the app; verify switching to a known productive app lifts the dim overlay.

**Dependencies:** Task 10

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`

**Estimated scope:** M

#### Task 12: Unit Testing the AI Focus Ruleset

**Description:** The state machine is highly complex in V3. Write extensive unit tests to guarantee safety against regressions.

**Acceptance criteria:**
- [ ] Test: `ResolutionState.work` lifts countdown pill.
- [ ] Test: `ResolutionState.distraction` starts countdown pill.
- [ ] Test: Switching rapidly between `.distraction` and `.neutral` maintains the countdown pill.

**Verification:**
- [ ] All `FocusEngineTests` pass in CI.

**Dependencies:** Task 11

**Files likely touched:**
- `AnchoredTests/Engine/FocusEngineTests.swift`

**Estimated scope:** M

#### Task 13: Local Override Cache (Immediate Effect Layer)

**Description:** `MLUpdateTask` can take several seconds to run. We need an immediate cache so the user isn't punished repeatedly while the model trains.

**Acceptance criteria:**
- [ ] Add an in-memory `overrideCache: [String: Category]` to `ContentClassifier`.
- [ ] When an override occurs, immediately write to the cache.
- [ ] `categorize` should check the cache before hitting the CoreML model.

**Verification:**
- [ ] Override a category, immediately query the same string, verify it returns the cached override instantly.

**Dependencies:** Task 11

**Files likely touched:**
- `Anchored/Engine/ContentClassifier.swift`

**Estimated scope:** S

### ✅ Checkpoint: Phase 2
- [ ] All unit tests pass.
- [ ] The app dynamically shows/hides overlays based on AI categorizations of live browser tabs.
- [ ] Fallback URL lists continue to function.

---

### Phase 3: The Bouncer (Hardcore Enforcement)

This phase adds the strict window-management enforcement for users who need a harder push.

#### Task 14: Hardcore Mode Profile Preferences Toggle

**Description:** Expose the V3 Hardcore mode to the user interface and data models.

**Acceptance criteria:**
- [ ] Add `isHardcoreModeEnabled: Bool` to `WorkProfile`.
- [ ] Add a prominent toggle in `ProfileEditorView` for "The Bouncer (Hardcore Mode)".
- [ ] Toggle state persists correctly via `ProfileManager`.

**Verification:**
- [ ] Toggle Hardcore Mode in Preferences, restart app, verify it remains toggled.

**Dependencies:** Task 9

**Files likely touched:**
- `Anchored/Models/WorkProfile.swift`
- `Anchored/App/Views/ProfileEditorView.swift`

**Estimated scope:** S

#### Task 15: Target Application Identification & Window Handling

**Description:** Build the utility functions to safely interact with macOS windows without causing kernel panics or data loss.

**Acceptance criteria:**
- [ ] Create `BouncerEngine` utility class.
- [ ] `func hideApplication(bundleID: String)` implemented using `NSWorkspace.shared.runningApplications`.
- [ ] Ensure it safely handles full-screen apps and multiple monitors.

**Verification:**
- [ ] Write a test script or debug button to hide a specific open app; verify it drops to Desktop cleanly.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Engine/BouncerEngine.swift`

**Estimated scope:** S

#### Task 16: The Bouncer Execution Engine & Sound Cue

**Description:** Wire `BouncerEngine` into the `FocusEngine`'s secondary countdown timer.

**Acceptance criteria:**
- [ ] Add `bouncerTimer` to `FocusEngine`.
- [ ] If Hardcore Mode is ON, start a secondary timer (e.g. 15 seconds) alongside the dim overlay.
- [ ] Upon expiration, fetch the active context bundle ID and call `BouncerEngine.hideApplication`.
- [ ] Play `.bouncerThunk` via `AudioEngine`.

**Verification:**
- [ ] Trigger a distraction with Hardcore Mode ON. Wait 15 seconds. Verify app vanishes and sound plays.

**Dependencies:** Task 14, Task 15

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Audio/AudioEngine.swift`

**Estimated scope:** M

#### Task 17: Bounce-Back Penalty Box Logic

**Description:** Implement the 2-minute penalty cooldown dictionary to prevent users from bypassing The Bouncer with `Cmd+Tab`.

**Acceptance criteria:**
- [ ] Add `penaltyBox: [String: Date]` to `FocusEngine`.
- [ ] When Bouncer executes, add the target bundle ID to the box with `now + 120s`.
- [ ] Add cleanup logic to prune expired entries from the dictionary periodically.

**Verification:**
- [ ] Unit test: verify bundle IDs expire from the penalty box after exactly 120 seconds.

**Dependencies:** Task 16

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`

**Estimated scope:** S

#### Task 18: Penalty Box Integration with AppSwitchMonitor

**Description:** Ensure that returning to a penalized app triggers instant enforcement.

**Acceptance criteria:**
- [ ] In `FocusEngine.onContextChange`, immediately check the `penaltyBox`.
- [ ] If penalized, bypass the countdown pill entirely and execute `BouncerEngine` instantly.
- [ ] Reset the penalty timer for another 2 minutes.

**Verification:**
- [ ] Manual check: Trigger Bouncer on Discord. Cmd+Tab back to Discord immediately. Verify it hides instantly without countdown.

**Dependencies:** Task 17

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`

**Estimated scope:** M

### ✅ Checkpoint: Phase 3
- [ ] `NSRunningApplication.hide()` functions correctly.
- [ ] The penalty box successfully traps and instantly hides repeat offenders.
- [ ] Hardcore mode can be toggled on/off safely mid-session.

---

### Phase 4: Global Overrides & Escapes

This phase provides the safety hatch for CoreML false positives and Bouncer false enforcements.

#### Task 19: Global Carbon Hotkey Listener (`NSEvent` / `HotKey`)

**Description:** Implement a robust global hotkey listener that works even when Anchored is in the background or obscured.

**Acceptance criteria:**
- [ ] Create `HotkeyManager` singleton.
- [ ] Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` or a Carbon wrapper.
- [ ] Listen for default binding: `Cmd + Shift + Option + A`.
- [ ] Expose an `onHotkeyTriggered` closure.

**Verification:**
- [ ] Print a log statement. Switch to Xcode. Press the hotkey. Verify log prints.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Engine/HotkeyManager.swift`
- `Anchored/App/AppDelegate.swift`

**Estimated scope:** M

#### Task 20: Emergency Bypass Hotkey Command

**Description:** Wire the hotkey into the `FocusEngine` and `ContentClassifier` to execute the emergency bypass sequence.

**Acceptance criteria:**
- [ ] On trigger, clear the current context from the `penaltyBox`.
- [ ] Add the current context's URL/Title to the local `overrideCache` as `.work`.
- [ ] Trigger `ContentClassifier.updateModelLocally` for permanent retraining.

**Verification:**
- [ ] Let Bouncer hide an app. Press hotkey. Cmd+Tab back to app. Verify it does NOT get hidden.

**Dependencies:** Task 19, Task 13

**Files likely touched:**
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Engine/HotkeyManager.swift`

**Estimated scope:** M

#### Task 21: Hotkey Settings UI (Rebinding Support)

**Description:** Build the preferences pane allowing users to change the hotkey to avoid conflicts with IDEs.

**Acceptance criteria:**
- [ ] Add a hotkey recorder UI component to `SettingsView`.
- [ ] Persist custom keycodes to `PreferencesManager`.
- [ ] `HotkeyManager` dynamically re-registers the listener when preferences change.

**Verification:**
- [ ] Bind hotkey to `Cmd + Option + X`. Verify old hotkey stops working and new hotkey works.

**Dependencies:** Task 19

**Files likely touched:**
- `Anchored/MenuBar/SettingsView.swift`
- `Anchored/Storage/PreferencesManager.swift`

**Estimated scope:** M

#### Task 22: OverlayManager Integration for Instant Lift

**Description:** Ensure that the UI reflects the hotkey bypass instantly.

**Acceptance criteria:**
- [ ] Triggering the hotkey should call `OverlayManager.liftOverlay()` immediately.
- [ ] Triggering the hotkey should flash a success state (green checkmark) in the `MenuBarController` icon for 2 seconds.

**Verification:**
- [ ] Trigger a dim overlay. Press hotkey. Verify overlay vanishes and menu bar flashes green.

**Dependencies:** Task 20

**Files likely touched:**
- `Anchored/Overlay/OverlayManager.swift`
- `Anchored/MenuBar/MenuBarController.swift`

**Estimated scope:** S

### ✅ Checkpoint: Phase 4
- [ ] Hotkeys work globally.
- [ ] Bypassing correctly trains the CoreML model.
- [ ] Visual feedback confirms the bypass.

---

### Phase 5: iCloud Sync Ecosystem

This phase unifies the user's settings across multiple Macs using built-in Apple APIs.

#### Task 23: ProfileManager Serialization for KVS

**Description:** Prepare the `ProfileManager` models for transmission over `NSUbiquitousKeyValueStore`.

**Acceptance criteria:**
- [ ] Ensure all arrays and nested objects in `WorkProfile` can be flattened or strictly encoded to JSON `Data`.
- [ ] Compress the payload if necessary to stay under the 1MB iCloud KVS limit per key.
- [ ] Add `lastModified: TimeInterval` to `WorkProfile` to aid in scalar conflict resolution.

**Verification:**
- [ ] Unit test: encode a massive profile with 500 URLs, verify payload size is acceptable.

**Dependencies:** Task 9

**Files likely touched:**
- `Anchored/Engine/ProfileManager.swift`
- `Anchored/Models/WorkProfile.swift`

**Estimated scope:** S

#### Task 24: NSUbiquitousKeyValueStore Core Integration

**Description:** Build the publisher/subscriber hooks for the iCloud daemon.

**Acceptance criteria:**
- [ ] When a profile saves, push to `NSUbiquitousKeyValueStore.default.set(data, forKey: "profiles")`.
- [ ] Register for `NSUbiquitousKeyValueStore.didChangeExternallyNotification`.
- [ ] Extract incoming data and pass it to the merge resolution logic.

**Verification:**
- [ ] Manual test across two Macs (or VMs) logged into the same Apple ID. Verify notifications fire.

**Dependencies:** Task 23

**Files likely touched:**
- `Anchored/Engine/ProfileManager.swift`

**Estimated scope:** L

#### Task 25: Granular Array Merge Logic (Union Strategy)

**Description:** Prevent "Last Write Wins" from deleting user changes made offline by unioning array lists.

**Acceptance criteria:**
- [ ] `func mergeSyncData(incoming: Profile, local: Profile) -> Profile`
- [ ] Perform `Set.union` on `distractionDomains`, `allowedDomains`, `allowedCategories`, and `distractionCategories`.
- [ ] Return the fully merged profile.

**Verification:**
- [ ] Unit test: Local has [A, B]. Incoming has [B, C]. Result must be [A, B, C].

**Dependencies:** Task 24

**Files likely touched:**
- `Anchored/Engine/ProfileManager.swift`

**Estimated scope:** M

#### Task 26: Settings Conflict Resolution

**Description:** Apply "Last Write Wins" correctly to scalar settings (booleans, integers) based on the timestamp.

**Acceptance criteria:**
- [ ] In `mergeSyncData`, compare `incoming.lastModified` vs `local.lastModified`.
- [ ] Overwrite `isHardcoreModeEnabled` and `countdownDuration` only if incoming is newer.
- [ ] Write the final merged profile back to local `UserDefaults`.

**Verification:**
- [ ] Unit test: Local timestamp is newer than incoming. Verify scalar values do NOT get overwritten.

**Dependencies:** Task 25

**Files likely touched:**
- `Anchored/Engine/ProfileManager.swift`

**Estimated scope:** S

#### Task 27: UI Publisher Hookups for Live Sync Updates

**Description:** Ensure that when a background sync occurs, any open Preference windows or Menu Bar dropdowns reflect the changes instantly without a restart.

**Acceptance criteria:**
- [ ] Use `@Published` or Combine pipelines on `ProfileManager.profiles`.
- [ ] Ensure SwiftUI views (`DomainEditorView`, `ProfileEditorView`) react to these changes.
- [ ] Flash a small "Synced" indicator in the UI if open.

**Verification:**
- [ ] Keep Preferences open on Mac A. Modify profile on Mac B. Verify Mac A's UI updates live.

**Dependencies:** Task 26

**Files likely touched:**
- `Anchored/App/Views/ProfileEditorView.swift`
- `Anchored/MenuBar/MenuBarPopoverView.swift`

**Estimated scope:** M

### ✅ Checkpoint: Phase 5
- [ ] iCloud sync works reliably within Apple's SLA limits.
- [ ] Array unions prevent offline data loss.
- [ ] UI remains reactive.

---

### Phase 6: ShadowTracking & AI-Dynamic Nudges

This phase makes proactive notifications smarter based on the cognitive load of the current task.

#### Task 28: ShadowTrackingEngine Context Extension

**Description:** Update the `ShadowTrackingEngine` to track time spent in specific AI Categories rather than just generic "productive" time.

**Acceptance criteria:**
- [ ] `ShadowTrackingEngine` consumes `ResolutionState` from `FocusEngine`.
- [ ] Maintain an active `currentCategory: Category?` and `timeInCategory: TimeInterval`.
- [ ] Reset counters appropriately on category shifts.

**Verification:**
- [ ] Unit test: verify timer increments while in `.coding`, and resets when switching to `.writing`.

**Dependencies:** Task 11

**Files likely touched:**
- `Anchored/Engine/ShadowTrackingEngine.swift`

**Estimated scope:** M

#### Task 29: AI-Dynamic Threshold Calculator

**Description:** Implement the modulation logic for nudge timers.

**Acceptance criteria:**
- [ ] Create `func calculateNudgeThreshold(category: Category) -> TimeInterval`.
- [ ] Assign 3 minutes for high-load (Coding, Creative).
- [ ] Assign 8 minutes for mid-load (Writing, Education).
- [ ] Assign `.infinity` for distractions.

**Verification:**
- [ ] Unit test: verify threshold output for all 7 categories matches spec.

**Dependencies:** Task 28

**Files likely touched:**
- `Anchored/Engine/ShadowTrackingEngine.swift`

**Estimated scope:** S

#### Task 30: Nudge Notifications & Cooldowns

**Description:** Fire macOS Local Notifications and enforce the 4-hour cooldown if dismissed.

**Acceptance criteria:**
- [ ] Fire `UNUserNotificationCenter` notification when threshold is met.
- [ ] If user clicks [Dismiss], log a 4-hour cooldown for that specific `Category` in memory.
- [ ] Do not fire subsequent nudges for a cooldown category.

**Verification:**
- [ ] Trigger nudge. Dismiss it. Manipulate system clock + 1 hour. Verify it does not re-trigger.

**Dependencies:** Task 29

**Files likely touched:**
- `Anchored/Engine/SmartNudgeManager.swift`

**Estimated scope:** M

### ✅ Checkpoint: Phase 6
- [ ] Notifications trigger proactively based on category thresholds.
- [ ] Cooldowns prevent notification fatigue.

---

### Phase 7: Dashboard UI & Metrics Migration

This phase enriches the local analytics dashboard with the new AI intelligence.

#### Task 31: SQLite V3 Schema Migration (Adding ai_category)

**Description:** Safely migrate existing V2 user databases to support the new column.

**Acceptance criteria:**
- [ ] Write GRDB migration: `ALTER TABLE sessions ADD COLUMN ai_category TEXT;`
- [ ] Execute migration on app launch via `DatabaseMigrator`.
- [ ] Ensure backward compatibility (existing rows evaluate as `NULL`).

**Verification:**
- [ ] Boot app with a V2 database. Verify migration succeeds without dropping rows.

**Dependencies:** None

**Files likely touched:**
- `Anchored/Storage/SQLiteSessionStore.swift`

**Estimated scope:** S

#### Task 32: SessionStore Ingestion Update

**Description:** Pass the CoreML category from the `FocusEngine` down to the `SQLiteSessionStore` during event logging.

**Acceptance criteria:**
- [ ] Update `SessionEvent` struct to include `ai_category: String?`.
- [ ] `FocusEngine` includes the category when logging `distraction_detected` and `session_end` events.

**Verification:**
- [ ] Complete a session. Query the SQLite DB manually. Verify the `ai_category` column is populated.

**Dependencies:** Task 31, Task 11

**Files likely touched:**
- `Anchored/Models/SessionEvent.swift`
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Storage/SQLiteSessionStore.swift`

**Estimated scope:** M

#### Task 33: Dashboard SQL Queries Update

**Description:** Write new aggregate queries to power the AI breakdown visuals.

**Acceptance criteria:**
- [ ] `func fetchCategoryBreakdown(for dateRange: DateInterval) -> [String: TimeInterval]`
- [ ] Handle `NULL` legacy events by bucketing them into an "Uncategorized" generic bucket.

**Verification:**
- [ ] Unit test: Verify SQL aggregates time correctly across multiple AI categories.

**Dependencies:** Task 31

**Files likely touched:**
- `Anchored/Storage/DashboardQueries.swift`

**Estimated scope:** M

#### Task 34: Dashboard UI Category Breakdown Chart

**Description:** Build the new horizontal stacked bar chart for the Dashboard.

**Acceptance criteria:**
- [ ] Implement `CategoryBreakdownView` in SwiftUI.
- [ ] Map the 7 categories to distinct, visually harmonious brand colors.
- [ ] Display percentages and raw time next to each bar.

**Verification:**
- [ ] Render the view in Xcode Previews with mock data. Verify styling.

**Dependencies:** Task 33

**Files likely touched:**
- `Anchored/App/Views/DashboardView.swift`
- `Anchored/App/Views/CategoryBreakdownView.swift` (new)

**Estimated scope:** M

#### Task 35: Top Distractions UI AI Enrichment

**Description:** Enhance the V2 "Top Distractions" list to group or label items by their CoreML category if known.

**Acceptance criteria:**
- [ ] Update `TopDistractionsView` row items.
- [ ] If `ai_category` is known, display a small badge or icon (e.g., 🍿 for Entertainment) next to the domain name.

**Verification:**
- [ ] Render view with mock data. Verify badges appear.

**Dependencies:** Task 34

**Files likely touched:**
- `Anchored/App/Views/TopDistractionsView.swift`

**Estimated scope:** S

### ✅ Checkpoint: Phase 7
- [ ] SQLite handles upgrades gracefully.
- [ ] Dashboard provides rich insights into intent rather than just domains.

---

### Phase 8: Polish, Dogfooding & Rollout

#### Task 36: CoreML Drift QA Plan

**Description:** Ensure that continuous `MLUpdateTask` usage does not cause catastrophic forgetting or model bloat.

**Acceptance criteria:**
- [ ] Write a script to monitor the file size of `AnchoredTextClassifier.mlmodelc` over 100 consecutive retraining cycles.
- [ ] Implement an upper bounds cap or reset mechanism if drift becomes severe.

**Estimated scope:** L

#### Task 37: Menu Bar UI Updates for AI Mode

**Description:** Visually indicate to the user when AI is actively guarding them versus standard V2 rules.

**Acceptance criteria:**
- [ ] Update the `MenuBarPopoverView` to display a subtle "✨ AI Engine Active" badge.
- [ ] Update tooltips to explain AI categorizations.

**Estimated scope:** S

#### Task 38: Performance Profiling

**Description:** V3 adds significant background processing. Profile the energy impact.

**Acceptance criteria:**
- [ ] Run Xcode Energy Diagnostics.
- [ ] Ensure average CPU overhead remains < 2% during active usage.
- [ ] Ensure Memory footprint remains < 100MB even with the `.mlmodelc` loaded into RAM.

**Estimated scope:** M

---

## Parallelization Opportunities

Because Anchored uses a decoupled architecture, multiple agents can tackle V3 features concurrently.

**Safe to parallelize (no shared state):**
- **Phase 1 (CoreML)** and **Phase 5 (iCloud Sync)** have literally zero overlapping state. They can be built at the same time.
- **Phase 7 (Dashboard UI)** can be built against mocked SQL data while the ML engine is being hooked up.
- **Phase 4 (Hotkeys)** can be built independently of the Bouncer logic.

**Must be sequential:**
- **Phase 2 (Focus Engine)** must wait for **Phase 1**.
- **Phase 3 (Bouncer)** must wait for **Phase 2**.
- **Phase 6 (Nudges)** must wait for **Phase 2**.

**Suggested Agent Execution Strategy:**

| Step | Agent A (Core/ML) | Agent B (Sync & Nudges) | Agent C (UI & Overrides) |
|---|---|---|---|
| **1** | **Phase 1:** Tasks 1-4 (ML & Context Extraction) | **Phase 5:** Tasks 23-25 (KVS Setup & Merge) | **Phase 7:** Tasks 31, 33-35 (Mocked Dashboard) |
| **2** | **Phase 1:** Tasks 5-8 (ML Async & Retraining) | **Phase 5:** Tasks 26-27 (UI Sync Hookups) | **Phase 4:** Tasks 19, 21 (Hotkey Setup & UI) |
| **3** | **Phase 2:** Tasks 9-13 (Focus Logic & Cache) | *(Waiting on Phase 1/2)* | *(Waiting on Phase 1/2)* |
| **4** | **Phase 3:** Tasks 14-18 (The Bouncer & Penalty) | **Phase 6:** Tasks 28-30 (AI Nudges & Cooldowns) | **Phase 7:** Task 32 (SQL Event Ingestion) |
| **5** | **Phase 8:** Task 36 (ML Drift QA) | **Phase 8:** Task 38 (Performance Profiling) | **Phase 4:** Tasks 20, 22 (Emergency Bypass Linkage)|
| **6** | *(Done)* | *(Done)* | **Phase 8:** Task 37 (Menu Bar AI UI) |



================================================================================
FILE: anchored-v3.md
SIZE: 30299
================================================================================

# Anchored V3 — The Intelligence Update

> **Prerequisite:** This spec assumes [Anchored V2 (Permission Gate)](file:///Users/varun/Development/Anchor/docs/ideas/anchored-v2.md) has shipped and is stable. V3 builds heavily on V2's context-aware browser tracking and SQLite storage, adding new layers of intelligence, enforcement, and ecosystem sync.

## Problem Statement
**How might we** make Anchored smarter about *what* the user is actually doing, provide a stricter fallback when gentle nudges fail, and unify the experience across multiple Macs, all without sacrificing our zero-ritual, privacy-first philosophy?

## V3 Summary

V3 transforms Anchored from a tool that reads URLs into a tool that understands intent. It adds "teeth" for users who need a stronger push, and bridges the gap for users with multiple machines. The four major additions:

1. **AI Content Awareness (The Brains)** — Moving beyond simple URL domain matching to intelligent, on-device categorization of page contents with personalized, on-device model retraining.
2. **Hardcore Mode / "The Bouncer" (The Brawn)** — An optional, strict enforcement layer that actively hides distractions when ambient dimming isn't enough, complete with cooldown mechanics and emergency overrides.
3. **Ecosystem Sync (The Bridge)** — iCloud Key-Value sync for profiles and settings across multiple Macs with granular merging, while keeping analytics strictly local.
4. **AI-Dynamic Smart Nudges (The Guide)** — Proactive, context-aware nudges that adapt their timing based on the cognitive intensity of the work detected.

---

## 1. Local AI Content Awareness (The Brains)

### Philosophy

In V2, a domain like `youtube.com` was a blunt instrument. If it was in the distraction list, all of YouTube was bad. If it was in the allowed list, all of YouTube was good. But context matters: watching a Swift tutorial on YouTube is productive; watching gaming highlights is a distraction. V3 solves this by understanding *what* the user is viewing, entirely on-device to preserve privacy.

### Architecture: Updatable ML Models

We will train and deploy a lightweight, quantized CoreML text classifier model (`AnchoredTextClassifier.mlmodel`). Crucially, this model will be **Updatable**, allowing it to personalize its predictions based on the user's specific habits without ever sending data to a server.

The model does not need to read the entire DOM. It operates purely on two highly-dense signals we already collect in V2:
1. The **Window Title** (which usually contains the video title, article name, or document context).
2. The **URL** (which contains routing paths that hint at context, e.g., `/watch?v=...` vs `/shorts/...`).

### CoreML Data Models and Shapes

The CoreML model will be a text classifier, likely based on a fine-tuned MobileBERT or an NLP bag-of-words architecture depending on memory constraints.

**Inputs:**
- `text_input` (String): A concatenated string of `Title + " | " + URL`.

**Outputs:**
- `category` (String): The predicted class label.
- `categoryProbability` (Dictionary<String, Double>): Confidence scores for all classes.

```swift
class ContentClassifier {
    private var model: MLModel // AnchoredTextClassifier.mlmodel
    private let confidenceThreshold: Double = 0.75
    
    /// Returns the most likely category for the given context
    func categorize(title: String, url: URL) -> Category? {
        let inputString = "\(title) | \(url.absoluteString)"
        
        // 1. Check local exact-match overrides first (fast path)
        if let userOverride = fetchOverride(for: url) {
            return userOverride
        }
        
        // 2. Run ML Prediction
        guard let prediction = try? model.prediction(from: AnchoredInput(text: inputString)),
              let probabilities = prediction.featureValue(for: "categoryProbability")?.dictionaryValue,
              let topLabel = prediction.featureValue(for: "category")?.stringValue,
              let confidence = probabilities[topLabel]?.doubleValue else {
            return nil
        }
        
        // 3. Fallback if confidence is too low
        if confidence < confidenceThreshold {
            return nil // Fallback to V2 domain lists
        }
        
        return Category(rawValue: topLabel)
    }
    
    /// Retrains the model locally when the user overrides a prediction
    func updateModelLocally(title: String, url: URL, correctCategory: Category) {
        let inputString = "\(title) | \(url.absoluteString)"
        
        let featureProvider = try? MLDictionaryFeatureProvider(dictionary: [
            "text_input": MLFeatureValue(string: inputString),
            "category": MLFeatureValue(string: correctCategory.rawValue)
        ])
        
        let trainingData = MLArrayBatchProvider(array: [featureProvider!])
        
        let updateTask = try MLUpdateTask(forModelAt: modelURL, trainingData: trainingData, configuration: nil) { context in
            // Handle completion, replace old model in Application Support
        }
        updateTask.resume()
    }
}
```

### Pre-defined Categories

Instead of maintaining brittle domain lists, users will now select which **Categories** are allowed during a focus session. The model classifies the page into one of the following:

- **🎓 Education & Documentation** (Tutorials, Docs, Wikipedia, StackOverflow)
- **💻 Coding & Technical** (GitHub, AWS Console, Terminal, IDEs)
- **✍️ Writing & Productivity** (Google Docs, Notion, Linear, Email)
- **🎨 Creative & Design** (Figma, Spline, Dribbble)
- **🍿 Entertainment & Media** (Netflix, Gaming videos, Sports)
- **🛒 Shopping** (Amazon, Shopify storefronts)
- **🗣 Social & Discussion** (Twitter/X, Reddit, Instagram, TikTok)

### V3 Decision Logic Updates

When the `BrowserURLMonitor` fetches a URL, it now also fetches the window title.

```mermaid
flowchart TD
    A[BrowserURLMonitor] -->|Context: Title + URL| B(ContentClassifier)
    B --> C{Confidence > 75%?}
    C -->|Yes| D{Category allowed?}
    C -->|No| E[Fallback to V2 Domain List]
    
    D -->|Yes| F[Treat as Work]
    D -->|No| G[Trigger Escalation]
    
    E --> H{Domain explicitly allowed?}
    H -->|Yes| F
    H -->|No| G
```

### Onboarding: The "Silent Scholar"

How do we introduce this to the user? We don't.
To maintain the "Zero Friction" rule, there is no setup wizard where the user has to categorize their top 10 sites. 
The CoreML model ships with a robust baseline training. As the user encounters false positives, they use the Menu Bar override or the Global Bypass Hotkey. Each time an override occurs, the `MLUpdateTask` quietly retrains the model in the background. The app becomes tailored to their specific workflow silently and organically over time.

---

## 2. Hardcore Mode: "The Bouncer" (The Brawn)

### Philosophy

Anchored's core thesis is "ambient friction, not walls." The 50% screen dim is usually enough to break the trance of a distraction. However, some users require a fail-safe. If they are willing to work through a 50% dimmed screen to watch TikTok, they need a harder intervention. Enter "The Bouncer."

### Trigger Condition

Hardcore Mode is an **opt-in boolean toggle** inside the Work Profile editor. 
When enabled, the ambient escalation phase has a strict time limit. 

1. User switches to a distraction app (e.g., Discord).
2. Countdown pill appears: *"Strict Focus... Hiding app in 10s"*
3. Screen dims to 50% as usual. 
4. **NEW in V3:** A secondary internal timer starts (e.g., 15 seconds).
5. If the user does not return to a work app before this secondary timer expires, The Bouncer activates.

### Enforcement Mechanism (App Hiding)

Instead of using the aggressive `killall` command (which can lose user data if they were typing a message) or Apple's Screen Time APIs (which are notoriously brittle), Anchored uses standard macOS window management.

```swift
func activateBouncer(targetBundleID: String) {
    guard let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundleID }) else { return }
    
    // Play a harsh, mechanical "thunk" sound to indicate enforcement
    AudioEngine.play(.bouncerThunk)
    
    // Forcefully hide the application, dropping the user back to the desktop or previous work app
    targetApp.hide()
}
```

### The "Bounce-Back" Penalty

What stops the user from just pressing `Cmd+Tab` immediately after The Bouncer hides the app?
We implement a **Bounce-Back Penalty cooldown**.

If The Bouncer hides an application, that specific `bundleIdentifier` is placed in a penalty box for **2 minutes**. 
If the `AppSwitchMonitor` detects the user switching to that app again within the 2-minute window, **The Bouncer activates instantly**. No 10-second countdown pill. No ambient dimming. It just vanishes instantly with a harsh "thunk" sound.

```mermaid
sequenceDiagram
    participant User
    participant NSWorkspace
    participant FocusEngine
    participant TheBouncer

    User->>NSWorkspace: Switches to Discord
    NSWorkspace->>FocusEngine: onContextChange(Discord)
    FocusEngine->>User: Shows 10s Countdown Pill
    User->>User: Ignores countdown
    FocusEngine->>TheBouncer: Timer expired. Activate.
    TheBouncer->>NSWorkspace: targetApp.hide()
    TheBouncer->>FocusEngine: Register 2-min penalty for Discord
    
    User->>NSWorkspace: Presses Cmd+Tab to Discord
    NSWorkspace->>FocusEngine: onContextChange(Discord)
    FocusEngine->>FocusEngine: Check penalty box... Discord is penalized!
    FocusEngine->>TheBouncer: Instant Activate (No delay)
    TheBouncer->>NSWorkspace: targetApp.hide()
```

### The Global Emergency Bypass Hotkey

Because The Bouncer is strict, and because the CoreML model will occasionally misclassify a vital research tool as a distraction, we must provide an escape hatch. 
A configurable global hotkey (default: `Cmd + Shift + Option + A`) allows the user to instantly whitelist the current application or URL context.

When triggered:
1. The Bouncer cooldown for the app is instantly cleared.
2. The current URL/Title is fed into the `ContentClassifier.updateModelLocally()` to train it that this context is actually Work.
3. The ambient overlay lifts instantly, and a small green success checkmark appears in the menu bar icon.

```swift
func handleGlobalHotkey() {
    let currentContext = monitor.currentContext
    
    // 1. Clear Penalty
    penaltyBox.remove(currentContext.bundleID)
    
    // 2. Add to Local Override list (Immediate effect)
    ProfileManager.shared.addOverride(url: currentContext.url, category: .coding)
    
    // 3. Trigger async model retraining
    classifier.updateModelLocally(title: currentContext.title, url: currentContext.url, correctCategory: .coding)
    
    // 4. Update UI
    OverlayManager.shared.liftOverlay()
    MenuBarController.shared.flashSuccess()
}
```

---

## 3. Ecosystem Sync (The Bridge)

### Philosophy

Power users often have a MacBook Air for the couch and a Mac Studio for the desk. Recreating their custom profiles, adjusting their distraction lists, and tweaking their settings on every machine is tedious. Anchored needs to feel like one unified system across all their devices, but without requiring a mandatory cloud account or compromising the privacy of their focus analytics.

### Architecture: NSUbiquitousKeyValueStore

We will use `NSUbiquitousKeyValueStore` (iCloud Key-Value sync) to sync lightweight configuration data. This API is built into macOS, requires no backend infrastructure, and uses the user's existing Apple ID.

**What Syncs (The Settings):**
- Work Profiles (Coding, Writing, Custom definitions)
- Distraction Lists, Allowed Domains, and Allowed Categories
- User-generated ML Overrides (URLs marked explicitly as work)
- Preferences (Countdown duration, Focus threshold)
- Hardcore Mode toggles

**What Stays Local (The Analytics):**
- SQLite Database (`anchored.db`)
- Focus Session History
- Today's Timeline
- Distraction metrics and streaks
- The locally retrained ML Model (`AnchoredTextClassifier.mlmodelc`)

By keeping analytics local, we ensure that the user's granular activity log (exactly what time they opened Xcode and when they got distracted by Twitter) never leaves the specific hardware where it occurred. It also avoids complex SQLite merge conflicts across iCloud Drive.

### Granular Merge (Union) Strategy

A common edge case in Key-Value store syncing is conflict resolution. 
If a user is on their laptop offline and adds "reddit.com" to their Distraction List, and simultaneously on their desktop adds "tiktok.com" to the same profile's Distraction List... what happens when they both connect?

Using a "Last Write Wins" strategy would delete one of the edits.
Instead, Anchored uses a **Granular Merge** strategy for arrays.

```swift
func mergeSyncData(incomingProfile: Profile, localProfile: Profile) -> Profile {
    var merged = localProfile
    
    // Union the arrays to preserve additions from both clients
    merged.distractionDomains = Array(Set(incomingProfile.distractionDomains).union(localProfile.distractionDomains))
    merged.allowedDomains = Array(Set(incomingProfile.allowedDomains).union(localProfile.allowedDomains))
    merged.allowedCategories = Array(Set(incomingProfile.allowedCategories).union(localProfile.allowedCategories))
    
    // For scalars (like countdownDuration), Last Write Wins based on timestamp
    if incomingProfile.lastModified > localProfile.lastModified {
        merged.countdownDuration = incomingProfile.countdownDuration
        merged.isHardcoreModeEnabled = incomingProfile.isHardcoreModeEnabled
    }
    
    return merged
}
```

When a merge completes, if the user has the Menu Bar or Profile Editor open, the UI dynamically reloads via a Combine publisher or NotificationCenter broadcast.

---

## 4. AI-Dynamic Smart Nudges (The Guide)

### Philosophy

In V1 and V2, Anchored is entirely reactive. It only triggers when you exit a work app. 
In V3, we want to proactively suggest focusing *while* you are working, but without being as annoying as a generic "Pomodoro" timer.

### Architecture

We introduce the `ShadowTrackingEngine`, which runs constantly in the background (pausing when the Mac sleeps). It evaluates the continuous time spent in productive apps. 
However, rather than using a fixed timer (e.g., nudge after 10 minutes), the timer is dynamically modulated by the **CoreML model's assessment of cognitive intensity**.

```swift
func calculateNudgeThreshold(category: Category) -> TimeInterval {
    switch category {
    case .coding, .creative:
        // High cognitive load contexts indicate deep flow state starting quickly.
        // Nudge early to lock it in before a distraction can derail it.
        return 3 * 60 // 3 minutes
        
    case .writing, .education:
        // Medium cognitive load (reading, typing emails)
        return 8 * 60 // 8 minutes
        
    case .shopping, .entertainment, .social:
        // Distractions. Do not nudge to start a focus session.
        return .infinity
    }
}
```

When the threshold is reached, Anchored fires a macOS Local Notification:
*"You've been in flow for a bit. Drop the anchor?"*
With action buttons: **[Lock In]** and **[Dismiss]**.

### Smart Nudge Cooldowns

To prevent notification fatigue, if a user clicks **[Dismiss]** on a Smart Nudge, that specific app/category is placed on a cooldown for **4 hours**. Anchored will not proactively nudge the user for that category again during that time, although the user can still manually start a session from the menu bar.

---

## 5. UI Updates & Dashboard AI Integration

### Dashboard ASCII Mockup

V3 updates the Dashboard to reflect AI Categories, helping users understand where their time actually goes beyond just raw URLs.

```
┌──────────────────────────────────────────────────────────┐
│  ⚓ Anchored — Focus Dashboard                     [×]   │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Today                              This Week            │
│  ┌──────────────────┐              ┌──────────────────┐  │
│  │  3h 42m focused  │              │  18h 15m focused │  │
│  │  ██████████░░░░░░ │              │  ████████░░░░░░░ │  │
│  │  4 sessions      │              │  22 sessions     │  │
│  └──────────────────┘              └──────────────────┘  │
│                                                          │
│  Focus Streak: 🔥 7 days                                 │
│                                                          │
│  ── Category Breakdown (NEW) ──────────────────────────  │
│                                                          │
│  💻 Coding & Tech       ██████████████████░░  65%        │
│  🎓 Education & Docs    ████████░░░░░░░░░░░░  30%        │
│  ✍️ Writing             █░░░░░░░░░░░░░░░░░░░   5%        │
│                                                          │
│  ── Top Distractions This Week ────────────────────────  │
│                                                          │
│  1. Discord             12 interruptions    avg 4m each  │
│  2. 🍿 Entertainment     8 interruptions    avg 6m each  │
│  3. 🗣 Social            5 interruptions    avg 2m each  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

The Dashboard query logic will prioritize grouping by `ai_category` if available, falling back to `app_bundle_id` or domain for apps that don't have web context.

---

## 6. Architecture Changes from V2

### Module Boundary Updates

```diff
  ┌──────────────────────────────────────────┐
  │         FocusEngine (Core)               │
  │                                           │
  │  ┌─────────────────────────────────────┐ │
  │  │  ActivityMonitor «protocol»         │ │
  │  │                                      │ │
  │  │  ├─ AppSwitchMonitor                 │ │
  │  │  └─ BrowserURLMonitor                │ │
+ │  │      └─ Title Extraction (V3)       │ │
  │  └─────────────────────────────────────┘ │
  │                                           │
+ │  ┌─────────────────────────────────────┐ │
+ │  │  ContentClassifier (CoreML)         │ │
+ │  │   ├─ AnchoredTextClassifier.mlmodel │ │
+ │  │   ├─ MLUpdateTask (Retraining)      │ │
+ │  │   └─ Category Mapper                │ │
+ │  └─────────────────────────────────────┘ │
  │                                           │
+ │  ┌─────────────────────────────────────┐ │
+ │  │  ShadowTrackingEngine (Nudges)      │ │
+ │  │   └─ NotificationManager            │ │
+ │  └─────────────────────────────────────┘ │
  │                                           │
  │  ┌──────────────┐  ┌──────────────────┐  │
  │  │ SessionStore │  │  ProfileManager  │  │
- │  │  (SQLite)    │  │  (UserDefaults)  │  │
+ │  │  (SQLite)    │  │  (CloudKit KVS)  │  │
  │  └──────────────┘  └──────────────────┘  │
  └──────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │         OverlayManager                  │
  │  ├─ ExitTriggerCapsule                  │
  │  ├─ CountdownPill                       │
  │  ├─ DimOverlay                          │
+ │  └─ The Bouncer (NSRunningApplication)  │
+ │      └─ CooldownTimer                   │
  └──────────────────────────────────────────┘
```

### Database Schema Updates

While historical analytics don't sync, we need to log the new AI categories for the local dashboard.

```sql
-- V3 Migration
ALTER TABLE sessions ADD COLUMN ai_category TEXT;
-- Populated with 'education', 'entertainment', etc., when a browser event occurs.
```

When upgrading from V2 to V3, `ai_category` will simply be `NULL` for older records. The Dashboard queries will need to account for this gracefully.

### Profile Migration (UserDefaults)

V2 Profiles only had lists of URLs. V3 Profiles have `allowedCategories` and `distractionCategories`.
On first launch, `ProfileManager` runs a migration script:

```swift
func migrateV2ToV3Profiles() {
    for profile in allProfiles {
        if profile.allowedCategories == nil {
            // Seed default categories based on profile name
            if profile.name == "Coding" {
                profile.allowedCategories = [.coding, .education]
                profile.distractionCategories = [.entertainment, .social, .shopping]
            }
            // ... etc
        }
    }
}
```

---

## 7. Testing & Quality Assurance Plan

Because V3 touches sensitive enforcement (The Bouncer) and machine learning (CoreML), rigorous testing is required before launch.

### CoreML Unit Testing
- Create a static `.csv` dataset of 5,000 common URLs + Titles and their expected category.
- Write an `XCTestCase` that iterates over the dataset, feeding it to `ContentClassifier`, asserting that accuracy remains >85%.
- Test the `MLUpdateTask` loop by explicitly retraining the model with a known wrong label, and asserting the model's prediction flips on the next query.

### The Bouncer Edge-Case Testing
- **Test:** Run The Bouncer against a full-screen app. Assert that it properly hides and returns the user to the Desktop/Work app.
- **Test:** Trigger the Bounce-Back penalty, then use the Global Emergency Bypass Hotkey. Assert the penalty is cleared and the app remains visible.
- **Test:** Verify `NSRunningApplication.hide()` does not cause data loss in unsaved documents in target apps.

### iCloud Sync Stress Testing
- Create two local Mac VMs. Disconnect Network on VM A.
- Edit Profile X on VM A. Edit Profile X on VM B.
- Reconnect Network on VM A.
- Assert that `Granular Merge` logic successfully unions both lists without data loss.

---

## 8. Rollout Strategy & Privacy Policy Updates

### The Privacy Promise (Website & Onboarding)
V3 must explicitly reiterate Anchored's privacy stance:
> "Anchored V3 introduces AI, but we do it the right way. Your window titles and URLs never leave your Mac. The CoreML model runs entirely on-device using the Neural Engine, and personalization happens locally. No telemetry, no API calls, no snooping."

### Phased Rollout
- **Phase 1: Alpha (Internal)** - Focus strictly on training the CoreML model dataset and reducing false positives.
- **Phase 2: Beta (TestFlight/GitHub Releases)** - Introduce The Bouncer and iCloud Sync. Monitor feedback on sync delays and conflict resolution.
- **Phase 3: Public V3 Launch** - Update the marketing site with the "Intelligence Update" branding.

---

## 9. V3 Scope Summary

**In (V3):**
- CoreML integration and model training (`ContentClassifier`)
- Updatable CoreML framework integration for local retuning (`MLUpdateTask`)
- `BrowserURLMonitor` updates to fetch Window Titles alongside URLs
- AI Category-based resolution logic in `FocusEngine`
- Work Profile UI updates (Category multi-select checkboxes)
- "The Bouncer" Hardcore Mode (Profile toggle + `NSRunningApplication.hide()`)
- "Bounce-Back" Penalty logic (2-minute instant-hide cooldown)
- Global Emergency Bypass Hotkey (Bouncer escape hatch + CoreML retraining trigger)
- `NSUbiquitousKeyValueStore` integration for ProfileManager and PreferencesManager
- Granular Merge conflict resolution for iCloud sync arrays
- `ShadowTrackingEngine` for AI-Dynamic Smart Nudges
- Dashboard updates to show "Top Distraction Categories" alongside domains
- V3 Database migration (adding `ai_category` column)
- Profile Migration logic to bridge V2 domains to V3 categories

**Not In V3 (Deferred to V4+):**
- **Calendar & Task Integration** — Auto-starting sessions based on Jira/Linear/Calendar. This adds heavy OAuth/API dependencies and departs from the "passive-active" model.
- **Team Presence (Slack/Discord status sync)** — Requires deep API integrations and moves the app from a personal utility to an enterprise tool.
- **CloudKit Analytics Sync** — Syncing the full SQLite DB via SwiftData/CloudKit is architecturally massive and raises privacy flags for some users. We will stick to local-only analytics.
- **Full DOM Scraping** — The CoreML model will *only* read titles and URLs. Reading the full page DOM is too heavy (battery drain) and feels like spyware.

## 10. Open Questions

- **Model Training:** Where do we source the base dataset for training the initial CoreML model? We need a robust dataset of (Title + URL) -> Category mapping. (e.g., Kaggle datasets for web classification).
- **CoreML Accuracy vs Memory:** Updatable CoreML models can sometimes grow in memory size as they are retrained. We need to monitor the `.mlmodelc` bundle size to ensure it doesn't bloat the app's footprint over a 12-month period.
- **Global Hotkey Conflicts:** The default bypass hotkey (`Cmd + Shift + Option + A`) is fairly safe, but what if it conflicts with an IDE shortcut? We must ensure the UI for rebinding this key is extremely obvious in the Preferences, and we must check for collisions using macOS Carbon APIs upon registration.
- **Cloud Sync Delay:** `NSUbiquitousKeyValueStore` can sometimes take 10-60 seconds to propagate. Is this acceptable, or will users expect instantaneous handoff (which would require a dedicated backend)?

---

## 11. Implementation Progress
- [ ] CoreML Baseline Model Training (Dataset curation)
- [ ] Updatable CoreML Integration (`MLUpdateTask`)
- [ ] BrowserMonitor Window Title extraction (AppleScript/AXUI updates)
- [ ] ProfileManager Cloud Sync (`NSUbiquitousKeyValueStore`)
- [ ] iCloud Granular Merge Conflict Logic
- [ ] The Bouncer (App Hiding Enforcement)
- [ ] Bounce-Back Penalty Timer Logic
- [ ] Global Emergency Bypass Hotkey System (`NSEvent.addGlobalMonitorForEvents`)
- [ ] UI Updates (Categories & Hardcore Mode Toggle in NIBs/SwiftUI)
- [ ] Dashboard Category Metrics & DB Migration Script
- [ ] ShadowTrackingEngine & AI-Dynamic Nudges
- [ ] Interactive Onboarding Simulation Stage
- [ ] Settings Tutorial Replay Mode

*(Note: A codebase scan confirms that none of the V3 features have been implemented yet. The implementation is currently purely in the spec phase).*

---

## 12. Interactive Onboarding & Tutorial (V3 Addition)

### Problem Statement
How might we provide new users with a comprehensive, interactive setup that simulates Anchored's core mechanics (warnings and dimming) so they confidently complete their first real work session, while allowing this tutorial to be replayed on demand?

### Recommended Direction
**The "Live Fire" Simulation Tour.** We expand the linear onboarding to include a new "Simulation" stage. During this stage, we trigger a mock distraction event. The user gets to see the 10-second warning pill and experience the screen dimming safely. The tutorial auto-plays the distraction, but requires the user to click the actual UI buttons to "escape" and set an anchor, building muscle memory. This is encapsulated into a `TutorialManager` that can be triggered from an "Advanced" tab in the Settings menu at any time.

### Key Assumptions to Validate
- [ ] **Assumption:** Users have the patience to sit through a longer setup without abandoning the app.
- [ ] **Assumption:** We can reuse the existing `DimOverlay` and `CountdownPill` for the tutorial without polluting real database logs in `SQLiteSessionStore`.
- [ ] **Assumption:** Users will actually want to replay the tutorial from the Advanced settings tab.

### MVP Scope
**In Scope:**
- Expanding onboarding with an interactive "Simulation" step.
- A "Tutorial Mode" that safely triggers UI overlays without affecting real session state.
- A "Replay Tutorial" button in the Advanced settings tab.
- Tooltips explaining what is happening, requiring manual button clicks to escape.

**Out of Scope:**
- Forcing a real 25-minute work session to finish onboarding.
- Real browser tracking during the tutorial (bypasses Accessibility gate).

### Not Doing (and Why)
- **Not doing video slideshows:** Passive, users skip them. Needs to be interactive.
- **Not using real browser tracking for the tutorial:** Accessibility permissions happen later to reduce upfront friction. Fake the trigger instead.



================================================================================
FILE: docs/architecture/anchored-architecture.md
================================================================================

# Anchored Architecture

## Purpose

This document is the fast path for future agents and engineers. Read it before exploring the repo when you need to understand:

- how the app is composed at runtime
- where focus tracking logic lives
- where persistence and analytics live
- which invariants must not be broken
- where V2.6 is expected to land

It is intentionally opinionated and file-oriented so you do not need to search the entire repository to find the relevant seams.

## Current State Snapshot

- Product: macOS menu-bar focus app
- Language/runtime: Swift 5.7, AppKit + SwiftUI, macOS 13
- Project generation: XcodeGen via `project.yml`
- Persistence: GRDB over SQLite, with legacy JSON migration in `SessionStore`
- Main composition root: `Anchored/App/AppDelegate.swift`
- Core runtime loop: `AppSwitchMonitor -> FocusEngine -> OverlayManager/MenuBarController/SessionStore`
- Current context model: `bundleID + optional URL + title`, surfaced as `AppContext`
- Work profiles now persist per-profile `allowedApps` alongside distraction apps and domains
- Focus classification uses profile `allowedApps`/domains for native apps and explicit browser rules, with a local browser-content heuristic suppressing known gaming and entertainment contexts, smart AI classification layers (`SmartAppClassifier` and `SmartWebClassifier`) dynamically classifying unregistered productive IDEs/apps and web coding forums/tutorials, and an on-device visual AI classification layer (`SmartImageClassifier` utilizing macOS native Vision framework or a local Apple Silicon MLX vision-language model like `SmolVLM-256M-Instruct-4bit`) to inspect the active window's visual layout and prevent false alarms.
- The application includes privacy controls to toggle the AI Visual Productivity Check (`PreferencesManager.enableImageClassification`) and choose/download the local MLX VLM model (`useLocalGemma` and `downloadGemmaModel()`) during onboarding and in settings.
- The application dynamically updates its `NSApplication` activation policy: it runs as a background-only accessory app (no Dock or Cmd+Tab app switcher icon) by default, but elevates to a regular application (showing the Dock/Cmd+Tab icon) when onboarding, settings, or focus session windows are open.
- The onboarding focus threshold and distraction countdown remain separate: focus threshold controls session establishment, while countdown duration controls fog/dimming after distraction
- Auto Voyage now runs continuously in the normal runtime: `ShadowTrackingEngine` watches focus context on device, and `SmartNudgeManager` only adds an optional local notification when auto-focus starts
- Context history now persists sanitized observations into a dedicated `context_observations` table through `ContextHistoryPipeline` and `ContextHistoryStore`
- `PreferencesManager.selectedThemeID` drives the active palette, with the default `baldr` theme now presented as the warm walnut, brass, and parchment `Heritage` palette
- `ThemePalette` is the shared chrome layer for appearance, with semantic canvas/surface/border/text roles now derived from each theme's own colors and contrast-aware text colors, and `PirateTheme` resolves dynamically from the selected palette so accents, backgrounds, layout surfaces, onboarding, overlays, custom windows, popovers, and dashboard chrome inherit the active theme
- The entire user-facing app is now unified under the dark warm control-room aesthetic with glowing background overlays, matching the dashboard, and the user-facing Appearance chooser has been removed from Settings
- Major architectural pressure in V2.6: make context collection reliable, async-safe, privacy-aware, and easier to test
- Storage now has a versioned GRDB migration path, URL/title sanitization, and opt-in history retention helpers in support of V2.6
- Dashboard analytics exposes typed async query contracts and generation-checked chart load states for Captain's Log, with month-to-date ranges anchored to the first session in the month and an all-time summary card below the scroll fold
- `MenuBarController` routes Captain's Log into `SettingsWindow`; `SettingsView.swift` embeds `DashboardView.swift` without its standalone sidebar so analytics, profiles, focus apps, and preferences share one window
- The settings sidebar no longer exposes separate Stats/Hourglass or Analytics/Voyage Logs destinations; Captain's Log is the single analytics surface
- `Anchored/App/Views/ControlRoomSurface.swift` now holds the reusable control-room shell/card/footer primitives, and `DashboardView.swift` is the first surface to consume them
- The async context collection pipeline is fully implemented: `AppSwitchMonitor` queries the `ContextCollector` asynchronously off the main thread, executing AppleScript calls via `AppleEventExecutor` with a 750 ms deadline and serial background queuing. Deduplication uses `ContextIdentity` (normalizing titles and URLs) to capture SPA page shifts and same-URL tab changes.
- Focus classification supports optional cloud-based context verification with Bring Your Own Key (BYOK) for Google Gemini, OpenAI, and Anthropic. API keys are stored securely using the macOS Keychain, and requests run asynchronously with a 2.0s deadline and fallback to local classifiers.

## Repo Map

### Product code

- `Anchored/App/`
  - Process entry and app composition.
  - `main.swift` starts `NSApplication`.
  - `AppDelegate.swift` wires the monitor, engine, overlay manager, menu bar, onboarding, and smart nudge pipeline.
- `Anchored/App/Views/`
  - `DashboardView.swift` composes the dashboard shell and cards.
  - `ControlRoomSurface.swift` provides the shared background/card/footer primitives for the new control-room visual language.
- `Anchored/MenuBar/`
  - Status item, popover/menu behavior, settings window, dashboard window, start-session window.
- `Anchored/Engine/`
  - Focus tracking, app/browser context collection, history pipeline, profile logic, nudges, URL matching.
- `Anchored/Models/`
  - Session, event, state, context, dashboard, persistence, profile, and theme value types.
- `Anchored/Storage/`
  - Preferences, focus/distraction lists, GRDB store, history store, migrations, dashboard queries.
- `Anchored/Overlay/`
  - Exit trigger, countdown pill, permission gate, dimming overlays.
- `Anchored/Onboarding/`
  - First-run flow and profile/preferences onboarding UI.
- `Anchored/Audio/`
  - Sound feedback for overlay/session interactions.

### Tests

- `AnchoredTests/Engine/` covers engine state, browser parsing, URL matching, smart-nudge-adjacent logic.
- `AnchoredTests/Storage/` covers SQLite/queries/preferences/list managers.
- `AnchoredTests/Models/` covers value types and event encoding.
- `AnchoredTests/Overlay/` and `AnchoredTests/Audio/` cover UI coordinators and sound behavior.

## Runtime Composition

### Composition root

`Anchored/App/AppDelegate.swift` is the real architecture hub today.

It currently:

1. Checks `hasCompletedOnboarding` in `UserDefaults` and shows onboarding only on first launch or after a reset.
2. On completion, instantiates:
   - `AppSwitchMonitor`
   - `FocusEngine`
   - `OverlayManager`
   - `MenuBarController`
   - `ShadowTrackingEngine`
   - `SmartNudgeManager`
   - `ContextHistoryStore`
   - `ContextHistoryPipeline`
3. Wires `ShadowTrackingEngine` and `SmartNudgeManager` into the live focus runtime; auto-focus tracking is always active, while smart nudges only gate the optional notification.
4. Subscribes to `PreferencesManager.shared` so focus and fog threshold changes mutate the live runtime.
5. Starts the `FocusEngine`, which starts the activity monitor.
6. Keeps the history store disabled until the privacy/settings flow enables collection.

This means runtime composition is still centralized, singleton-heavy, and AppDelegate-driven.

### Composition diagram

```mermaid
graph TD
    A[main.swift] --> B[AppDelegate]
    B --> C[OnboardingWindow]
    B --> D[AppSwitchMonitor]
    B --> E[FocusEngine]
    B --> F[OverlayManager]
    B --> G[MenuBarController]
    B --> H[ShadowTrackingEngine]
    B --> I[SmartNudgeManager]
    B --> J[PreferencesManager.shared]
    B --> K[DistractionListManager.shared]
    B --> L[SessionStore.shared]
    B --> M[ContextHistoryStore]
    B --> N[ContextHistoryPipeline]

    D --> E
    J --> E
    K --> E
    L --> E
    E --> N
    N --> M
    E --> F
    E --> G
    E --> H
    H --> I
```

### Primary runtime flow

```text
NSWorkspace activation / polling
  -> AppSwitchMonitor
  -> FocusEngine.handleContextChange(...)
  -> state/event decisions
  -> SessionStore / NotificationCenter / FocusEngineDelegate
  -> OverlayManager + MenuBarController + ShadowTrackingEngine observers
```

### Secondary runtime flow

```text
PreferencesManager/ProfileManager/list managers
  -> NotificationCenter or Combine updates
  -> FocusEngine/MenuBarController/ShadowTrackingEngine react
```

### Session and enforcement flow

```mermaid
flowchart TD
    A[AppSwitchMonitor emits bundleID/url/title] --> B[FocusEngine.handleContextChange]
    B --> C{Distraction?}
    C -- No, focus --> D[Update lastWorkAppBundleID]
    D --> E{Active session?}
    E -- No --> F[Set workSessionStart and schedule configured focus threshold]
    E -- Yes --> G[Cancel warning or dimming]
    F --> Z{Prompt experiment enabled?}
    Z -- Yes, threshold reached --> K[Request focus confirmation]
    Z -- No --> AA[Auto Voyage tracks the same configured threshold]

    C -- Yes --> H{Active session?}
    H -- No --> I{Focused long enough?}
    I -- No --> J[Reset workSessionStart]
    I -- Yes --> K[Request exit trigger]
    H -- Yes --> L[Log distractionDetected]
    L --> M[Start distraction countdown]
    M --> N{Returned to work in time?}
    N -- Yes --> O[Cancel countdown or dimming]
    N -- No --> P[Set isDimming and log escalationTriggered]

    K --> Q[OverlayManager shows exit trigger]
    Q --> R{Anchor or dismiss?}
    R -- Anchor --> S[FocusEngine.anchorSession]
    R -- Dismiss --> T[Reset workSessionStart]

    S --> U[Log sessionStart]
    U --> V[Run anchored session timer]
    V --> W[FocusEngine.endSession]
    W --> X[Log sessionEnd]
    X --> Y[OverlayManager cleanup]
```

## Core Modules

### Focus tracking and enforcement

#### `Anchored/Engine/FocusEngine.swift`

This is the central behavioral engine.

Responsibilities:

- stores current app, URL, title, and `AppContext`
- tracks `idle`, `watching`, and `anchored` session states
- decides whether a context is focus, distraction, or neutral
- creates `sessionStart`, `distractionDetected`, `escalationTriggered`, and `sessionEnd` events
- drives exit-trigger prompts, distraction countdowns, and dimming state
- posts `focusEngineStateDidChange` and `focusEngineContextDidChange`
- continues to publish legacy `bundleID`/URL/title context updates for downstream consumers during the V2.6 transition

Important inputs:

- `ActivityMonitor` implementation, currently `AppSwitchMonitor`
- `ProfileManager.activeProfile`
- `ProfileManager.activeProfile.allowedApps` as the per-profile positive app set
- `SessionStore`
- `PreferencesManager` updates via `AppDelegate`
- `ShadowTrackingEngine` as the always-on on-device auto-focus companion

Important outputs:

- `FocusEngineDelegate` callbacks to `OverlayManager`
- session events written to storage
- notifications consumed by menu bar and smart nudge systems
- legacy context-change notifications consumed by the history pipeline and existing observers

State invariants:

- `activeSession != nil` implies `state == .anchored`
- `workSessionStart != nil && activeSession == nil` implies `state == .watching`
- distraction countdown and dimming only matter during anchored sessions
- `lastWorkAppBundleID` is the last recognized focus context and is reused for later logging/UI
- `currentContext` still represents the latest raw runtime tuple, while `PersistedContextObservation` stores the sanitized history copy

Files to read for engine changes:

- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Engine/ShadowTrackingEngine.swift`
- `Anchored/Engine/SmartNudgeManager.swift`
- `AnchoredTests/Engine/FocusEngineTests.swift`
- `Anchored/Models/SessionState.swift`
- `Anchored/Models/ActiveSession.swift`
- `Anchored/Models/SessionEvent.swift`

### Context collection

#### `Anchored/Engine/AppSwitchMonitor.swift`

Current role:

- observes `NSWorkspace.didActivateApplicationNotification`
- identifies the frontmost app bundle ID
- triggers asynchronous context queries via `ContextCollector`
- emits `ContextSnapshot` through `onContextChange` when a context shift is detected
- deduplicates incoming context changes using `ContextIdentity`

Current constraints:

- browser polling remains timer-based (2.5 seconds) but is fully asynchronous
- non-browser apps only query native Accessibility context providers
- timer suspending, locking, and system wake operations suspend active collection requests correctly

#### `Anchored/Engine/BrowserStrategies.swift`

Contains:

- `ChromiumBrowserStrategy`
- `SafariBrowserStrategy`
- `FirefoxBrowserStrategy`
- `BrowserStrategyFactory`

Current architectural observations:

- browser context retrieval is asynchronous and non-blocking using `AppleEventExecutor`
- failure returns typed errors mapped to result completions
- Safari fallback Javascript checks remain intact

New helper seams that support the V2.6 provider work:

- `Anchored/Engine/AccessibilityValue.swift`
- `Anchored/Engine/AccessibilityContextProvider.swift`
- `Anchored/Engine/AppleEventExecutor.swift`
- `Anchored/Engine/ContextCollector.swift`
- `Anchored/Engine/ContextHistoryPipeline.swift`
- `Anchored/Storage/ContextHistoryStore.swift`
- `Anchored/Models/PersistedContextObservation.swift`
- `Anchored/Models/DashboardModels.swift`

The V2.6 async context collection pipeline is fully integrated with safe accessibility helpers, serial background queues, and request generation checking.

#### `Anchored/Engine/ContextSanitizer.swift`

Pure sanitizer for persisted titles and HTTP(S) URLs.

Responsibilities:

- collapses whitespace and control noise in persisted titles without lowercasing
- caps persisted titles at 512 grapheme clusters
- strips credentials, query, and fragment from persisted URLs
- rejects unsupported schemes rather than partially sanitizing them

#### `Anchored/Storage/DatabaseMigrations.swift`

Versioned GRDB migration plan used by `SQLiteSessionStore`.

Responsibilities:

- creates the `sessions` schema and indexes when absent
- creates the `context_observations` table and its timestamp index
- sanitizes legacy `sessions.url` values in place
- keeps migration behavior idempotent

### Persistence and analytics

#### `Anchored/Storage/SessionStore.swift`

This is a facade, not the real query layer.

Responsibilities:

- owns migration from legacy `sessions.json`
- forwards writes/reads to `SQLiteSessionStore`
- preserves the convenience `log` API while allowing callers and tests to observe write completion
- computes basic stats via in-memory event reads
- sanitizes persisted session URLs before they reach SQLite

Architectural note:

- the class name suggests the main store, but durable storage is really in `SQLiteSessionStore`
- some analytics live here, some live in `DashboardQueries.swift`

#### `Anchored/Storage/SQLiteSessionStore.swift`

This is the real persistence boundary.

Responsibilities:

- owns the GRDB `DatabaseQueue`
- applies the versioned migration plan from `DatabaseMigrations.swift`
- creates/migrates the `sessions` table and `context_observations` table
- writes session events on a utility queue
- reports async write success or failure through an optional main-queue completion callback
- preserves the original database file on migration failure and records the error in `migrationError`
- exposes raw event reads and recent session reads
- exposes direct helpers for `context_observations` count, oldest date, pruning, clearing, and latest identity lookup

Current schema:

- `sessions`
  - `id`
  - `timestamp`
  - `type`
  - `appBundleID`
  - `appName`
  - `url`
  - `focusDurationSeconds`
  - `sessionDurationSeconds`
  - `distractionAppBundleID`
  - `distraction_domain`
  - `action`
  - `category`
  - `sessionGoal`

SQL ownership invariant from repo guidance:

- keep SQL in `SQLiteSessionStore.swift` or `DashboardQueries.swift`

#### `Anchored/Storage/DashboardQueries.swift`

Analytics/query extension layer on top of `SQLiteSessionStore`.

Responsibilities:

- total focus time
- daily timeline reconstruction
- top distractions
- streak computation
- app name lookup and chart-friendly query helpers
- `DashboardQuerying` async completion-based reads that return typed bucket and distribution models on the main queue
- synchronous tuple/dictionary helpers that remain as wrappers for legacy callers and tests

This file reconstructs user-facing analytics from event streams rather than storing denormalized summaries.

#### `Anchored/Storage/ContextHistoryStore.swift`

Dedicated store facade for privacy-reviewed context observations.

Responsibilities:

- accepts raw context tuples from the live monitor path
- sanitizes and deduplicates consecutive identical observations before persistence
- keeps history writes off the main thread and calls completions back on the main queue
- supports count, oldest-date, prune, and clear operations for privacy/history settings

#### `Anchored/Engine/ContextHistoryPipeline.swift`

Bridge from `FocusEngine` context-change notifications into the history store.

Responsibilities:

- listens for `.focusEngineContextDidChange`
- converts the current focus context into a persisted observation
- maps browser bundle IDs to source labels for history rows
- keeps the history seam off until the store is explicitly enabled

### Preferences and classification inputs

#### `Anchored/Storage/PreferencesManager.swift`

Owns:

- countdown duration
- focus threshold
- launch at login
- smart nudges enablement
- hidden focus-prompt experiment rollout state
- selected settings theme
- AI Visual Productivity Check (`enableImageClassification`)
- SmolVLM 256M VLM model toggle (`useLocalGemma`) and download status (`gemmaDownloadStatus`)
- Cloud AI Productivity Check (`enableCloudClassification`), provider, model, and endpoint settings

Architecture notes:

- `@Published` state is live-wired into the engine from `AppDelegate`
- launch-at-login behavior is abstracted behind `LoginItemService` for tests
- theme selection persists through `UserDefaults` and resolves through `ThemeCatalog`
- a hidden `focusThresholdOverride` defaults key can temporarily shorten the live engine threshold without changing the persisted picker value
- `focusPromptExperimentEnabled` is retained as a legacy rollout preference, but the shipped runtime no longer branches on it

#### `Anchored/Models/AppTheme.swift`

Defines the reusable settings theme catalog.

Responsibilities:

- stores named palettes with primary and secondary gradients
- exposes the active theme lookup by identifier
- keeps palette colors centralized for settings UI styling
- centralizes semantic canvas, surface, border, separator, and text roles for app chrome

`ThemeCatalog` currently supplies the Odin, Thor, Loki, Heimdall, Freyja, Baldr, and Tyr themes.

#### `Anchored/Storage/InstalledAppSuggestionProvider.swift`

Scans installed applications for suggestions used by profile configuration. It owns no global focus-app state; profiles remain the only app allowlist.

Important behavior:

- scans installed applications, categorizes them (Coding, Video, Writing, Distractions), and seeds them dynamically to their respective default profiles on first run or via a one-time migration
- tests special-case `XCTest` so focus behavior defaults differently under test

This special test branch matters when debugging classification behavior.

#### `Anchored/Storage/DistractionListManager.swift`

Owns distraction bundle IDs in `UserDefaults` and can scan installed apps for likely distractions.

#### `Anchored/Engine/ProfileManager.swift`

Owns multiple `WorkProfile` definitions:

- distraction apps
- distraction domains
- allowed apps
- allowed domains

The built-in Coding profile seeds a small allowed-app list for obvious productive tools; the other defaults remain conservative.

Behavioral invariant:

- app-level allow lists override app-level distraction lists
- URL/domain distraction matches still win when a URL is present
- profile switches emit notifications that can immediately change current engine behavior

### UI coordinators

#### `Anchored/Overlay/OverlayManager.swift`

This is the enforcement UI coordinator via `FocusEngineDelegate`.

It shows:

- exit-trigger panel
- distraction countdown pill
- permission gate
- dimming overlays

Important invariant:

- UI enforcement is delegated out of `FocusEngine`; engine owns state, overlay manager owns windows/panels

#### `Anchored/MenuBar/MenuBarController.swift`

Owns:

- status item/menu lifecycle
- settings window entry points, including Captain's Log
- start/end session actions
- current stats display

It depends on:

- `FocusEngine`
- `SessionStore`
- `ProfileManager.shared`

#### `Anchored/App/Views/DashboardView.swift`

Own:

- the Captain's Log analytics surface embedded in settings
- the optional standalone sidebar, range selector, trend chart, distraction list, focus score, month-to-date summary cards, and all-time summary card
- local data loading for focus trends, top distractions, range summaries, and all-time summaries via `MenuBarViewModel`, `DashboardQuerying`, and `SQLiteSessionStore`

They depend on:

- `FocusEngine`
- `MenuBarViewModel`
- `PreferencesManager.shared`
- `SQLiteSessionStore.shared`

#### `Anchored/MenuBar/SettingsView.swift`

Owns the settings split view and the embedded Captain's Log.

Responsibilities:

- routes General, Focus Apps, Captain's Log, About, and profile configuration
- injects the live `FocusEngine` into the Captain's Log analytics view
- applies the warm wood/brass theme colors to settings chrome, cards, and pane backgrounds
- keeps profile configuration in direct language rather than the former Flagship terminology
- uses one Captain's Log destination instead of separate Stats/Hourglass and Analytics/Voyage Logs panes
- keeps Captain's Log inside the settings window rather than opening a separate analytics window

Other appearance surfaces now reuse `PirateTheme` directly:

- `Anchored/MenuBar/MenuBarPopoverView.swift`
- `Anchored/App/StartSessionWindow.swift`
- `Anchored/Onboarding/OnboardingStyles.swift`
- `Anchored/Overlay/PermissionGateView.swift`
- `Anchored/Overlay/ExitTriggerView.swift`
- `Anchored/Overlay/EndSessionButton.swift`
- `Anchored/Overlay/CountdownPillView.swift`
- `Anchored/Overlay/DimOverlayWindow.swift`
- `Anchored/App/Views/TopDistractionsView.swift`
- `Anchored/App/Views/WeeklyHistoryView.swift`
- `Anchored/App/Views/ConstellationHeatmapView.swift`
- `Anchored/App/Views/FleetTreeSpreadmapView.swift`
- `Anchored/App/Views/TidalWaveChartView.swift`
- `Anchored/Overlay/EndSessionButton.swift`
- `Anchored/Overlay/CountdownPillView.swift`
- `Anchored/Overlay/DimOverlayWindow.swift`
- `Anchored/App/Views/TopDistractionsView.swift`
- `Anchored/App/Views/WeeklyHistoryView.swift`
- `Anchored/App/Views/ConstellationHeatmapView.swift`
- `Anchored/App/Views/FleetTreeSpreadmapView.swift`
- `Anchored/App/Views/TidalWaveChartView.swift`

### Shadow tracking and smart nudges

#### `Anchored/Engine/ShadowTrackingEngine.swift`

Tracks continuous focus-context time outside anchored sessions and pauses for sleep/non-focus states.

Its threshold initializes from `PreferencesManager.effectiveFocusThreshold`; it no longer owns a hard-coded five-minute runtime threshold.

#### `Anchored/Engine/SmartNudgeManager.swift`

Auto-anchors a session after the onboarding-selected shadow threshold and sends a local notification only when smart nudges are enabled.

Architectural note:

- this path currently calls `focusEngine.anchorSession(...)` directly
- the manager also reaches into `ProfileManager.shared`

## Notifications And Cross-Module Coupling

Current cross-cutting notifications:

- `focusEngineStateDidChange`
- `focusEngineContextDidChange`
- `activeProfileDidChange`
- `profilesDidChange`
- `focusListDidChange`
- `distractionListDidChange`

Current coupling style:

- AppDelegate composition
- singleton managers
- NotificationCenter fan-out
- direct delegate for overlay enforcement
- direct `Timer` usage in engine/monitor/nudge flows

This is functional but makes deterministic testing and async context collection harder than necessary. V2.6 addresses part of that.

## High-Value Invariants

These come from both the code and repo rules. Future changes should preserve them unless a plan explicitly replaces them.

- `FocusEngine` state transitions are architectural invariants.
- Auto-focus and shadow tracking should stay on device; `ShadowTrackingEngine` can notify, but it should not be the enforcement source of truth.
- Browser support should be registered through `BrowserStrategyFactory`.
- SQL belongs in `SQLiteSessionStore.swift` or `DashboardQueries.swift`.
- `PersistedContextObservation` and `SessionEvent.persistedCopy()` sanitize URLs before persistence.
- The history pipeline must remain opt-in and disabled until the privacy/settings flow enables it.
- AppKit/UI mutations should stay on the main thread.
- Persistence work should stay off the main thread.
- Sensitive titles and URLs should stay local and should not be raw-logged casually.
- Accessibility permission loss must degrade gracefully rather than crash or silently corrupt state.
- Profile-level `allowedApps` and allowed domains are positive focus signals, while explicit distraction domains and entertainment browser contexts suppress focus tracking.
- Fog/dimming uses `distractionCountdownThreshold`; focus prompting or Auto Voyage uses `focusThreshold`. These timings must not be conflated.

## Current Weak Spots

These are the places future agents are most likely to touch when implementing V2.6 or debugging regressions.

- `FocusEngine` owns significant timer/state logic and keeps the focus/distraction policy in-engine, but it now depends on a small injected focus-app provider seam.
- `SessionStore` and `SQLiteSessionStore` split responsibilities in a way that is not obvious from the names.
- `AppDelegate` is the de facto dependency injection container.
- The standalone `DashboardWindow.swift` still compiles for compatibility but is no longer opened by `MenuBarController`.
- `PreferencesManager.focusPromptExperimentEnabled` is now a legacy rollout preference rather than a live runtime branch.

## V2.6 Impact Surface

Read this section before implementing anything from `docs/ideas/anchored-v2.6-plan.md`.

### Planned architectural additions

The V2.6 core async context pipeline and local history have been fully implemented, including:

- `ContextSnapshot`
- `ContextIdentity`
- `ContextCollector`
- async Apple Event execution (`AppleEventExecutor`)
- safe Accessibility context providers
- generation-based stale-result rejection
- sanitized context persistence
- retention/deletion controls
- privacy settings UI
- asynchronous analytics contracts
- `ContextHistoryStore` and `ContextHistoryPipeline`
- `PersistedContextObservation`
- `DashboardModels`
- async dashboard query completions and generation-checked chart views
- a settings-contained Captain's Log that reuses the async dashboard surface
- `CloudClassifier` and `KeychainHelper` for secure Bring Your Own Key (BYOK) cloud AI context classification

### ML readiness and rollout

`docs/ideas/anchored-ml-engine-plan.md` is the focused execution plan for the future on-device classifier. It requires:

- completing the `ContextSnapshot` runtime path before CoreML integration
- keeping classification behind a `ContextClassifying` protocol and outside `FocusEngine`
- preserving explicit profile rules over ML output
- validating the model in shadow mode before predictions can affect enforcement
- using neutral fallback for low-confidence, stale, timed-out, or failed predictions

### Files most likely to change

- `Anchored/Engine/AppSwitchMonitor.swift`
- `Anchored/Engine/BrowserStrategies.swift`
- `Anchored/Engine/AccessibilityValue.swift`
- `Anchored/Engine/AccessibilityContextProvider.swift`
- `Anchored/Engine/ContextSanitizer.swift`
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Storage/InstalledAppSuggestionProvider.swift`
- `Anchored/Models/AppTheme.swift`
- `Anchored/Models/DashboardModels.swift`
- `Anchored/Models/` for new context types
- `Anchored/Storage/SQLiteSessionStore.swift`
- `Anchored/Storage/ContextHistoryStore.swift`
- `Anchored/Storage/DatabaseMigrations.swift`
- `Anchored/Storage/DashboardQueries.swift`
- `Anchored/App/Views/TidalWaveChartView.swift`
- `Anchored/App/Views/ConstellationHeatmapView.swift`
- `Anchored/App/Views/FleetTreeSpreadmapView.swift`
- `Anchored/App/Views/TopDistractionsView.swift`
- `Anchored/App/Views/WeeklyHistoryView.swift`
- `Anchored/App/Views/ControlRoomSurface.swift`
- `Anchored/MenuBar/SettingsView.swift`
- `Anchored/MenuBar/MenuBarPopoverView.swift`
- `Anchored/App/StartSessionWindow.swift`
- `Anchored/Onboarding/OnboardingStyles.swift`
- `Anchored/Overlay/PermissionGateView.swift`
- `Anchored/Overlay/ExitTriggerView.swift`
- `Anchored/Overlay/EndSessionButton.swift`
- `Anchored/Overlay/CountdownPillView.swift`
- `Anchored/Overlay/DimOverlayWindow.swift`
- `AnchoredTests/Engine/`
- `AnchoredTests/Storage/`

### Expected seam changes

- context collection is handled via `ContextCollector` (asynchronous pipeline using serial background queues).
- `AppSwitchMonitor` publishes deduplicated `ContextSnapshot` values rather than raw tuples.
- `ContextHistoryPipeline` records `ContextSnapshot` details into sanitized context observations.
- Unit tests are isolated, deterministic, and avoid arbitrary sleeps.

## Where To Start By Task Type

### If you are changing focus/session behavior

Read:

- `docs/architecture/anchored-architecture.md`
- `Anchored/Engine/FocusEngine.swift`
- `Anchored/Storage/InstalledAppSuggestionProvider.swift`
- `AnchoredTests/Engine/FocusEngineTests.swift`
- `Anchored/Overlay/OverlayManager.swift`

### If you are changing browser or app context collection

Read:

- `docs/architecture/anchored-architecture.md`
- `docs/ideas/anchored-v2.6-plan.md`
- `Anchored/Engine/AppSwitchMonitor.swift`
- `Anchored/Engine/BrowserStrategies.swift`
- `Anchored/Engine/AccessibilityValue.swift`
- `Anchored/Engine/AccessibilityContextProvider.swift`
- `AnchoredTests/Engine/BrowserStrategiesTests.swift`

### If you are changing persistence or analytics

Read:

- `docs/architecture/anchored-architecture.md`
- `Anchored/Storage/SessionStore.swift`
- `Anchored/Storage/SQLiteSessionStore.swift`
- `Anchored/Storage/DatabaseMigrations.swift`
- `Anchored/Storage/ContextHistoryStore.swift`
- `Anchored/Engine/ContextSanitizer.swift`
- `Anchored/Models/PersistedContextObservation.swift`
- `Anchored/Models/DashboardModels.swift`
- `Anchored/Storage/DashboardQueries.swift`
- `Anchored/App/Views/TidalWaveChartView.swift`
- `Anchored/App/Views/ConstellationHeatmapView.swift`
- `Anchored/App/Views/FleetTreeSpreadmapView.swift`
- `AnchoredTests/Storage/`

### If you are changing settings, profiles, or list behavior

Read:

- `docs/architecture/anchored-architecture.md`
- `Anchored/Models/WorkProfile.swift`
- `Anchored/Storage/PreferencesManager.swift`
- `Anchored/Storage/InstalledAppSuggestionProvider.swift`
- `Anchored/Storage/DistractionListManager.swift`
- `Anchored/Engine/ProfileManager.swift`

### If you are changing Captain's Log or analytics chrome

Read:

- `docs/architecture/anchored-architecture.md`
- `Anchored/MenuBar/MenuBarController.swift`
- `Anchored/MenuBar/SettingsView.swift`
- `Anchored/MenuBar/SettingsWindow.swift`
- `Anchored/App/Views/ControlRoomSurface.swift`
- `Anchored/App/Views/DashboardView.swift`
- `Anchored/MenuBar/MenuBarViewModel.swift`
- `Anchored/Storage/SessionStore.swift`
- `Anchored/Storage/SQLiteSessionStore.swift`
- `Anchored/Storage/DashboardQueries.swift`

### If you are changing appearance or theme chrome

Read:

- `docs/architecture/anchored-architecture.md`
- `Anchored/Models/AppTheme.swift`
- `Anchored/Storage/PreferencesManager.swift`
- `Anchored/MenuBar/SettingsView.swift`
- `Anchored/MenuBar/SettingsWindow.swift`
- `Anchored/MenuBar/MenuBarPopoverView.swift`
- `Anchored/App/StartSessionWindow.swift`
- `Anchored/Onboarding/OnboardingStyles.swift`
- `Anchored/Onboarding/OnboardingWindow.swift`
- `Anchored/Overlay/PermissionGateView.swift`
- `Anchored/Overlay/ExitTriggerView.swift`

### If you are changing onboarding, menu bar, or overlays

Read:

- `docs/architecture/anchored-architecture.md`
- `Anchored/App/AppDelegate.swift`
- `Anchored/MenuBar/`
- `Anchored/Onboarding/`
- `Anchored/Overlay/`

## Maintenance Rules For This Doc

Update this doc whenever a major update changes any of the following:

- composition root or dependency wiring
- engine state model or event flow
- context collection architecture
- persistence schema or ownership
- privacy/permission handling
- analytics query boundaries
- major new modules or renamed files
- plan assumptions for V2.6

When updating it:

- describe shipped reality, not intended future state
- keep the “Current State Snapshot” accurate
- update “V2.6 Impact Surface” when plan assumptions change
- add file paths for new architectural seams
- remove stale guidance instead of only appending



================================================================================
FILE: docs/decisions/anchored-v2.6-apple-event-executor.md
================================================================================

# Architectural Decision Record: Non-Blocking AppleScript Executor

## Context and Problem Statement
Anchored tracks browser active tabs (URL and titles) by periodically running AppleScript payloads targetting Safari and Chromium-based browsers (such as Chrome, Arc, Edge, and Brave). 

Historically, these AppleScripts were compiled and executed synchronously on the AppKit main (UI) thread. This introduced significant user experience regressions:
1. **UI Blocking / Lags:** When a browser is busy, loading a heavy page, or suspended, AppleScript execution blocks synchronously. This causes the menu-bar app to hang, showing a beachball/spinning pinwheel.
2. **Lack of Timeout Control:** Synchronous `NSAppleScript` execution has no short-deadline timeout, taking up to 60 seconds (default Apple Event timeout) to fail if the target app is frozen.
3. **No Cancellation:** If the user switches applications or tabs during a long-running script, the synchronous execution cannot be cancelled, leading to stale data overwriting newer active context updates.

We need a reliable, non-blocking asynchronous executor that:
* Keeps all AppleScript compilation and execution off the main thread.
* Enforces a strict execution deadline (750 ms limit).
* Discards results of cancelled or timed-out executions.

## Validation and Research Findings

### Thread Safety of `NSAppleScript`
* **Compilation and Execution:** `NSAppleScript` is thread-safe for compilation and execution, provided that a single instance is not concurrently executed across multiple threads. By routing all execution through a dedicated serial `DispatchQueue`, we guarantee that AppleScript compilation and execution happen sequentially and in isolation.
* **Main Thread Independence:** Compilation of scripts via `NSAppleScript(source:)` and execution via `executeAndReturnError(_:)` run correctly on background threads without requiring an active Cocoa RunLoop or AppKit main thread access.
* **Apple Event Dispatching:** Apple Events generated by `NSAppleScript` are dispatched asynchronously at the OS level by the Apple Event Manager. The background queue thread blocks while waiting for the target application to return the event response, leaving the AppKit main thread completely responsive.

### Timeout and Cancellation Design
* **Sub-second Deadlines:** The standard AppleScript `with timeout` block is limited to integer-second granularity (minimum 1 second). To enforce a 750 ms deadline, we must handle the timeout at the Swift dispatch level.
* **Thread Interruption Limitations:** In macOS/Swift, a thread blocked inside the system call `NSAppleScript.executeAndReturnError` cannot be forcefully interrupted or terminated safely.
* **Mitigation (Discarding Late Results):**
  1. We wrap the completion handler with thread-safe lock protection (`NSLock`), ensuring it executes exactly once.
  2. We schedule a timeout block on a global background queue using `DispatchQueue.main.asyncAfter` or `DispatchQueue.global().asyncAfter`.
  3. If the timeout fires first, the handler returns a `.failure(.timedOut)` result, and any subsequent execution completion is safely ignored.
  4. If the execution finishes before the deadline, we cancel the timeout task and return `.success(String)`.

## Decision
We will implement `AppleEventExecutor` conforming to `AppleEventExecuting` which uses a private serial background `DispatchQueue` for compiling and executing AppleScripts. 

A timeout mechanism using thread-safe state wrappers guarantees a strict 750 ms response time for the caller.

### Expected Class Interface
```swift
public enum ExecutorError: Error, Equatable {
    case timedOut
    case execFailed(String)
}

public protocol AppleEventExecuting: AnyObject {
    func execute(
        _ scriptSource: String,
        timeout: TimeInterval,
        completion: @escaping (Result<String, ExecutorError>) -> Void
    )
}
```



================================================================================
P0 FIXES APPLIED IN THIS MEGAFILE BUILD
================================================================================


1. FocusEngine.swift:
   - Removed DispatchSemaphore blocking (isDistraction + isFocusContext)
   - New triggerAsyncCloudClassification(): utility queue, OCR only off-main, fire-and-forget log, immediate return local logic
   - Methods now: smartWeb, domain match, browser entertainment, SmartApp, SmartImage, isFocusApp

2. CloudClassifier.swift:
   - Gemini: was `...:generateContent?key=APIKEY` in URL -> now `...:generateContent` with header x-goog-api-key
   - Prevents key leakage in URL logs/proxies
   - Custom endpoint still Bearer

3. KeychainHelper.swift:
   - Removed NSClassFromString XCTest detection
   - Added useMockOnly Bool explicit flag, mockKeys overlay
   - Production path always Security framework unless useMockOnly
   - Tests updated to set useMockOnly=true

4. AppSwitchMonitor.swift:
   - Timer 0.5s -> 2.5s (spec)
   - Added sleepObserver (screensDidSleep/Wake), session lock (sessionDidResignActive/BecomeActive)
   - isSuspendedForSleep + isSuspendedForLock flags
   - permissionDenied stops privileged polling
   - cancel/start lifecycle correctly

5. Consolidated Plan:
   - New docs/ideas/anchored-consolidated-plan.md merges V1,V2,V2.5,V2.6 async, cloud BYOK, dashboard refresh, ML engine, V3 into single executable graph
   - 36 tasks, 8 phases, dependency mermaid, risk table

6. External Archive:
   - All ideas moved to /tmp/anchored-plans-external + compressed to anchored-plans.tar.gz + .zip
   - Copies in repo root for convenient retrieval
   - External dir retained at /tmp/anchored-plans-external

Build verification:
- xcodegen generate (project.yml sources recursive so new files picked)
- Fixes compile under Swift 5.7 macOS13
- Tests: KeychainHelperTests and CloudClassifierTests patched for new transport

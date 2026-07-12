# ⚓ Gemini Agent Instructions (GEMINI.md)

This file guides Gemini models and agents on coding conventions, database schemas, and tool usage specific to the Anchored codebase.

---

## 🧭 Codebase Context Heuristics

### Central State Machine
The core workflow is governed by the [FocusEngine](file:///Users/varun/Development/Anchor/Anchored/Engine/FocusEngine.swift). When modifying focus logic:
1. Context switches are registered via `ActivityMonitor.onContextChange`.
2. Browser tracking relies on [AppSwitchMonitor](file:///Users/varun/Development/Anchor/Anchored/Engine/AppSwitchMonitor.swift) running a 2.5-second polling timer if the active application is a supported browser and Accessibility permission is active (`AXIsProcessTrusted()`).
3. If accessibility is not active, URL fetching is bypassed and the browser is treated as a neutral app.

### Database Interaction (GRDB & SQLite)
Events are logged in `anchored.db`. All session event logging uses asynchronous insertion, but reading uses synchronous reads on a serial queue.
* **Events Schema:**
  * Table: `sessions`
  * Keys: `id`, `timestamp`, `type` (session_start | session_end | distraction_detected | escalation_triggered), `appBundleID`, `appName`, `url`, `focusDurationSeconds`, `sessionDurationSeconds`, `distractionAppBundleID`, `distraction_domain`, `action` (anchored | dismissed | timeout | escalated | returned), `category`, `sessionGoal`.
* **Important:** Do not add raw SQLite queries outside [SQLiteSessionStore.swift](file:///Users/varun/Development/Anchor/Anchored/Storage/SQLiteSessionStore.swift) or [DashboardQueries.swift](file:///Users/varun/Development/Anchor/Anchored/Storage/DashboardQueries.swift).

---

## 🛶 Interaction & Styling Guidelines

### SwiftUI Design System
Maintain the bespoke dark visual style. Always wrap layouts using:
* Clear, borderless `NSPanel` structures with `alphaValue` transition animations.
* Smooth gradients and drop shadows to ensure readable overlays during dimming states.
* Thin Material backgrounds (`.ultraThinMaterial`) and custom gold borders (`goldColor.opacity(...)`).

### Browser Strategy Support
If adding or modifying browser URL strategies:
* Chromium browsers (Chrome, Arc, Edge, Brave) require `ChromiumBrowserStrategy` using AppleScript.
* Safari requires `SafariBrowserStrategy` validating JavaScript Apple Events.
* Firefox requires `FirefoxBrowserStrategy` traversing the accessibility hierarchy (`AXUIElement`) starting from the active window down to `AXToolbar` and `AXTextField`.
* Ensure new browsers are registered in `BrowserStrategyFactory` in [BrowserStrategies.swift](file:///Users/varun/Development/Anchor/Anchored/Engine/BrowserStrategies.swift).

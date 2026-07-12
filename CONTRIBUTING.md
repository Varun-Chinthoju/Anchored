# Contributing to Anchored

Thanks for contributing to Anchored. This guide covers the project workflow, testing expectations, and architectural conventions.

Please review these guidelines before making changes.

---

## 📜 Code of Conduct

All contributors are expected to follow our [Code of Conduct](file:///Users/varun/Development/Anchor/CODE_OF_CONDUCT.md). Please report any unacceptable behavior to **varun.chinthoju@gmail.com**.

---

## 🛠️ Environment Setup

Anchored does not store its Xcode project file in Git to prevent nasty merge conflicts. Instead, we use **XcodeGen** to generate it on the fly.

### Prerequisites
* macOS 13.0 or later
* Xcode 14.0 or later (Swift 5.7+)
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Local Setup Steps
1. **Fork and Clone:**
   ```bash
   git clone https://github.com/YOUR-USERNAME/Anchor.git
   cd Anchor
   ```
2. **Generate the Project:**
   ```bash
   xcodegen generate
   ```
   This reads `project.yml` and creates `Anchored.xcodeproj`.
3. **Open and Run:**
   * Open `Anchored.xcodeproj` in Xcode.
   * Choose the `Anchored` scheme and hit `Cmd + R` to build and run the app.

---

## 📐 Coding & Architectural Guidelines

Please follow these core architectural rules:

### 1. SwiftUI Design & Aesthetic Style
Anchored features a bespoke, rich dark user interface. When building UI components:
* **Backgrounds & Overlays:** Use `.ultraThinMaterial` and thin translucent panels.
* **Borders:** Frame panels and cards with gold borders (`goldColor.opacity(...)`).
* **Transitions:** Use borderless `NSPanel` structures with custom `alphaValue` transition animations for overlays.
* **Friction overlays:** Dimming overlays should use smooth gradients and drop shadows to ensure readability.

### 2. FocusEngine State Machine
The core focus tracking state machine is located in [FocusEngine](file:///Users/varun/Development/Anchor/Anchored/Engine/FocusEngine.swift). All state transitions must follow a strict flow:
* **Idle** ➜ **Watching** (when a Whitelisted App/URL is active).
* **Watching** ➜ **Prompting** (when switching to a Distraction/Neutral app for too long).
* **Prompting** ➜ **Anchored** (when the user starts a session) or **Idle** (dismiss/timeout).
* **Anchored** ➜ **Warning** (on distraction app switch, starts 10s countdown).
* **Warning** ➜ **Dimmed** (countdown expiry, up to 50% opacity screen dimming).
* **Dimmed** ➜ **Anchored** (return to work app/URL).

### 3. The Permission Gate
To ensure zero upfront friction:
* Browser URL monitoring remains locked until the database registers **10 or more** `sessionEnd` events.
* After 10 completed sessions, the `FocusEngine` triggers a spring-animated `PermissionGatePanel` prompting the user for Accessibility permissions.
* Once Accessibility is granted (`AXIsProcessTrusted() == true`), the polling timer starts automatically whenever a browser is in the foreground.

### 4. Database Interactions (GRDB & SQLite)
* All focus sessions and events are persisted in `anchored.db`.
* **Writing:** Perform all database writes/insertions asynchronously on a background thread.
* **Reading:** Use synchronous reads on a serial queue to prevent concurrency anomalies.
* **Important:** Do NOT write raw SQLite queries outside [SQLiteSessionStore.swift](file:///Users/varun/Development/Anchor/Anchored/Storage/SQLiteSessionStore.swift) or [DashboardQueries.swift](file:///Users/varun/Development/Anchor/Anchored/Storage/DashboardQueries.swift).

### 5. Browser Strategies
If you are adding or modifying tracking behavior for web browsers:
* **Chromium (Chrome, Arc, Edge, Brave, Orion):** Use AppleScript via `ChromiumBrowserStrategy` to query active tab URLs.
* **Safari:** Use AppleScript via `SafariBrowserStrategy` (make sure "Allow JavaScript from Apple Events" is enabled in Safari's Develop settings).
* **Firefox:** Query the macOS Accessibility API (`AXUIElement`) by traversing the window tree down to `AXToolbar` and locating `AXTextField` to parse the URL address.
* Register all strategies in `BrowserStrategyFactory` inside [BrowserStrategies.swift](file:///Users/varun/Development/Anchor/Anchored/Engine/BrowserStrategies.swift).

---

## 🧪 Testing Your Code

Do not send a pull request with broken or untested code!

### In Xcode
1. Select the `AnchoredTests` scheme.
2. Press `Cmd + U` to run the suite.

### Via Command Line (CI equivalent)
```bash
xcodegen generate
xcodebuild test \
  -project Anchored.xcodeproj \
  -scheme AnchoredTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

---

## 🚀 Creating a Pull Request

Ready to merge your changes?

1. **Create a Feature Branch:**
   ```bash
   git checkout -b feature/your-awesome-feature
   ```
2. **Commit with Clarity:** Keep commit messages concise, descriptive, and imperative (e.g. `Add Orion browser support to factory`).
3. **Generate Xcode Project:** Make sure your `project.yml` is updated if you added/removed source files, and verify `xcodegen generate` runs successfully.
4. **Push & PR:** Push to your fork and submit a Pull Request to our default branch.
5. **Fill Out the Template:** Complete the pull request template, including testing steps.

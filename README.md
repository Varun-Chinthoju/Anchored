# ⚓ Ahoy, Anchored!

Anchored is a zero-ritual, context-aware macOS focus utility for scallywags. Unlike traditional focus blockers that demand upfront commitments or invasive permission handshakes, Anchored passive-actively guards yer flow. It detects when ye step away from yer work, prompts ye to protect yer momentum (Ghost Mode), and escalates using gentle ambient friction if ye stray.

## License

Anchored is licensed under PolyForm Noncommercial 1.0.0. You may contribute and
use it for noncommercial purposes, but commercial sale or use is not allowed.
See [LICENSE](LICENSE) for the full terms.

---

## 💡 The Captain's Code

* **Focus Without the Ritual:** No timers to start, matey. Anchored watches yer workflow passively in the background. The prompt triggers at the *exit*, validating the work ye've already completed.
* **Earned Trust:** The app boots with zero configuration and zero special permissions. After ye complete 10 successful sessions, it presents the "Permission Gate" to request Accessibility permission, unlocking URL-level awareness inside browsers.
* **Ambient Friction, Not Walls:** Traditional blockers provoke immediate override impulses. Anchored uses custom floating UI capsules and a gradual screen-dimming overlay—friction ye can work through if ye must, but clear visual teeth to nudge ye back to yer duties.

---

## 🚀 Booty & Features

### 👤 Ghost Mode (V1)
* **Zero-Permission Detection:** Uses passive `NSWorkspace` notifications to track app activation.
* **Exit Triggers:** Automatically detects when ye switch from a work app (e.g., Xcode, VS Code) to a distraction app (e.g., Discord, Slack) after a configurable duration threshold.
* **Ambient Escalation:** If ye stray during an active session, a countdown pill warns ye before the screen slowly dims (up to 50% opacity). The overlay is fully click-through, lifting immediately when ye return to work.

### 🌐 Context-Aware Browser Monitoring (V2)
* **Permission Gate:** A spring-animated `NSPanel` prompt presented after 10 sessions to request Accessibility permission.
* **Multi-Browser Support:** URL-level tracking for Chromium-based browsers (Chrome, Arc, Edge, Brave, Orion) and Safari via AppleScript, and Firefox via the Accessibility API.
* **Subdomain-Aware Resolution:** Intelligently maps URLs against work profiles so browser windows are evaluated based on their active tabs rather than treated as uniformly neutral.

### 📂 Work Profiles
* Pre-configured sets (Coding, Writing, Video Creation, Custom) grouping distraction apps, distraction domains, and allowed domains.
* Quick-switch interface directly from the macOS menu bar or Preferences pane.

### 📊 Focus Dashboard & Smart Nudges
* **Rich Analytics:** Beautiful timeline view of yer day, streak tracker, weekly session count, and breakdown of yer top distractions.
* **SQLite Storage:** Session events are migrated from flat JSON to SQLite (powered by GRDB.swift) for high-performance date-filtering and timeline query aggregates.
* **Shadow Tracking & Smart Nudges:** Opt-in background category tracking that suggests dropping the anchor if it detects sustained work (e.g., 5+ minutes in Xcode).

---

## 🛠️ Ship's Map & Structure

The project is organized cleanly by domain responsibility:

```
Anchored/
├── App/                # App delegate, lifecycle, and app-level initialization
├── Audio/              # Sound effects (success chimes, tactile button clicks)
├── Engine/             # Core engines: FocusEngine, ActivityMonitor, ShadowTracking, BrowserStrategies
│   ├── ActivityMonitor.swift
│   ├── AppSwitchMonitor.swift
│   ├── BrowserStrategies.swift
│   ├── FocusEngine.swift
│   ├── FocusEngineDelegate.swift
│   ├── ProfileManager.swift
│   ├── ShadowTrackingEngine.swift
│   ├── SmartNudgeManager.swift
│   └── URLMatcher.swift
├── MenuBar/            # macOS Menu bar icon, status item dropdowns, and context menu actions
├── Models/             # Application data models (Session, Event, ActivityState)
├── Onboarding/         # Flow-based educational onboarding interface
├── Overlay/            # Core escalation views (NSPanel, Dimming overlay window)
├── Storage/            # Persistence layers (SQLiteSessionStore, PreferencesManager, ProfileManager)
│   ├── DashboardQueries.swift
│   ├── DistractionListManager.swift
│   ├── FocusListManager.swift
│   ├── PreferencesManager.swift
│   ├── SQLiteSessionStore.swift
│   └── SessionStore.swift
└── Resources/          # Asset catalogs, icons, and plist configs
```

---

## 📐 Architecture & Decision Logic

### FocusEngine Decision Tree
When an application activation or URL change event occurs, the `FocusEngine` routes the state based on the active profile's configuration:

```
                  [ Incoming Event (App Activation or URL Change) ]
                                         │
                                         ▼
                        Is App in Distraction List?
                                ├── Yes ──► [ Trigger countdown pill -> Dim overlay ]
                                └── No
                                         │
                                         ▼
                            Is App a Supported Browser?
                                ├── No ───► [ Treat as Work / Neutral ]
                                └── Yes
                                         │
                                         ▼
                               Is Accessibility Granted?
                                ├── No ───► [ Treat Browser as Neutral ]
                                └── Yes
                                         │
                                         ▼
                                   Fetch Tab URL
                                         │
                                         ▼
                              Check Domain in Profile
                                ├── Distraction Domain ──► [ Trigger countdown pill ]
                                ├── Allowed Domain ──────► [ Treat as Work (Lift Dim) ]
                                └── Unlisted Domain ─────► [ Treat as Neutral ]
```

### Browser URL Retrieval Strategies

Different browser engines require different retrieval strategies to minimize CPU utilization and energy impact:

1. **Chromium Engine (Chrome, Arc, Edge, Brave, Orion):**
   Uses `NSAppleScript` executing:
   ```applescript
   tell application "Google Chrome"
       get URL of active tab of front window
   end tell
   ```
2. **Safari Engine:**
   Uses `NSAppleScript` executing:
   ```applescript
   tell application "Safari"
       get URL of current tab of front window
   end tell
   ```
3. **Firefox Engine:**
   Uses macOS Accessibility API (`AXUIElement`) to traverse the application's UI tree:
   * Locates the active window and navigates down to `AXToolbar`.
   * Queries for the address bar (`AXTextField`) containing a URL-like value.
   * Extracts the `AXValue` attribute dynamically.

---

## 🗄️ Database Schema

The persistence layer uses a local SQLite database located at `~/Library/Application Support/Anchored/anchored.db`. The table schema is defined as follows:

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,           -- ISO-8601 string
    type TEXT NOT NULL,                -- session_start | session_end | distraction_detected | escalation_triggered
    app_bundle_id TEXT NOT NULL,
    app_name TEXT NOT NULL,
    url TEXT,                          -- Populated for V2 browser events
    focus_duration_seconds INTEGER,
    session_duration_seconds INTEGER,
    distraction_app_bundle_id TEXT,
    distraction_domain TEXT,           -- Extracted from url for fast queries
    action TEXT                        -- anchored | dismissed | timeout | escalated | returned
);

CREATE INDEX idx_sessions_timestamp ON sessions(timestamp);
CREATE INDEX idx_sessions_type ON sessions(type);
CREATE INDEX idx_sessions_date ON sessions(date(timestamp));
```

During upgrade from V1 to V2, the app automatically reads the legacy JSON format from `~/Library/Application Support/Anchored/sessions.json` and imports it into the SQLite schema, keeping a backup file named `sessions.json.migrated`.

---

## ⚙️ Work Profile Configurations

Profiles map yer environment context dynamically. Each profile consists of three parts:

| Profile | Distraction Apps | Distraction Domains | Allowed Domains |
| :--- | :--- | :--- | :--- |
| **💻 Coding** | Discord, Slack, Messages, Steam, Spotify, Music | youtube.com, twitter.com, x.com, reddit.com, instagram.com, tiktok.com, facebook.com | github.com, stackoverflow.com, developer.apple.com, docs.python.org, npmjs.com |
| **🎬 Video Creation** | Discord, Messages, Telegram, Steam, Slack | twitter.com, x.com, reddit.com, instagram.com, tiktok.com | youtube.com (creator exception), studio.youtube.com, frame.io, vimeo.com |
| **✍️ Writing & Research** | Discord, Slack, Messages, Steam, Spotify, Music | youtube.com, twitter.com, x.com, reddit.com, instagram.com | docs.google.com, wikipedia.org, scholar.google.com, notion.so |
| **⚙️ Custom** | *Configured by user* | *Configured by user* | *Configured by user* |

---

## 🏁 Getting Started

### Prerequisites
* macOS 13.0 or later
* Xcode 14.0 or later
* Swift 5.7+
* [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Installation & Build

1. **Clone the repository:**
   ```bash
   git clone https://github.com/varun/Anchor.git
   cd Anchor
   ```

2. **Generate the Xcode Project:**
   Anchored uses `XcodeGen` to manage its project structure. Run the following to generate `Anchored.xcodeproj`:
   ```bash
   xcodegen generate
   ```

3. **Open and Run:**
   - Open `Anchored.xcodeproj` in Xcode.
   - Choose the `Anchored` scheme.
   - Build and run (`Cmd + R`).

---

## 🧪 Testing

To run the unit test suite:
* Select the `AnchoredTests` target.
* Run tests (`Cmd + U`) to verify:
  * Focus logic state machine rules
  * Profile configurations mapping
  * SQLite DB migrations
  * Subdomain and URL resolving heuristics

---

## ❓ Troubleshooting & FAQ

#### Q: Why isn't Safari tracking my active tab URLs?
Safari security policy requires ye to authorize external automation. Go to **Safari** ➜ **Develop** menu and check **"Allow JavaScript from Apple Events"**. If the Develop menu is hidden, enable it in **Safari** ➜ **Settings** ➜ **Advanced** ➜ **"Show features for web developers"**.

#### Q: How heavy is the background resource polling?
To ensure minimal battery impact, the `BrowserURLMonitor` only runs its 2.5-second polling timer when a supported web browser holds the OS focus window. The moment ye switch back to Xcode, VS Code, or any other app, the polling timer halts completely.

#### Q: Does my browser data leave my computer?
No. All URL extraction, domain matching, and session storage operations are executed locally. The app contains no telemetric analytics trackers or external synchronization services.

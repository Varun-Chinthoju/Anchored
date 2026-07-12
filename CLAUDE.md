# ⚓ Developer Guide (CLAUDE.md)

This file contains build, test, and run instructions, along with coding style guidelines for Anchored.

---

## 🛠️ Build & Development Commands

### Project Generation
Anchored uses `XcodeGen` to manage project target files dynamically. If you add, delete, or rename files, you must regenerate the project:
```bash
xcodegen generate
```

### Building the Application
To build the application in Release mode (including compiling GRDB and Swift dependencies):
```bash
xcodebuild -project Anchored.xcodeproj -scheme Anchored -configuration Release -derivedDataPath build/DerivedData
```

### Running Unit Tests
To run the full suite of unit tests:
```bash
xcodebuild -project Anchored.xcodeproj -scheme AnchoredTests -destination 'platform=macOS' test
```

### Deploying & Launching
To deploy the application to your `/Applications` directory and launch it:
```bash
# Terminate existing instance
killall Anchored || true

# Copy and open
rm -rf /Applications/Anchored.app
cp -R build/DerivedData/Build/Products/Release/Anchored.app /Applications/
open /Applications/Anchored.app
```

---

## 🎨 Coding Style & Guidelines

### Swift Style Rules
* **Formatting:** Use 4 spaces for indentation. Follow the official Apple Swift API Design Guidelines.
* **Naming Conventions:**
  * Types (classes, structs, enums, protocols) must use `PascalCase`.
  * Variables, methods, and parameters must use `camelCase`.
  * Constants or static configurations should use `camelCase`.
* **State Management:** Align state changes via Swift `Combine` properties (`@Published`) or standard macOS notifications.
* **Database Queries:** All database interactions must flow through [SessionStore](file:///Users/varun/Development/Anchor/Anchored/Storage/SessionStore.swift), using safe, parameterized queries powered by GRDB.swift.

### UI & Architecture
* **Interface:** Custom overlays (Capsules, Pills) must be built using **SwiftUI** wrapped in custom, borderless AppKit `NSPanel` subclasses.
* **Aesthetics:** Follow the core dark visual design tokens:
  * Gold: `Color(red: 0.9, green: 0.75, blue: 0.3)`
  * Parchment White: `Color(red: 0.95, green: 0.95, blue: 0.9)`
  * Dark Wood: `Color(red: 0.12, green: 0.09, blue: 0.07)`
* **Browser Monitoring:** Leverage the [BrowserStrategy](file:///Users/varun/Development/Anchor/Anchored/Engine/BrowserStrategies.swift) protocol for fetching active browser tab URLs. Do not call direct scripts outside strategies.

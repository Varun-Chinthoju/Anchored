import AppKit
import SwiftUI

class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let focusEngine: FocusEngine
    private let sessionStore: SessionStore
    private var settingsWindow: SettingsWindow?
    private var startSessionWindow: StartSessionWindow?
    private var pendingReviewTarget: ReviewTarget?

    private struct ReviewTarget {
        let bundleID: String
        let localizedName: String?
        let url: URL?
        let title: String?
    }
    
    init(focusEngine: FocusEngine, sessionStore: SessionStore = .shared) {
        self.focusEngine = focusEngine
        self.sessionStore = sessionStore
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        
        setupStatusItem()
        
        // Observe focus engine state changes to update menu bar icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .focusEngineStateDidChange,
            object: nil
        )
        
        // Observe active profile change events to update UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .activeProfileDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupStatusItem() {
        updateStatusItemIcon()
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }
    
    @objc private func handleStateChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItemIcon()
        }
    }
    
    private func updateStatusItemIcon() {
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: "anchor.circle.fill", accessibilityDescription: "Anchored")
            ?? NSImage(named: "MenuBarIcon")

        button.image = icon
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Anchored"
    }
    
    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        pendingReviewTarget = makeReviewTarget()
        
        // Status header
        let activeProfileName = ProfileManager.shared.activeProfile.name
        if let session = focusEngine.activeSession {
            let baseStatus = session.goal != nil ? "Focus: \(session.goal!)" : "Focusing in \(session.displayName)"
            let statusTitle = focusEngine.isFocusScheduleActive ? baseStatus : "\(baseStatus) (Schedule Off)"
            let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            
            let now = Date()
            let elapsed: TimeInterval
            if let pausedAt = focusEngine.pausedDate {
                elapsed = pausedAt.timeIntervalSince(session.startDate)
            } else {
                elapsed = now.timeIntervalSince(session.startDate)
            }
            let remaining = max(0, session.anchoredDuration - elapsed)
            let remainingMin = Int(remaining / 60)
            let remainingSec = Int(remaining) % 60
            let timeString = focusEngine.pausedDate != nil ? "\(remainingMin)m \(remainingSec)s (Paused)" : (remainingMin > 0 ? "\(remainingMin)m \(remainingSec)s" : "\(remainingSec)s")
            
            let timeItem = NSMenuItem(title: "Time Remaining: \(timeString)", action: nil, keyEquivalent: "")
            timeItem.isEnabled = false
            menu.addItem(timeItem)
            
            let endSessionItem = NSMenuItem(title: "End Focus Session", action: #selector(endSessionClicked), keyEquivalent: "")
            endSessionItem.target = self
            menu.addItem(endSessionItem)

            let forceDimItem = NSMenuItem(title: "Force Dim Now", action: #selector(forceDimClicked), keyEquivalent: "d")
            forceDimItem.target = self
            forceDimItem.keyEquivalentModifierMask = [.command, .option, .shift]
            menu.addItem(forceDimItem)
        } else {
            let statusTitle = focusEngine.isFocusScheduleActive ? "Status: Ready to Focus" : "Status: Outside Focus Schedule"
            let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            
            let startSessionItem = NSMenuItem(title: "Start Focus Session...", action: #selector(startSessionClicked), keyEquivalent: "s")
            startSessionItem.target = self
            menu.addItem(startSessionItem)
        }
        
        let reviewCurrentItem = NSMenuItem(title: reviewCurrentItemTitle(), action: #selector(reviewCurrentItemAsProductiveClicked), keyEquivalent: "")
        reviewCurrentItem.target = self
        reviewCurrentItem.isEnabled = pendingReviewTarget != nil
        menu.addItem(reviewCurrentItem)
        
        let profileHeaderItem = NSMenuItem(title: "Active Profile: \(activeProfileName)", action: nil, keyEquivalent: "")
        profileHeaderItem.isEnabled = false
        menu.addItem(profileHeaderItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Stats
        let stats = sessionStore.getStats()
        let focusTimeMin = Int(stats.focusedTimeToday / 60)
        let statsItem = NSMenuItem(title: "Focus Today: \(focusTimeMin)m (\(stats.sessionCountToday) session\(stats.sessionCountToday != 1 ? "s" : ""))", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        
        let streakItem = NSMenuItem(title: "Focus Streak: \(stats.streakDays) day\(stats.streakDays != 1 ? "s" : "")", action: nil, keyEquivalent: "")
        streakItem.isEnabled = false
        menu.addItem(streakItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings & Actions
        let editItem = NSMenuItem(title: "Manage Distractions...", action: #selector(editDistractionList), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        
        let switchProfileItem = NSMenuItem(title: "Switch Profile", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let profiles = ProfileManager.shared.profiles
        let activeProfile = ProfileManager.shared.activeProfile
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(switchProfileClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.name
            if profile.id == activeProfile.id {
                item.state = .on
            } else {
                item.state = .off
            }
            submenu.addItem(item)
        }
        switchProfileItem.submenu = submenu
        menu.addItem(switchProfileItem)
        
        let dashboardItem = NSMenuItem(title: "Open Analytics...", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        
        let prefsItem = NSMenuItem(title: "Settings...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Anchored", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func switchProfileClicked(_ sender: NSMenuItem) {
        if let profileName = sender.representedObject as? String {
            ProfileManager.shared.switchProfile(to: profileName)
        }
    }
    
    @objc func endSessionClicked() {
        focusEngine.endSession()
    }

    @objc func forceDimClicked() {
        focusEngine.forceImmediateDim()
    }

    @objc func reviewCurrentItemAsProductiveClicked() {
        let reviewTarget = pendingReviewTarget ?? makeReviewTarget()
        pendingReviewTarget = nil

        guard let reviewTarget, reviewTarget.bundleID != "com.varun.Anchored" else {
            presentNoCurrentItemAlert()
            return
        }

        focusEngine.reviewItemAsProductive(
            bundleID: reviewTarget.bundleID,
            localizedName: reviewTarget.localizedName,
            url: reviewTarget.url,
            title: reviewTarget.title
        ) { [weak self] review in
            DispatchQueue.main.async {
                self?.presentProductiveReviewAlert(review: review, target: reviewTarget)
            }
        }
    }
    
    @objc private func editDistractionList() {
        showSettingsWindow(section: .distractions)
    }
    
    @objc func openPreferences() {
        showSettingsWindow(section: .general)
    }
    
    @objc func openDashboard() {
        showSettingsWindow(section: .captainsLog)
    }

    private func showSettingsWindow(section: SettingsSection) {
        if let window = settingsWindow {
            window.close()
        }
        
        NSApp.setActivationPolicy(.regular)
        let window = SettingsWindow(
            focusEngine: focusEngine,
            initialSection: section,
            onCheckForUpdates: UpdateManager.shared.checkForUpdates
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func settingsWindowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            
            if startSessionWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @objc func startSessionClicked() {
        if let window = startSessionWindow {
            window.close()
        }
        
        NSApp.setActivationPolicy(.regular)
        let window = StartSessionWindow(focusEngine: focusEngine)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(startSessionWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        
        self.startSessionWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func startSessionWindowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == startSessionWindow {
            startSessionWindow = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            
            if settingsWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func presentNoCurrentItemAlert() {
        let alert = NSAlert()
        alert.messageText = "No Current Item"
        alert.informativeText = "Anchored does not have a visible app or window to review right now."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func makeReviewTarget() -> ReviewTarget? {
        if let context = focusEngine.currentContext,
           context.bundleIdentifier != "com.varun.Anchored" {
            return ReviewTarget(
                bundleID: context.bundleIdentifier,
                localizedName: context.localizedName,
                url: focusEngine.currentURL,
                title: context.title
            )
        }

        guard let bundleID = focusEngine.currentApp ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              bundleID != "com.varun.Anchored" else {
            return nil
        }

        return ReviewTarget(
            bundleID: bundleID,
            localizedName: focusEngine.currentContext?.localizedName,
            url: focusEngine.currentURL,
            title: focusEngine.currentContext?.title ?? focusEngine.currentTitle
        )
    }

    private func presentProductiveReviewAlert(
        review: ProductiveCorrectionReview,
        target: ReviewTarget
    ) {
        let alert = NSAlert()
        alert.messageText = "Review Current Item"
        alert.informativeText = review.message

        let choices: [(title: String, scope: ProductiveCorrectionScope)] = {
            switch review.recommendedScope {
            case .app:
                return [("Mark This App as Productive", .app)]
            case .website:
                return [("Mark This Website as Productive", .website)]
            case .page:
                var options: [(title: String, scope: ProductiveCorrectionScope)] = [("This Page Is Related to My Focus", .page)]
                if review.canUseWebsiteScope {
                    options.append(("This Website Is Productive", .website))
                }
                return options
            }
        }()

        for choice in choices {
            alert.addButton(withTitle: choice.title)
        }
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        let selectedScope: ProductiveCorrectionScope?
        switch response {
        case .alertFirstButtonReturn:
            selectedScope = choices.first?.scope
        case .alertSecondButtonReturn:
            selectedScope = choices.dropFirst().first?.scope
        default:
            selectedScope = nil
        }

        guard let selectedScope else { return }

        switch selectedScope {
        case .app:
            focusEngine.applyCorrection(.allowApp, bundleID: target.bundleID, url: target.url, title: target.title)
        case .website:
            focusEngine.applyCorrection(.allowDomain, bundleID: target.bundleID, url: target.url, title: target.title)
        case .page:
            let snapshot = ContextSnapshot(
                bundleIdentifier: target.bundleID,
                localizedName: target.localizedName ?? focusEngine.currentContext?.localizedName ?? target.bundleID,
                url: target.url,
                title: target.title ?? "",
                source: BrowserStrategyFactory.isSupportedBrowser(target.bundleID)
                    ? (target.bundleID == "com.apple.Safari" ? .safari : .chromium)
                    : .application,
                observedAt: Date()
            )
            focusEngine.applyPageScopedProductive(snapshot: snapshot)
        }
    }

    private func reviewCurrentItemTitle() -> String {
        guard let reviewTarget = pendingReviewTarget ?? makeReviewTarget() else {
            return "Review Current Item"
        }

        switch ContextualSiteHeuristic.reviewScope(
            for: reviewTarget.bundleID,
            url: reviewTarget.url,
            title: reviewTarget.title ?? ""
        ) {
        case .app:
            return "Mark This App as Productive..."
        case .website:
            return "Mark This Website as Productive..."
        case .page:
            return "This Page Is Related to My Focus..."
        }
    }
}

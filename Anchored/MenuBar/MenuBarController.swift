import AppKit
import SwiftUI

class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let focusEngine: FocusEngine
    private let sessionStore: SessionStore
    private var settingsWindow: SettingsWindow?
    
    init(focusEngine: FocusEngine, sessionStore: SessionStore = .shared) {
        self.focusEngine = focusEngine
        self.sessionStore = sessionStore
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        
        setupStatusItem()
        
        // Observe focus engine state changes to update menu bar icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .focusEngineStateDidChange,
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
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "anchor", accessibilityDescription: "Anchored")
            button.image?.isTemplate = true
        }
    }
    
    // MARK: - NSMenuDelegate
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // Status header
        if let session = focusEngine.activeSession {
            let statusItem = NSMenuItem(title: "Status: Active (Focusing on \(session.appName))", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            
            let now = Date()
            let elapsed = now.timeIntervalSince(session.startDate)
            let remaining = max(0, session.anchoredDuration - elapsed)
            let remainingMin = Int(remaining / 60)
            let remainingSec = Int(remaining) % 60
            let timeString = remainingMin > 0 ? "\(remainingMin)m \(remainingSec)s" : "\(remainingSec)s"
            
            let timeItem = NSMenuItem(title: "Time Remaining: \(timeString)", action: nil, keyEquivalent: "")
            timeItem.isEnabled = false
            menu.addItem(timeItem)
            
            let endSessionItem = NSMenuItem(title: "End Session", action: #selector(endSessionClicked), keyEquivalent: "")
            endSessionItem.target = self
            menu.addItem(endSessionItem)
        } else {
            let statusItem = NSMenuItem(title: "Status: Idle (Ready to Anchor)", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Stats
        let stats = sessionStore.getStats()
        let focusTimeMin = Int(stats.focusedTimeToday / 60)
        let statsItem = NSMenuItem(title: "Focus Time Today: \(focusTimeMin)m (\(stats.sessionCountToday) session\(stats.sessionCountToday != 1 ? "s" : ""))", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        
        let streakItem = NSMenuItem(title: "Streak: \(stats.streakDays) day\(stats.streakDays != 1 ? "s" : "")", action: nil, keyEquivalent: "")
        streakItem.isEnabled = false
        menu.addItem(streakItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings & Actions
        let editFocusItem = NSMenuItem(title: "Edit Focus Apps...", action: #selector(editFocusAppsList), keyEquivalent: "")
        editFocusItem.target = self
        menu.addItem(editFocusItem)
        
        let editItem = NSMenuItem(title: "Edit Distraction List...", action: #selector(editDistractionList), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Anchored", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func endSessionClicked() {
        focusEngine.endSession()
    }
    
    @objc private func editFocusAppsList() {
        showSettingsWindow(section: .focusApps)
    }
    
    @objc private func editDistractionList() {
        showSettingsWindow(section: .distractions)
    }
    
    @objc private func openPreferences() {
        showSettingsWindow(section: .general)
    }
    
    private func showSettingsWindow(section: SettingsSection) {
        if let window = settingsWindow {
            window.close()
        }
        
        let window = SettingsWindow(initialSection: section)
        
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
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

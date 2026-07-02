import AppKit
import SwiftUI

class SettingsWindow: NSWindow {
    
    init(initialSection: SettingsSection = .general) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Anchored Settings"
        self.isReleasedWhenClosed = false
        self.isOpaque = true
        self.hasShadow = true
        self.minSize = NSSize(width: 600, height: 380)
        
        let view = SettingsView(initialSection: initialSection)
        self.contentView = NSHostingView(rootView: view)
        self.center()
    }
}

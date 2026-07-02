import AppKit
import SwiftUI

class SettingsWindow: NSWindow {
    
    init(initialSection: SettingsSection = .general) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 990, height: 630),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Anchored Settings"
        self.isReleasedWhenClosed = false
        self.isOpaque = true
        self.hasShadow = true
        self.minSize = NSSize(width: 900, height: 570)
        self.appearance = NSAppearance(named: .vibrantDark)
        self.titlebarAppearsTransparent = true
        
        let view = SettingsView(initialSection: initialSection)
            .preferredColorScheme(.dark)
        self.contentView = NSHostingView(rootView: view)
        self.center()
    }
}

import AppKit
import SwiftUI

class SettingsWindow: NSWindow {
    
    init(focusEngine: FocusEngine, initialSection: SettingsSection = .general) {
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
        
        let themeAccent = ThemePalette.baldr.accentColor
        let view = SettingsView(focusEngine: focusEngine, initialSection: initialSection)
            .preferredColorScheme(.dark)
            .accentColor(themeAccent)
            .tint(themeAccent)
        self.contentView = NSHostingView(rootView: view)
        self.center()
    }
}

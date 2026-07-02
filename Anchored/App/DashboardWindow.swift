import AppKit
import SwiftUI

class DashboardWindow: NSWindow {
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Focus Dashboard"
        self.isReleasedWhenClosed = false
        self.isOpaque = true
        self.hasShadow = true
        self.titlebarAppearsTransparent = true
        self.appearance = NSAppearance(named: .vibrantDark)
        self.minSize = NSSize(width: 600, height: 480)
        self.maxSize = NSSize(width: 600, height: 480)
        
        let view = DashboardView()
            .preferredColorScheme(.dark)
        self.contentView = NSHostingView(rootView: view)
        self.center()
    }
}

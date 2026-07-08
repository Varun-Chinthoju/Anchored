import AppKit
import SwiftUI

/// A borderless, click-through window covering a display screen that gradually dims the view.
public final class DimOverlayWindow: NSWindow {
    public init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Window level selection based on macOS version (statusBar on macOS 14+, screenSaver on macOS 13)
        if #available(macOS 14.0, *) {
            self.level = .statusBar
        } else {
            self.level = .screenSaver
        }
        
        self.backgroundColor = NSColor(PirateTheme.canvas)
        self.alphaValue = 0.0
        self.isOpaque = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
    }
    
    public static let maxAlpha: CGFloat = 0.85
    public static let escalationDuration: TimeInterval = 3.0
    
    /// Starts the ambient escalation animation, ramping opacity to maxAlpha over escalationDuration.
    public func startEscalation() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.escalationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().alphaValue = Self.maxAlpha
        }
    }
    
    /// Fades out the overlay and removes the window.
    public func liftOverlay() {
        self.alphaValue = 0.0
        self.close()
    }
}

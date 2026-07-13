import AppKit
import SwiftUI

/// A borderless, click-through window covering a display screen that gradually dims the view.
public final class DimOverlayWindow: NSWindow {
    public let maxAlpha: CGFloat
    public let escalationDuration: TimeInterval

    public init(screen: NSScreen, maxAlpha: CGFloat = CGFloat(PreferencesManager.shared.dimOpacity), escalationDuration: TimeInterval = PreferencesManager.shared.dimTransitionDuration) {
        self.maxAlpha = maxAlpha
        self.escalationDuration = escalationDuration

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
        
        self.backgroundColor = PirateTheme.canvasNSColor
        self.alphaValue = 0.0
        self.isOpaque = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isReleasedWhenClosed = false
    }
    
    /// Starts the ambient escalation animation, ramping opacity to maxAlpha over escalationDuration.
    public func startEscalation() {
        if escalationDuration <= 0 {
            self.alphaValue = maxAlpha
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = escalationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().alphaValue = maxAlpha
            }
        }
    }
    
    /// Fades out the overlay and removes the window.
    public func liftOverlay() {
        self.alphaValue = 0.0
        self.close()
    }
}

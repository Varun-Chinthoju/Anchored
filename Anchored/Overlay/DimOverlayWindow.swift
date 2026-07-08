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
    
    /// Starts the ambient escalation animation, ramping opacity to 0.5 over 15 seconds.
    public func startEscalation() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 15.0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().alphaValue = 0.5
        }
    }
    
    /// Fades out the overlay and removes the window.
    public func liftOverlay() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.close()
        })
    }
}

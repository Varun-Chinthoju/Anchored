import AppKit
import SwiftUI

class OnboardingWindow: NSWindow {
    
    init(onComplete: @escaping () -> Void) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 520)
        super.init(
            contentRect: screenFrame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.setFrame(screenFrame, display: true)
        
        self.title = "Anchored Setup"
        self.isOpaque = false
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        
        // Host the OnboardingView directly
        let view = OnboardingView(onComplete: { [weak self] in
            self?.fadeOutAndClose(onComplete: onComplete)
        })
        
        self.contentView = NSHostingView(rootView: view)
    }
    
    private func fadeOutAndClose(onComplete: @escaping () -> Void) {
        onComplete()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.close()
        })
    }
}

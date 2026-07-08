import AppKit
import SwiftUI

public class PermissionGatePanel: NSPanel {
    private var isDismissing = false
    
    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        
        if #available(macOS 14.0, *) {
            self.level = .statusBar
        } else {
            self.level = .screenSaver
        }
        
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    public func show(
        onGrant: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        isDismissing = false
        let themeAccent = PirateTheme.gold
        
        let view = PermissionGateView(
            onGrant: { [weak self] in
                self?.handleGrant(callback: onGrant)
            },
            onDismiss: { [weak self] in
                self?.handleDismiss(callback: onDismiss)
            }
        )
        .accentColor(themeAccent)
        .tint(themeAccent)
        
        let hostingView = NSHostingView(rootView: view)
        self.contentView = hostingView
        
        guard let primaryScreen = NSScreen.screens.first else { return }
        let viewSize = hostingView.fittingSize
        let screenFrame = primaryScreen.frame
        
        // Centered on the primary screen
        let targetX = screenFrame.origin.x + (screenFrame.size.width - viewSize.width) / 2.0
        let targetY = screenFrame.origin.y + (screenFrame.size.height - viewSize.height) / 2.0
        let targetFrame = NSRect(x: targetX, y: targetY, width: viewSize.width, height: viewSize.height)
        
        self.setFrame(targetFrame, display: true)
        self.alphaValue = 0.0
        self.orderFront(nil)
        
        // Play Pop sound feedback when the panel appears
        AudioEngine.shared.play(.pop)
        
        // Fade in animation (SwiftUI view handles the spring scale)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }
    
    private func handleGrant(callback: @escaping () -> Void) {
        guard !isDismissing else { return }
        dismissPanel {
            callback()
        }
    }
    
    private func handleDismiss(callback: @escaping () -> Void) {
        guard !isDismissing else { return }
        dismissPanel {
            callback()
        }
    }
    
    private func dismissPanel(completion: @escaping () -> Void) {
        isDismissing = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            completion()
        })
    }
}

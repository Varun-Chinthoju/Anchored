import AppKit
import SwiftUI

public class DimCenterPanel: NSPanel {
    private var isDismissing = false
    private var hostingView: NSHostingView<DimCenterView>?
    
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
        onBreak: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onReturnToWork: @escaping () -> Void,
        onDeclareActivity: @escaping (String) -> Void
    ) {
        isDismissing = false
        
        let view = DimCenterView(
            onBreak: { [weak self] in
                self?.slideUpAndHide {
                    onBreak()
                }
            },
            onCancel: { [weak self] in
                self?.slideUpAndHide {
                    onCancel()
                }
            },
            onReturnToWork: { [weak self] in
                self?.slideUpAndHide {
                    onReturnToWork()
                }
            },
            onDeclareActivity: { [weak self] activity in
                self?.slideUpAndHide {
                    onDeclareActivity(activity)
                }
            }
        )
        
        let host = NSHostingView(rootView: view)
        self.contentView = host
        self.hostingView = host
        
        guard let primaryScreen = NSScreen.screens.first else { return }
        let viewSize = host.fittingSize
        let screenFrame = primaryScreen.frame
        
        // Centered on the primary screen
        let targetX = screenFrame.origin.x + (screenFrame.size.width - viewSize.width) / 2.0
        let targetY = screenFrame.origin.y + (screenFrame.size.height - viewSize.height) / 2.0
        let targetFrame = NSRect(x: targetX, y: targetY, width: viewSize.width, height: viewSize.height)
        
        self.setFrame(targetFrame, display: true)
        self.alphaValue = 0.0
        self.orderFront(nil)
        
        // Fade in animation matching macOS dialogs
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }
    
    public func closePanel() {
        guard !isDismissing else { return }
        slideUpAndHide {}
    }
    
    private func slideUpAndHide(completion: @escaping () -> Void) {
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

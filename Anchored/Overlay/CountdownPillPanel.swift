import AppKit
import SwiftUI

public class CountdownPillPanel: NSPanel {
    private var timer: Timer?
    private var secondsRemaining = 0
    private var completionHandler: (() -> Void)?
    private var hostingView: NSHostingView<CountdownPillView>?
    
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
        self.level = .floating // Above normal windows, below dim overlay (level statusBar/screenSaver)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    public func show(seconds: Int, onComplete: @escaping () -> Void) {
        // Cancel any active countdown timer first
        cancelTimer()
        
        self.secondsRemaining = seconds
        self.completionHandler = onComplete
        
        if seconds <= 0 {
            self.completionHandler?()
            return
        }
        
        updateView()
        positionPanel()
        
        // Initial setup for fade-in animation
        self.alphaValue = 0.0
        self.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }, completionHandler: nil)
        
        // Schedule 1-second ticks
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.secondsRemaining -= 1
            if self.secondsRemaining <= 0 {
                self.cancelTimer()
                // Fade out, then execute completion handler
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self.animator().alphaValue = 0.0
                }, completionHandler: {
                    self.orderOut(nil)
                    self.completionHandler?()
                })
            } else {
                self.updateView()
            }
        }
    }
    
    public func cancel() {
        cancelTimer()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
    
    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateView() {
        let view = CountdownPillView(secondsRemaining: secondsRemaining)
        if let host = self.hostingView {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            self.contentView = host
            self.hostingView = host
        }
        
        // Adjust panel frame size based on fitting content size
        if let viewSize = self.contentView?.fittingSize {
            var frame = self.frame
            frame.size = viewSize
            self.setFrame(frame, display: true)
        }
    }
    
    private func positionPanel() {
        guard let primaryScreen = NSScreen.screens.first else { return }
        
        let viewSize = self.contentView?.fittingSize ?? CGSize(width: 220, height: 40)
        let screenFrame = primaryScreen.frame
        let padding: CGFloat = 20
        let menuBarHeight: CGFloat = 24
        
        // Upper-right corner layout, with space for the menu bar
        let x = screenFrame.origin.x + screenFrame.size.width - viewSize.width - padding
        let y = screenFrame.origin.y + screenFrame.size.height - viewSize.height - padding - menuBarHeight
        
        self.setFrame(NSRect(x: x, y: y, width: viewSize.width, height: viewSize.height), display: true)
    }
}

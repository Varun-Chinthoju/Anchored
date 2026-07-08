import AppKit
import SwiftUI
import AudioToolbox // Fallback to System Sound if AudioEngine pop fails

public class ExitTriggerPanel: NSPanel {
    private var dismissTimer: Timer?
    private var isDismissing = false
    private var currentDismissCallback: (() -> Void)?
    
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
        duration: TimeInterval,
        appName: String,
        onAnchor: @escaping (TimeInterval) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // Cancel any active timers
        cancelTimer()
        isDismissing = false
        currentDismissCallback = onDismiss
        let themeAccent = PirateTheme.gold
        
        let formatted = formatDuration(duration)
        
        let view = ExitTriggerView(
            formattedDuration: formatted,
            appName: appName,
            onAnchor: { [weak self] chosenDuration in
                self?.handleAnchorSelection(chosenDuration, callback: onAnchor)
            },
            onDismiss: { [weak self] in
                self?.handleDismissSelection()
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
        
        // Play Pop sound
        AudioEngine.shared.play(.pop)
        
        // Fade in animation matching macOS dialogs
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }, completionHandler: nil)
        
        // 15 seconds auto-dismiss
        self.dismissTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.handleAutoDismiss()
        }
    }
    
    private func handleAnchorSelection(_ duration: TimeInterval, callback: @escaping (TimeInterval) -> Void) {
        guard !isDismissing else { return }
        cancelTimer()
        
        slideUpAndHide {
            callback(duration)
        }
    }
    
    private func handleDismissSelection() {
        guard !isDismissing else { return }
        cancelTimer()
        
        slideUpAndHide { [weak self] in
            self?.currentDismissCallback?()
        }
    }
    
    private func handleAutoDismiss() {
        guard !isDismissing else { return }
        
        slideUpAndHide { [weak self] in
            self?.currentDismissCallback?()
        }
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
    
    private func cancelTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(round(duration))
        if totalSeconds < 60 {
            return "\(totalSeconds) second\(totalSeconds != 1 ? "s" : "")"
        }
        
        let minutes = totalSeconds / 60
        if minutes == 1 {
            return "1 minute"
        } else if minutes < 60 {
            let remainingSeconds = totalSeconds % 60
            if remainingSeconds == 0 {
                return "\(minutes) minutes"
            } else {
                return "\(minutes)m \(remainingSeconds)s"
            }
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hour\(hours > 1 ? "s" : "")"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}

import AppKit
import SwiftUI

/// Panel that presents the doomscroll loop-breaker prompt when the user
/// has been on a distraction app outside a focus session for too long.
public class DoomscrollBreakerPanel: NSPanel {
    private var isDismissing = false
    private var hostingView: NSHostingView<DoomscrollBreakerView>?

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
        self.isReleasedWhenClosed = false
    }

    public func show(
        threshold: TimeInterval,
        onDim: @escaping () -> Void,
        onStartFocus: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        isDismissing = false

        let view = DoomscrollBreakerView(
            threshold: threshold,
            onDim: { [weak self] in
                self?.fadeOutAndHide { onDim() }
            },
            onStartFocus: { [weak self] in
                self?.fadeOutAndHide { onStartFocus() }
            },
            onDismiss: { [weak self] in
                self?.fadeOutAndHide { onDismiss() }
            }
        )

        let host = NSHostingView(rootView: view)
        self.contentView = host
        self.hostingView = host

        guard let primaryScreen = NSScreen.screens.first else { return }
        let viewSize = host.fittingSize
        let screenFrame = primaryScreen.frame

        // Positioned in the upper-right, below the menu bar
        let padding: CGFloat = 20
        let menuBarHeight: CGFloat = 24
        let x = screenFrame.origin.x + screenFrame.size.width - viewSize.width - padding
        let y = screenFrame.origin.y + screenFrame.size.height - viewSize.height - padding - menuBarHeight

        self.setFrame(NSRect(x: x, y: y, width: viewSize.width, height: viewSize.height), display: true)
        self.alphaValue = 0.0
        self.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }

    public func closePanel() {
        guard !isDismissing else { return }
        fadeOutAndHide {}
    }

    private func fadeOutAndHide(completion: @escaping () -> Void) {
        guard !isDismissing else { return }
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

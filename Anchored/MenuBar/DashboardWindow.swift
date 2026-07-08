import AppKit
import SwiftUI

final class DashboardWindow: NSWindow {
    init(focusEngine: FocusEngine, onOpenSettings: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Anchored Dashboard"
        isReleasedWhenClosed = false
        isOpaque = true
        hasShadow = true
        minSize = NSSize(width: 980, height: 680)
        appearance = NSAppearance(named: .vibrantDark)
        titlebarAppearsTransparent = true

        let rootView = DashboardView(
            focusEngine: focusEngine,
            onOpenSettings: onOpenSettings
        )
        .preferredColorScheme(.dark)
        .accentColor(PreferencesManager.shared.selectedThemePalette.accentColor)
        .tint(PreferencesManager.shared.selectedThemePalette.accentColor)

        contentView = NSHostingView(rootView: rootView)
        center()
    }
}

import AppKit
import SwiftUI

/// A borderless, click-through window covering a display screen that gradually dims the view.
public final class DimOverlayWindow: NSWindow {
    public static let missionMessageRevealFraction: Double = 0.30
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

        let host = NSHostingView(
            rootView: SandOverlayView(
                escalationDuration: escalationDuration
            )
        )
        host.frame = screen.frame
        self.contentView = host
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

private struct SandOverlayView: View {
    let escalationDuration: TimeInterval
    @State private var startDate = Date()

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: startDate, by: 1.0 / 24.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let normalized = escalationDuration <= 0 ? 1.0 : min(1.0, elapsed / escalationDuration)
            let grainDensity = 120 + Int(280 * normalized)
            let grainOpacity = 0.018 + (0.08 * normalized)
            let smearOpacity = 0.03 + (0.10 * normalized)

            GeometryReader { geometry in
                ZStack {
                    Canvas { context, size in
                        drawSandGrains(
                            in: context,
                            size: size,
                            elapsed: elapsed,
                            grainDensity: grainDensity,
                            grainOpacity: grainOpacity
                        )
                    }

                    LinearGradient(
                        colors: [
                            Color.black.opacity(smearOpacity),
                            Color.clear,
                            Color.black.opacity(smearOpacity * 0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.02 + normalized * 0.03),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.65
                    )
                    .blendMode(.screen)
                }
            }
        }
        .background(Color.clear)
        .allowsHitTesting(false)
    }

    private func drawSandGrains(
        in context: GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval,
        grainDensity: Int,
        grainOpacity: Double
    ) {
        for index in 0..<grainDensity {
            let seed = Double(index) * 0.618_033_988_75 + elapsed * 0.91
            let x = Self.noise(seed: seed) * size.width
            let y = Self.noise(seed: seed + 11.0) * size.height
            let driftX = sin(elapsed * 0.7 + Double(index) * 0.13) * (2.0 + Double(index % 7) * 0.35)
            let driftY = cos(elapsed * 0.5 + Double(index) * 0.17) * (1.5 + Double(index % 5) * 0.28)
            let width = 0.8 + Self.noise(seed: seed + 23.0) * 2.0
            let height = 0.8 + Self.noise(seed: seed + 37.0) * 2.0
            let rect = CGRect(
                x: x + driftX,
                y: y + driftY,
                width: width,
                height: height
            )

            let warm = Color(red: 0.96, green: 0.88, blue: 0.70)
            let cool = Color.black
            let isWarm = index.isMultiple(of: 4)
            let color = isWarm ? warm : cool
            let opacity = grainOpacity + (Self.noise(seed: seed + 53.0) * 0.04)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        }
    }

    private static func noise(seed: Double) -> Double {
        let value = sin(seed * 12.9898) * 43758.5453
        return value - floor(value)
    }
}

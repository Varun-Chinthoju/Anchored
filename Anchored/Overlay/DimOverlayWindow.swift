import AppKit
import SwiftUI

/// A borderless, click-through window covering a display screen that gradually dims the view.
public final class DimOverlayWindow: NSWindow {
    static let missionMessageRevealFraction: Double = 0.30
    public let maxAlpha: CGFloat
    public let escalationDuration: TimeInterval

    public init(
        screen: NSScreen,
        maxAlpha: CGFloat = CGFloat(PreferencesManager.shared.dimOpacity),
        escalationDuration: TimeInterval = PreferencesManager.shared.dimTransitionDuration
    ) {
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
            rootView: FogOverlayView(
                escalationDuration: escalationDuration,
                missionMessageDuration: max(0, escalationDuration * Self.missionMessageRevealFraction)
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

private struct FogOverlayView: View {
    let escalationDuration: TimeInterval
    let missionMessageDuration: TimeInterval
    @State private var startDate = Date()
    @State private var missionMessageVisible = true
    @State private var hideMissionMessageWorkItem: DispatchWorkItem?

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: startDate, by: 1.0 / 24.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let normalized = escalationDuration <= 0 ? 1.0 : min(1.0, elapsed / escalationDuration)
            let grainDensity = 96 + Int(180 * normalized)
            let grainOpacity = 0.012 + (0.035 * normalized)
            let hazeOpacity = 0.08 + (0.16 * normalized)

            GeometryReader { geometry in
                ZStack {
                    backgroundFogLayer(normalized: normalized)

                    fogWisps(size: geometry.size, elapsed: elapsed, normalized: normalized)

                    Canvas { context, size in
                        drawFogDust(
                            in: context,
                            size: size,
                            elapsed: elapsed,
                            grainDensity: grainDensity,
                            grainOpacity: grainOpacity
                        )
                    }

                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.95, blue: 0.90).opacity(hazeOpacity),
                            Color.clear,
                            Color.black.opacity(0.12 + normalized * 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)

                    if missionMessageVisible {
                        missionMessageCard
                            .padding(.horizontal, 56)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(Color.clear)
        .allowsHitTesting(false)
        .onAppear {
            startDate = Date()
            missionMessageVisible = true
            hideMissionMessageWorkItem?.cancel()

            let workItem = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.25)) {
                    missionMessageVisible = false
                }
                hideMissionMessageWorkItem = nil
            }
            hideMissionMessageWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, missionMessageDuration), execute: workItem)
        }
        .onDisappear {
            hideMissionMessageWorkItem?.cancel()
            hideMissionMessageWorkItem = nil
        }
    }

    private var missionMessageCard: some View {
        VStack(spacing: 10) {
            Text("Ye have strayed from the mission")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundColor(Color.white.opacity(0.96))
                .multilineTextAlignment(.center)

            Text("The fog will clear, then the current popup returns.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color.white.opacity(0.75))
                .tracking(0.4)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 24, x: 0, y: 12)
    }

    private func backgroundFogLayer(normalized: Double) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.10).opacity(0.90),
                    Color(red: 0.15, green: 0.16, blue: 0.14).opacity(0.84),
                    Color(red: 0.24, green: 0.22, blue: 0.18).opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.07 + normalized * 0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 860
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    Color.white.opacity(0.04 + normalized * 0.04),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 14,
                endRadius: 620
            )
            .blendMode(.screen)
        }
    }

    private func fogWisps(size: CGSize, elapsed: TimeInterval, normalized: Double) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                fogWisp(index: index, size: size, elapsed: elapsed, normalized: normalized)
            }
        }
        .blendMode(.screen)
    }

    private func fogWisp(index: Int, size: CGSize, elapsed: TimeInterval, normalized: Double) -> some View {
        let seed = Double(index) * 17.137 + elapsed * 0.16
        let width = size.width * (0.36 + Self.noise(seed: seed + 1.0) * 0.42)
        let height = size.height * (0.09 + Self.noise(seed: seed + 9.0) * 0.22)
        let baseX = (Self.noise(seed: seed + 3.0) - 0.5) * size.width * 0.9
        let baseY = (Self.noise(seed: seed + 11.0) - 0.5) * size.height * 0.45
        let driftX = sin(elapsed * 0.12 + Double(index) * 0.65) * (24 + Double(index) * 5)
        let driftY = cos(elapsed * 0.10 + Double(index) * 0.43) * (14 + Double(index) * 4)
        let opacity = 0.045 + normalized * 0.10 + Self.noise(seed: seed + 19.0) * 0.03

        return Ellipse()
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
            .blur(radius: 44)
            .offset(x: baseX + driftX, y: baseY + driftY)
    }

    private func drawFogDust(
        in context: GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval,
        grainDensity: Int,
        grainOpacity: Double
    ) {
        for index in 0..<grainDensity {
            let seed = Double(index) * 0.618_033_988_75 + elapsed * 0.77
            let x = Self.noise(seed: seed) * size.width
            let y = Self.noise(seed: seed + 11.0) * size.height
            let driftX = sin(elapsed * 0.23 + Double(index) * 0.17) * (1.5 + Double(index % 7) * 0.25)
            let driftY = cos(elapsed * 0.18 + Double(index) * 0.19) * (1.2 + Double(index % 5) * 0.20)
            let width = 0.9 + Self.noise(seed: seed + 23.0) * 1.8
            let height = 0.9 + Self.noise(seed: seed + 37.0) * 1.8
            let rect = CGRect(
                x: x + driftX,
                y: y + driftY,
                width: width,
                height: height
            )

            let mist = Color.white
            let shadow = Color(red: 0.08, green: 0.09, blue: 0.10)
            let useMist = index.isMultiple(of: 3)
            let color = useMist ? mist : shadow
            let dustOpacity = grainOpacity + (Self.noise(seed: seed + 53.0) * 0.02)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(dustOpacity)))
        }
    }

    private static func noise(seed: Double) -> Double {
        let value = sin(seed * 12.9898) * 43758.5453
        return value - floor(value)
    }
}

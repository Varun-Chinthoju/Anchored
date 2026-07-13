import SwiftUI

/// Shown when the user has been on a distraction app outside of a session for too long.
/// Offers a gentle intervention: break the loop via dimming, or start a focus session.
public struct DoomscrollBreakerView: View {
    let threshold: TimeInterval
    let onDim: () -> Void
    let onStartFocus: () -> Void
    let onDismiss: () -> Void

    @State private var dismissCountdown = 3
    @State private var countdownTimer: Timer? = nil

    private var formattedThreshold: String {
        let mins = Int(threshold) / 60
        if mins < 1 { return "\(Int(threshold))s" }
        return "\(mins) min"
    }

    private var themeAccent: Color { PirateTheme.gold }
    private var themeSurface: Color { PirateTheme.surface }
    private var themeSurfaceElevated: Color { PirateTheme.surfaceRaised }
    private var themeTextPrimary: Color { PirateTheme.textPrimary }
    private var themeTextSecondary: Color { PirateTheme.textSecondary }

    public init(
        threshold: TimeInterval,
        onDim: @escaping () -> Void,
        onStartFocus: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.threshold = threshold
        self.onDim = onDim
        self.onStartFocus = onStartFocus
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(themeAccent)
                    Text("Loop Detected")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(themeAccent)
                }

                Text("You've been scrolling for \(formattedThreshold).\nTime to break the loop?")
                    .font(.system(size: 13))
                    .foregroundColor(themeTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            Divider()
                .background(PirateTheme.separator.opacity(0.6))
                .padding(.vertical, 16)

            // Action buttons
            VStack(spacing: 10) {
                // Dim the screen — primary action
                Button(action: onDim) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.haze.fill")
                            .font(.system(size: 14))
                        Text("Dim Screen")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(PirateTheme.darkWood)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(themeAccent)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Start a focus session — secondary action
                Button(action: onStartFocus) {
                    HStack(spacing: 8) {
                        Image(systemName: "anchor")
                            .font(.system(size: 13))
                        Text("Start Focus Session")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(themeTextPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(themeSurfaceElevated.opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeAccent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            // Dismiss footer
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text(dismissCountdown > 0 ? "Dismiss (\(dismissCountdown))" : "Dismiss")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(dismissCountdown > 0 ? themeTextSecondary.opacity(0.4) : themeTextSecondary)
                }
                .buttonStyle(.plain)
                .disabled(dismissCountdown > 0)
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(width: 300)
        .background(
            ControlRoomShellBackground(palette: PreferencesManager.shared.selectedThemePalette)
                .cornerRadius(14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeAccent.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
        .onAppear { startCountdown() }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    private func startCountdown() {
        dismissCountdown = 3
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if dismissCountdown > 0 {
                dismissCountdown -= 1
            } else {
                countdownTimer?.invalidate()
                countdownTimer = nil
            }
        }
    }
}

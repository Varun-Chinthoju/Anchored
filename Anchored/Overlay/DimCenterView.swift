import SwiftUI

public struct DimCenterView: View {
    @State private var declaredActivity: String = ""
    @State private var countdownRemaining = 3
    @State private var timer: Timer? = nil
    @FocusState private var isActivityFieldFocused: Bool
    
    let onBreak: () -> Void
    let onCancel: () -> Void
    let onReturnToWork: () -> Void
    let onDeclareActivity: (String) -> Void
    let onExitSession: (String) -> Void
    
    public init(
        suggestedActivity: String? = nil,
        onBreak: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onReturnToWork: @escaping () -> Void,
        onDeclareActivity: @escaping (String) -> Void,
        onExitSession: @escaping (String) -> Void
    ) {
        self._declaredActivity = State(initialValue: suggestedActivity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        self.onBreak = onBreak
        self.onCancel = onCancel
        self.onReturnToWork = onReturnToWork
        self.onDeclareActivity = onDeclareActivity
        self.onExitSession = onExitSession
    }
    
    private var themeAccent: Color { PirateTheme.gold }
    private var themeSurface: Color { PirateTheme.surface }
    private var themeSurfaceElevated: Color { PirateTheme.surfaceRaised }
    private var themeTextPrimary: Color { PirateTheme.textPrimary }
    private var themeTextSecondary: Color { PirateTheme.textSecondary }
    private var panelCornerRadius: CGFloat { 28 }
    private var cardCornerRadius: CGFloat { 20 }
    
    public var body: some View {
        ZStack {
            tapShield

            backgroundLayer

            VStack(alignment: .leading, spacing: 22) {
                headerSection
                actionCard
                footerSection
            }
            .padding(30)
        }
        .frame(width: 560)
        .onAppear {
            startCountdown()
            DispatchQueue.main.async {
                isActivityFieldFocused = true
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var tapShield: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                // Absorb taps on decorative space so they do not fall through to the app behind the overlay.
            }
            .accessibilityHidden(true)
    }

    private var backgroundLayer: some View {
        ZStack {
            ControlRoomShellBackground(palette: PreferencesManager.shared.selectedThemePalette)
                .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))

            LinearGradient(
                colors: [
                    themeSurface.opacity(0.12),
                    themeSurfaceElevated.opacity(0.18),
                    Color.black.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))

            Circle()
                .fill(themeAccent.opacity(0.16))
                .frame(width: 240, height: 240)
                .blur(radius: 34)
                .offset(x: 184, y: -160)

            Circle()
                .fill(Color.white.opacity(0.03))
                .frame(width: 320, height: 320)
                .blur(radius: 56)
                .offset(x: -210, y: 172)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.03), Color.clear, Color.black.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(themeAccent.opacity(0.24), lineWidth: 1.25)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 28, x: 0, y: 14)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                pill(label: "Focus session", systemImage: "bolt.fill", accent: themeAccent)

                Text("Return to the work in front of you")
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundColor(themeTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Close the active tab or window, then Anchored restores the session without losing the thread.")
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .foregroundColor(themeTextPrimary.opacity(0.78))
                    .lineSpacing(1.2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    metaLabel(text: "Closes the current tab or window", systemImage: "xmark.circle.fill")

                    Circle()
                        .fill(themeTextSecondary.opacity(0.35))
                        .frame(width: 4, height: 4)

                    metaLabel(text: "Keeps the session moving", systemImage: "timer")
                }
            }

            Spacer(minLength: 14)

            VStack(alignment: .trailing, spacing: 10) {
                Text("Return status")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundColor(themeTextSecondary.opacity(0.8))

                Text(countdownRemaining > 0 ? "Ready in \(countdownRemaining)s" : "Ready now")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(themeTextPrimary)

                Text(countdownRemaining > 0 ? "Break remains locked briefly." : "The break action is available.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(themeTextSecondary.opacity(0.86))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(themeSurface.opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(themeTextPrimary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What are you working on?")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(themeTextPrimary)

                    Text("Anchored fills this from the current context, and you can edit it if needed.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(themeTextSecondary.opacity(0.9))
                }

                Spacer()

                Text("Suggested")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(themeAccent.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeAccent.opacity(0.12))
                    .clipShape(Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                themeSurfaceElevated.opacity(0.56),
                                themeSurface.opacity(0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                TextField("Draft the launch memo", text: $declaredActivity, onCommit: declareAndReturn)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(themeTextPrimary)
                    .focused($isActivityFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        hasDeclaredActivity ? themeAccent.opacity(0.34) : themeTextPrimary.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .shadow(color: hasDeclaredActivity ? themeAccent.opacity(0.08) : .clear, radius: 10, x: 0, y: 4)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(themeAccent.opacity(0.95))
                    .padding(.top, 1)

                Text("Anchored closes the active tab or window and keeps the session intact.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(themeTextSecondary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: declareAndReturn) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Close tab and return to work")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    Image(systemName: "return")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.7)
                }
                .foregroundColor(hasDeclaredActivity ? themeSurface : themeTextPrimary.opacity(0.45))
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: hasDeclaredActivity
                            ? [themeAccent.opacity(0.98), themeAccent.opacity(0.76)]
                            : [themeSurfaceElevated.opacity(0.62), themeSurface.opacity(0.44)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            hasDeclaredActivity ? themeAccent.opacity(0.34) : themeTextPrimary.opacity(0.14),
                            lineWidth: 1
                        )
                )
                .shadow(color: hasDeclaredActivity ? themeAccent.opacity(0.16) : .clear, radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!hasDeclaredActivity)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(themeSurface.opacity(0.44))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(themeTextPrimary.opacity(0.1), lineWidth: 1)
        )
    }

    private var footerSection: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .tint(themeTextSecondary)

            Button(action: {
                if countdownRemaining == 0 {
                    onBreak()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(countdownRemaining > 0 ? themeTextSecondary.opacity(0.45) : themeAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take a two-minute break")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(themeTextPrimary)
                        Text(countdownRemaining > 0 ? "Available in \(countdownRemaining)s" : "Step away without ending the session")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(themeTextSecondary.opacity(0.85))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(themeSurfaceElevated.opacity(countdownRemaining > 0 ? 0.3 : 0.46))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(themeAccent.opacity(countdownRemaining > 0 ? 0.11 : 0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(countdownRemaining > 0)

            Spacer()

            Text(countdownRemaining > 0 ? "Break unlocks in \(countdownRemaining)s" : "Break option is ready")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(themeTextSecondary.opacity(0.8))
        }
    }

    private func pill(label: String, systemImage: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundColor(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(accent.opacity(0.1))
        .clipShape(Capsule())
    }

    private func metaLabel(text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundColor(themeTextSecondary.opacity(0.9))
    }
    
    private func startCountdown() {
        countdownRemaining = 3
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdownRemaining > 0 {
                countdownRemaining -= 1
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    private var hasDeclaredActivity: Bool {
        !declaredActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func declareAndReturn() {
        let trimmed = declaredActivity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onDeclareActivity(trimmed)
    }
}

import SwiftUI

public struct DimCenterView: View {
    @State private var selection: String = "break"
    @State private var declaredActivity: String = ""
    @State private var countdownRemaining = 3
    @State private var timer: Timer? = nil
    
    let onBreak: () -> Void
    let onCancel: () -> Void
    let onReturnToWork: () -> Void
    let onDeclareActivity: (String) -> Void
    
    public init(
        onBreak: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onReturnToWork: @escaping () -> Void,
        onDeclareActivity: @escaping (String) -> Void
    ) {
        self.onBreak = onBreak
        self.onCancel = onCancel
        self.onReturnToWork = onReturnToWork
        self.onDeclareActivity = onDeclareActivity
    }
    
    private var themeAccent: Color { PirateTheme.gold }
    private var themeSurface: Color { PirateTheme.surface }
    private var themeSurfaceElevated: Color { PirateTheme.surfaceRaised }
    private var themeTextPrimary: Color { PirateTheme.textPrimary }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header text
            Text("Focus Disturbed")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(themeAccent)
            
            // Selector/Picker
            Picker("", selection: $selection) {
                Text("Take a Break?").tag("break")
                Text("Return to Work?").tag("work")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            
            if selection == "break" {
                VStack(spacing: 12) {
                    Text("Take a 2-minute restorative break.")
                        .font(.system(size: 13))
                        .foregroundColor(themeTextPrimary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(height: 36)
                    
                    Button(action: {
                        if countdownRemaining == 0 {
                            onBreak()
                        }
                    }) {
                        Text(countdownRemaining > 0 ? "Break (\(countdownRemaining))" : "Take a Break")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(countdownRemaining > 0 ? themeTextPrimary.opacity(0.4) : themeSurface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(countdownRemaining > 0 ? themeSurfaceElevated.opacity(0.5) : themeAccent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(countdownRemaining > 0)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    Text("What are you doing? Declare it to continue:")
                        .font(.system(size: 13))
                        .foregroundColor(themeTextPrimary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(height: 36)
                    
                    TextField("I am doing...", text: $declaredActivity, onCommit: {
                        let trimmed = declaredActivity.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onDeclareActivity(trimmed)
                        }
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .padding(.horizontal)
                    
                    Button(action: {
                        let trimmed = declaredActivity.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onDeclareActivity(trimmed)
                        }
                    }) {
                        Text("Declare Task")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(declaredActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? themeTextPrimary.opacity(0.4) : themeSurface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(declaredActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? themeSurfaceElevated.opacity(0.5) : themeAccent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(declaredActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .transition(.opacity)
            }
            
            Divider()
                .background(PirateTheme.separator)
            
            // Cancel underneath and Return to work
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(themeTextPrimary.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(themeSurfaceElevated.opacity(0.35))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(themeAccent.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: onReturnToWork) {
                    Text("Return to Work")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(themeTextPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(themeSurface.opacity(0.35))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(themeAccent.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(
            ControlRoomShellBackground(palette: PreferencesManager.shared.selectedThemePalette)
                .cornerRadius(12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeAccent.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
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
}

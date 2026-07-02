import SwiftUI

struct PreferencesStepView: View {
    let onComplete: (() -> Void)?
    let showSaveButton: Bool
    
    init(onComplete: (() -> Void)? = nil, showSaveButton: Bool = true) {
        self.onComplete = onComplete
        self.showSaveButton = showSaveButton
    }
    
    @StateObject private var prefs = PreferencesManager.shared
    
    private let thresholdOptions = [
        (300.0, "5 min"),
        (600.0, "10 min"),
        (900.0, "15 min"),
        (1800.0, "30 min")
    ]
    
    private let countdownOptions = [5, 10, 15, 20]
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Setup details)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.pink)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: "Customize\nBehavior",
                        font: .system(size: 36, weight: .bold, design: .rounded),
                        colors: [.pink, .purple]
                    )
                    
                    Text("Tailor how Anchored helps you maintain momentum. Adjust thresholds, warnings, and system integration options.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                
                Spacer()
                
                if showSaveButton {
                    Button(action: {
                        AudioEngine.shared.play(.chime)
                        onComplete?()
                    }) {
                        HStack {
                            Text("Save & Launch Anchored")
                            Image(systemName: "checkmark")
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.pink, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                        .shadow(color: Color.pink.opacity(0.3), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 320, alignment: .leading)
            
            // Right Column (Configurations list)
            VStack(alignment: .leading, spacing: 28) {
                // Focus Threshold Picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Focus Threshold")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Active time needed to trigger an anchor.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Focus Threshold", selection: $prefs.focusThreshold) {
                        ForEach(thresholdOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(20)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
                
                // Countdown Duration Picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Dimming Warning Countdown")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Seconds allowed on distraction before dimming.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Countdown Duration", selection: $prefs.countdownDuration) {
                        ForEach(countdownOptions, id: \.self) { value in
                            Text("\(value)s").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(20)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
                
                // Launch at Login Toggle
                Toggle(isOn: $prefs.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Automatically start Anchored on system launch.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

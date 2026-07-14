import SwiftUI

struct PreferencesStepView: View {
    let onComplete: (() -> Void)?
    let showSaveButton: Bool
    
    init(onComplete: (() -> Void)? = nil, showSaveButton: Bool = true) {
        self.onComplete = onComplete
        self.showSaveButton = showSaveButton
    }
    
    @StateObject private var prefs = PreferencesManager.shared
    @ObservedObject private var langManager = LanguageManager.shared
    
    private let thresholdOptions = [
        (300.0, "5 min"),
        (600.0, "10 min"),
        (900.0, "15 min"),
        (1800.0, "30 min")
    ]
    
    private let countdownOptions = [5, 10, 15, 20, 30]
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Setup details)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(PirateTheme.gold.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    SafeSystemImage(systemName: "gearshape.fill", size: 32)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: t("pref_title"),
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    
                    Text(t("pref_desc"))
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        .lineSpacing(4)
                }
                
                Spacer()
                
                if showSaveButton {
                    Button(action: {
                        AudioEngine.shared.play(.tick)
                        onComplete?()
                    }) {
                        HStack {
                            Text(t("pref_btn"))
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundColor(PirateTheme.darkWood)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                        .shadow(color: PirateTheme.gold.opacity(0.3), radius: 12, x: 0, y: 6)
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
                        Text(t("pref_threshold_title"))
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundColor(PirateTheme.parchment)
                        Spacer()
                        Text(t("pref_threshold_desc"))
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(PirateTheme.parchment.opacity(0.6))
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
                .background(PirateTheme.darkWood.opacity(0.4))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
                )
                
                // Countdown Duration Picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(t("pref_countdown_title"))
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundColor(PirateTheme.parchment)
                        Spacer()
                        Text(t("pref_countdown_desc"))
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(PirateTheme.parchment.opacity(0.6))
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
                .background(PirateTheme.darkWood.opacity(0.4))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
                )
                
                // Smart Nudges Toggle
                Toggle(isOn: $prefs.enableSmartNudges) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("pref_nudges_title"))
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundColor(PirateTheme.parchment)
                        Text(t("pref_nudges_desc"))
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(PirateTheme.parchment.opacity(0.6))
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(PirateTheme.darkWood.opacity(0.4))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
                )
                
                // AI Visual Productivity Check Toggle
                Toggle(isOn: $prefs.enableImageClassification) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("pref_image_model_title"))
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundColor(PirateTheme.parchment)
                        Text(t("pref_image_model_desc"))
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(PirateTheme.parchment.opacity(0.6))
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(PirateTheme.darkWood.opacity(0.4))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
                )
                
                // Nested Gemma 3 270M Toggle if Image Classification is Enabled
                if prefs.enableImageClassification {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $prefs.useLocalGemma) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("pref_use_gemma_title"))
                                    .font(.system(size: 12, weight: .semibold, design: .serif))
                                    .foregroundColor(PirateTheme.parchment)
                                Text(t("pref_use_gemma_desc"))
                                    .font(.system(size: 10, design: .serif))
                                    .foregroundColor(PirateTheme.parchment.opacity(0.6))
                            }
                        }
                        .toggleStyle(.checkbox)
                        
                        if prefs.useLocalGemma {
                            HStack(spacing: 12) {
                                Button(action: {
                                    prefs.downloadGemmaModel()
                                }) {
                                    Text(t(prefs.gemmaDownloadStatus))
                                        .font(.system(size: 11, weight: .bold, design: .serif))
                                        .foregroundColor(PirateTheme.darkWood)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(PirateTheme.gold)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .disabled(prefs.gemmaDownloadStatus == "Downloading..." || prefs.gemmaDownloadStatus == "Installing mlx-lm..." || prefs.gemmaDownloadStatus == "Downloaded")
                                
                                if prefs.gemmaDownloadStatus == "Downloading..." || prefs.gemmaDownloadStatus == "Installing mlx-lm..." {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 16, height: 16)
                                }
                            }
                            .padding(.leading, 24)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(PirateTheme.darkWood.opacity(0.2))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(PirateTheme.gold.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.leading, 16)
                }
                
                // Launch at Login Toggle
                Toggle(isOn: $prefs.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("pref_launch_title"))
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundColor(PirateTheme.parchment)
                        Text(t("pref_launch_desc"))
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(PirateTheme.parchment.opacity(0.6))
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(PirateTheme.darkWood.opacity(0.4))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

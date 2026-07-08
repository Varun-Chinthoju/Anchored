import SwiftUI

struct PermissionStepView: View {
    let windowHeight: CGFloat
    let onNext: () -> Void
    
    @State private var isGranted = AXIsProcessTrusted()
    @ObservedObject private var langManager = LanguageManager.shared
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Details)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(PirateTheme.gold.opacity(0.10))
                        .frame(width: 80, height: 80)
                    
                    SafeSystemImage(systemName: "scope", size: 32)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: t("perm_title"),
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    
                    Text(t("perm_desc"))
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        .lineSpacing(4)
                }
                
                Spacer()
            }
            .frame(width: 320, alignment: .leading)
            
            // Right Column (Interactive Permissions Card)
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 20) {
                    // Status Badge Icon
                    ZStack {
                        Circle()
                            .fill(isGranted ? PirateTheme.gold.opacity(0.12) : PirateTheme.bronze.opacity(0.10))
                            .frame(width: 90, height: 90)
                        
                        SafeSystemImage(systemName: isGranted ? "checkmark.seal.fill" : "lock.fill", size: 40, color: isGranted ? PirateTheme.gold : PirateTheme.bronze)
                            .shadow(color: (isGranted ? PirateTheme.gold : PirateTheme.bronze).opacity(0.3), radius: 8)
                    }
                    
                    VStack(spacing: 8) {
                        Text(isGranted ? t("perm_status_unlocked") : t("perm_status_locked"))
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundColor(isGranted ? PirateTheme.gold : PirateTheme.bronze)
                        
                        Text(isGranted ? 
                             "Ye've unlocked full browser domain and window title monitoring!" :
                             "Enable Accessibility in macOS System Settings so we can monitor browser domains.")
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(PirateTheme.parchment.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                        
                        if !isGranted {
                            Text(t("perm_warning"))
                                .font(.system(size: 11, design: .serif))
                                .foregroundColor(PirateTheme.bronze.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 24)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .background(PirateTheme.darkWood.opacity(0.45))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isGranted ? PirateTheme.gold.opacity(0.25) : PirateTheme.gold.opacity(0.12), lineWidth: 1.5)
                )
                
                // Action Buttons
                VStack(spacing: 12) {
                    if isGranted {
                        // Continue Voyage
                        Button(action: {
                            AudioEngine.shared.play(.tick)
                            onNext()
                        }) {
                            HStack {
                                Text(t("perm_btn_continue"))
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundColor(PirateTheme.darkWood)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                            .shadow(color: PirateTheme.gold.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Grant Permission Button
                        Button(action: {
                            AudioEngine.shared.play(.tick)
                            triggerPermissionRequest()
                        }) {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                Text(t("perm_btn_grant"))
                            }
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundColor(PirateTheme.darkWood)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                            .shadow(color: PirateTheme.gold.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(.plain)
                        
                        // Skip Bypass Button
                        Button(action: {
                            AudioEngine.shared.play(.tick)
                            onNext()
                        }) {
                        Text("Skip For Now (Distraction site detection will be disabled)")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundColor(PirateTheme.parchment.opacity(0.5))
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(300, windowHeight - 280))
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            isGranted = AXIsProcessTrusted()
        }
    }
    
    private func triggerPermissionRequest() {
        // Trigger Accessibility system option prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Open Settings directly to Accessibility panel as fallback
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

import AppKit
import SwiftUI

struct PermissionStepView: View {
    let windowHeight: CGFloat
    let onNext: () -> Void
    
    @State private var isAXGranted = AXIsProcessTrusted()
    @State private var isScreenGranted = CGPreflightScreenCaptureAccess()
    @ObservedObject private var langManager = LanguageManager.shared
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Details)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(PirateTheme.gold.opacity(0.12))
                        .frame(width: 80, height: 80)
                    
                    SafeSystemImage(systemName: "scope", size: 32)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: t("perm_title"),
                        font: .system(size: 32, weight: .semibold, design: .rounded),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    
                    Text("Enable permissions to unlock URL-level awareness and local visual AI check capabilities. All data stays 100% private on your device.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        .lineSpacing(3)
                }
                
                Spacer()
            }
            .frame(width: 320, alignment: .leading)
            
            // Right Column (Interactive Permissions Card)
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 16) {
                    // Accessibility Row
                    HStack(spacing: 16) {
                        Image(systemName: isAXGranted ? "checkmark.circle.fill" : "lock.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(isAXGranted ? PirateTheme.gold : PirateTheme.bronze)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility Permission")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(PirateTheme.parchment)
                            Text("Detects browser tabs and distraction URLs.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(PirateTheme.parchment.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        if !isAXGranted {
                            Button(action: {
                                AudioEngine.shared.play(.tick)
                                triggerAXRequest()
                            }) {
                                Text("Enable")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(PirateTheme.darkWood)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(PirateTheme.gold)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Enabled")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(PirateTheme.gold)
                        }
                    }
                    .padding(16)
                    .background(PirateTheme.darkWood.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isAXGranted ? PirateTheme.gold.opacity(0.2) : PirateTheme.gold.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    
                    // Screen Recording Row
                    HStack(spacing: 16) {
                        Image(systemName: isScreenGranted ? "checkmark.circle.fill" : "lock.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(isScreenGranted ? PirateTheme.gold : PirateTheme.bronze)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Screen Recording Permission")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(PirateTheme.parchment)
                            Text("Enables local visual checks (AI and Vision fallbacks).")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(PirateTheme.parchment.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        if !isScreenGranted {
                            Button(action: {
                                AudioEngine.shared.play(.tick)
                                triggerScreenRequest()
                            }) {
                                Text("Enable")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(PirateTheme.darkWood)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(PirateTheme.gold)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Enabled")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(PirateTheme.gold)
                        }
                    }
                    .padding(16)
                    .background(PirateTheme.darkWood.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isScreenGranted ? PirateTheme.gold.opacity(0.2) : PirateTheme.gold.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(PirateTheme.darkWood.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                // Action Buttons
                VStack(spacing: 12) {
                    if isAXGranted && isScreenGranted {
                        // Continue Voyage
                        Button(action: {
                            AudioEngine.shared.play(.tick)
                            onNext()
                        }) {
                            HStack {
                                Text(t("perm_btn_continue"))
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                        // Skip Bypass Button
                        Button(action: {
                            AudioEngine.shared.play(.tick)
                            onNext()
                        }) {
                            Text("Skip For Now (AI and browser distraction checking will be limited)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(PirateTheme.parchment.opacity(0.5))
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "power")
                            Text("Quit Anchored")
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(PirateTheme.parchment.opacity(0.72))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help("Quit so you can finish granting macOS permissions, then reopen Anchored.")
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(300, windowHeight - 280))
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            isAXGranted = AXIsProcessTrusted()
            isScreenGranted = CGPreflightScreenCaptureAccess()
        }
    }
    
    private func triggerAXRequest() {
        // Trigger Accessibility system option prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Open Settings directly to Accessibility panel as fallback
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
    
    private func triggerScreenRequest() {
        _ = CGRequestScreenCaptureAccess()
    }
}

import SwiftUI

public struct PermissionGateView: View {
    let onGrant: () -> Void
    let onDismiss: () -> Void
    @ObservedObject private var langManager = LanguageManager.shared
    
    private var themeAccent: Color {
        PirateTheme.gold
    }

    private var themeSurface: Color {
        PirateTheme.surface
    }

    private var themeSurfaceElevated: Color {
        PirateTheme.surfaceRaised
    }

    private var themeTextPrimary: Color {
        PirateTheme.textPrimary
    }

    private var themeTextSecondary: Color {
        PirateTheme.textSecondary
    }
    
    @State private var isPresented = false
    
    public init(onGrant: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onGrant = onGrant
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                // Spyglass/Anchor icon
                Image(systemName: "scope")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(themeAccent)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(langManager.translate("perm_gate_title"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(themeAccent)
                    
                    Text(langManager.translate("perm_gate_desc"))
                        .font(.system(size: 13))
                        .foregroundColor(themeTextPrimary.opacity(0.85))
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack {
                Button(action: onDismiss) {
                    Text(langManager.translate("perm_gate_later"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeTextSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(themeSurface.opacity(0.22))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(themeAccent.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
            Button(action: onGrant) {
                    Text(langManager.translate("perm_btn_grant"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(themeSurface)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(themeAccent)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                    Text(langManager.translate("onboarding_quit"))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(themeTextSecondary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help(langManager.translate("onboarding_quit"))
        }
        .padding(24)
        .frame(width: 480)
        .background(
            ControlRoomShellBackground(palette: PreferencesManager.shared.selectedThemePalette)
                .cornerRadius(12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeAccent.opacity(0.3), lineWidth: 1.5)
        )
        .scaleEffect(isPresented ? 1.0 : 0.8)
        .opacity(isPresented ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                isPresented = true
            }
        }
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
}

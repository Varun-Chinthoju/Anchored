import SwiftUI

public struct ExitTriggerView: View {
    let formattedDuration: String
    let appName: String
    let onAnchor: (TimeInterval) -> Void
    let onDismiss: () -> Void
    
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
    
    public init(
        formattedDuration: String,
        appName: String,
        onAnchor: @escaping (TimeInterval) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.formattedDuration = formattedDuration
        self.appName = appName
        self.onAnchor = onAnchor
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start a focus session?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(themeAccent)
                
                Text("You have been focused in \(appName) for \(formattedDuration).")
                    .font(.system(size: 13))
                    .foregroundColor(themeTextPrimary.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack {
                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeTextPrimary.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(themeSurfaceElevated.opacity(0.35))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(themeAccent.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: { onAnchor(900) }) {
                        Text("15 min")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(themeTextPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(themeSurface.opacity(0.35))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(themeAccent.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { onAnchor(1500) }) {
                        Text("25 min")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(themeTextPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(themeSurface.opacity(0.35))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(themeAccent.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { onAnchor(2700) }) {
                        Text("45 min")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(themeSurface)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(themeAccent)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(
            ControlRoomShellBackground(palette: PreferencesManager.shared.selectedThemePalette)
                .cornerRadius(12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeAccent.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
    }
}

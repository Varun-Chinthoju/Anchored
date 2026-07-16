import SwiftUI

struct WelcomeStepView: View {
    let onNext: () -> Void
    @ObservedObject private var langManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(PirateTheme.darkWood.opacity(0.52))
                    .frame(width: 146, height: 146)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(PirateTheme.gold.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
                
                SafeSystemImage(systemName: "compass.fill", size: 54)
                    .shadow(color: PirateTheme.darkGold.opacity(0.34), radius: 10, x: 0, y: 4)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 12) {
                GlowingText(
                    text: langManager.translate("welcome_title"),
                    font: .system(size: 34, weight: .semibold, design: .rounded),
                    colors: [PirateTheme.gold, PirateTheme.parchment]
                )
                
                Text(langManager.translate("welcome_desc"))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(PirateTheme.parchment.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 500)
            }
            
            Spacer()
            
            Button(action: {
                AudioEngine.shared.play(.tick)
                onNext()
            }) {
                Text(langManager.translate("welcome_btn"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PirateTheme.darkWood)
                    .frame(width: 280)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: PirateTheme.gold.opacity(0.18), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            
            Spacer()
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

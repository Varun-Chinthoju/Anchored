import SwiftUI

struct HowItWorksStepView: View {
    let onNext: () -> Void
    @ObservedObject private var langManager = LanguageManager.shared
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Concept Introduction)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(PirateTheme.gold.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    SafeSystemImage(systemName: "compass.fill", size: 32)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: t("how_title"),
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    
                    Text(t("how_left_desc"))
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(PirateTheme.parchment.opacity(0.8))
                        .lineSpacing(4)
                }
                
                Spacer()
                
                Button(action: {
                    AudioEngine.shared.play(.tick)
                    onNext()
                }) {
                    HStack {
                        Text(t("how_btn"))
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
                    .shadow(color: PirateTheme.gold.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 320, alignment: .leading)
            
            // Right Column (Step-by-step Cards)
            VStack(spacing: 16) {
                FeatureCard(
                    icon: "binoculars.fill",
                    title: t("how_card1_title"),
                    description: t("how_desc1"),
                    accentColor: PirateTheme.gold
                )
                
                FeatureCard(
                    icon: "anchor",
                    title: t("how_card2_title"),
                    description: t("how_desc2"),
                    accentColor: PirateTheme.gold
                )
                
                FeatureCard(
                    icon: "eye.slash.fill",
                    title: t("how_card3_title"),
                    description: t("how_desc3"),
                    accentColor: PirateTheme.gold
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                SafeSystemImage(systemName: icon, size: 18, color: accentColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(PirateTheme.parchment)
                Text(description)
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundColor(PirateTheme.parchment.opacity(0.7))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
        .background(PirateTheme.darkWood.opacity(0.4))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PirateTheme.gold.opacity(0.2), lineWidth: 1)
        )
    }
}

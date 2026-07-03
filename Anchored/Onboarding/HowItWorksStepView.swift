import SwiftUI

struct HowItWorksStepView: View {
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Concept Introduction)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(PirateTheme.gold.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "compass.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [PirateTheme.gold, PirateTheme.darkGold]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: "Chart Your\nCourse",
                        font: .system(size: 36, weight: .bold, design: .serif),
                        colors: [PirateTheme.gold, PirateTheme.parchment]
                    )
                    
                    Text("Anchored operates quietly like a trusted navigator, tracking your progress and shielding your attention during your voyage.")
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
                        Text("Chart the Course")
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
                    title: "1. Passive Lookout",
                    description: "Our watchman silently monitors your active app and browser domain in the background. No manual buttons needed.",
                    accentColor: PirateTheme.gold
                )
                
                FeatureCard(
                    icon: "anchor",
                    title: "2. Drop the Anchor",
                    description: "If you wander to a distracting site after deep work, you'll be prompted to drop anchor and lock in a session.",
                    accentColor: PirateTheme.gold
                )
                
                FeatureCard(
                    icon: "eye.slash.fill",
                    title: "3. Ocean Fog (Dimming)",
                    description: "Straying into forbidden waters during a session causes a heavy dimming fog to roll in until you steer back to work.",
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
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accentColor)
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

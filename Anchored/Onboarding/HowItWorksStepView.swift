import SwiftUI

struct HowItWorksStepView: View {
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 64) {
            // Left Column (Concept Introduction)
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    GlowingText(
                        text: "Protecting\nYour Focus",
                        font: .system(size: 36, weight: .bold, design: .rounded),
                        colors: [.blue, .purple]
                    )
                    
                    Text("Anchored operates quietly in the background, matching your working pace and blocking notifications when you lock in.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                
                Spacer()
                
                Button(action: {
                    AudioEngine.shared.play(.tick)
                    onNext()
                }) {
                    HStack {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 320, alignment: .leading)
            
            // Right Column (Step-by-step Cards)
            VStack(spacing: 16) {
                FeatureCard(
                    icon: "sparkles",
                    title: "1. Passive Focus Tracking",
                    description: "Anchored silently watches your active window in the background. No start/stop buttons needed.",
                    accentColor: .blue
                )
                
                FeatureCard(
                    icon: "anchor",
                    title: "2. Momentum Anchors",
                    description: "When you switch to a distraction app after focused work, you are prompted to lock in a dedicated block.",
                    accentColor: .purple
                )
                
                FeatureCard(
                    icon: "eye.slash.fill",
                    title: "3. Ambient Escalation",
                    description: "If you stray to distracted apps during a session, your screen dims to gently guide you back to work.",
                    accentColor: .pink
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

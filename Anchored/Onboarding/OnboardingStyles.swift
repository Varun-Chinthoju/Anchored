import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            // Dark ocean base canvas
            Color(red: 0.04, green: 0.05, blue: 0.07)
                .edgesIgnoringSafeArea(.all)
            
            // Glowing ambient gold and teal circles
            GeometryReader { geo in
                ZStack {
                    // Gold glow (top left)
                    Circle()
                        .fill(Color(red: 0.9, green: 0.75, blue: 0.3).opacity(0.08))
                        .frame(width: 550, height: 550)
                        .blur(radius: 100)
                        .position(x: 100, y: 100)
                    
                    // Deep Teal/Aqua glow (bottom right)
                    Circle()
                        .fill(Color(red: 0.0, green: 0.4, blue: 0.5).opacity(0.1))
                        .frame(width: 600, height: 600)
                        .blur(radius: 110)
                        .position(x: geo.size.width - 150, y: geo.size.height - 150)
                    
                    // Warm Bronze/Amber glow (center right)
                    Circle()
                        .fill(Color(red: 0.6, green: 0.4, blue: 0.1).opacity(0.07))
                        .frame(width: 450, height: 450)
                        .blur(radius: 90)
                        .position(x: geo.size.width - 250, y: 250)
                }
            }
        }
    }
}

// Glowing text component styled for the pirate theme
struct GlowingText: View {
    let text: String
    let font: Font
    let colors: [Color]
    
    var body: some View {
        Text(text)
            .font(font)
            .bold()
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 8, x: 0, y: 0)
    }
}

// Global pirate theme colors
struct PirateTheme {
    static let gold = Color(red: 0.9, green: 0.75, blue: 0.3)
    static let darkGold = Color(red: 0.75, green: 0.6, blue: 0.2)
    static let parchment = Color(red: 0.95, green: 0.95, blue: 0.9)
    static let darkWood = Color(red: 0.12, green: 0.09, blue: 0.07)
    static let deepBlue = Color(red: 0.05, green: 0.15, blue: 0.25)
}

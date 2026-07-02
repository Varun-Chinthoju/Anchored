import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            // Dark base canvas
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .edgesIgnoringSafeArea(.all)
            
            // Glowing ambient circles (neon green, red, blue, pink)
            GeometryReader { geo in
                ZStack {
                    // Blue glow
                    Circle()
                        .fill(Color(red: 0.1, green: 0.4, blue: 0.9).opacity(0.12))
                        .frame(width: 500, height: 500)
                        .blur(radius: 90)
                        .position(x: 100, y: 150)
                    
                    // Pink glow
                    Circle()
                        .fill(Color(red: 0.9, green: 0.2, blue: 0.6).opacity(0.1))
                        .frame(width: 500, height: 500)
                        .blur(radius: 90)
                        .position(x: geo.size.width - 150, y: geo.size.height - 150)
                    
                    // Green glow
                    Circle()
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.07))
                        .frame(width: 450, height: 450)
                        .blur(radius: 85)
                        .position(x: geo.size.width - 250, y: 200)
                    
                    // Red glow
                    Circle()
                        .fill(Color(red: 0.95, green: 0.15, blue: 0.25).opacity(0.06))
                        .frame(width: 400, height: 400)
                        .blur(radius: 80)
                        .position(x: 250, y: geo.size.height - 200)
                }
            }
        }
    }
}

// Glowing text component
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
            .shadow(color: colors.first?.opacity(0.3) ?? .clear, radius: 10, x: 0, y: 0)
    }
}

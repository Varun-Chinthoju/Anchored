import SwiftUI

public struct CountdownPillView: View {
    let secondsRemaining: Int
    
    public init(secondsRemaining: Int) {
        self.secondsRemaining = secondsRemaining
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Pulsing gold indicator dot
            Circle()
                .fill(Color(red: 0.9, green: 0.75, blue: 0.3))
                .frame(width: 8, height: 8)
                .shadow(color: Color(red: 0.9, green: 0.75, blue: 0.3).opacity(0.8), radius: 4)
            
            Text("Plundering…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            
            Text("Sirens in \(secondsRemaining)s")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.9, green: 0.75, blue: 0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(red: 0.08, green: 0.07, blue: 0.06).opacity(0.85))
                .background(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.9, green: 0.75, blue: 0.3).opacity(0.4), Color(red: 0.9, green: 0.75, blue: 0.3).opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

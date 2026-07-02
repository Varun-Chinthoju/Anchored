import SwiftUI

public struct CountdownPillView: View {
    let secondsRemaining: Int
    
    public init(secondsRemaining: Int) {
        self.secondsRemaining = secondsRemaining
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Pulsing orange/amber indicator dot
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: Color.orange.opacity(0.8), radius: 4)
            
            Text("Focusing…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            
            Text("Dimming in \(secondsRemaining)s")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

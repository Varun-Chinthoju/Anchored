import SwiftUI

public struct EndSessionButton: View {
    public var onEndSession: () -> Void
    @State private var isHovered = false
    @State private var isButtonHovered = false
    
    public init(onEndSession: @escaping () -> Void) {
        self.onEndSession = onEndSession
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("⚓")
                    .font(.system(size: 14))
                Text("Anchored")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .opacity(0.9)
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))
            
            Button(action: onEndSession) {
                Text("End Session")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: isButtonHovered ? [Color.red.opacity(0.8), Color.orange.opacity(0.8)] : [Color.red.opacity(0.6), Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.red.opacity(0.3), radius: isButtonHovered ? 6 : 2, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isButtonHovered = hovering
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.4))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}

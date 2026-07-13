import SwiftUI

public struct CountdownPillView: View {
    let secondsRemaining: Int
    let isDimmed: Bool
    let onBreak: (() -> Void)?
    
    public init(secondsRemaining: Int, isDimmed: Bool = false, onBreak: (() -> Void)? = nil) {
        self.secondsRemaining = secondsRemaining
        self.isDimmed = isDimmed
        self.onBreak = onBreak
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Pulsing gold indicator dot
            Circle()
                .fill(PirateTheme.gold)
                .frame(width: 8, height: 8)
                .shadow(color: PirateTheme.gold.opacity(0.8), radius: 4)
            
            Text(isDimmed ? "Screen dimmed" : "Plundering…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(PirateTheme.parchment.opacity(0.8))
            
            if !isDimmed {
                Text("Sirens in \(secondsRemaining)s")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(PirateTheme.gold)
            }

            if let onBreak {
                Button("Break") {
                    onBreak()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(PirateTheme.gold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(PirateTheme.darkWood.opacity(0.85))
                .background(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [PirateTheme.gold.opacity(0.4), PirateTheme.gold.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

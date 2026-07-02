import SwiftUI

public struct ExitTriggerView: View {
    let formattedDuration: String
    let appName: String
    let onAnchor: (TimeInterval) -> Void
    let onDismiss: () -> Void
    
    // Pirate colors
    private let goldColor = Color(red: 0.9, green: 0.75, blue: 0.3)
    private let parchmentWhite = Color(red: 0.95, green: 0.95, blue: 0.9)
    private let darkWood = Color(red: 0.12, green: 0.09, blue: 0.07)
    
    public init(
        formattedDuration: String,
        appName: String,
        onAnchor: @escaping (TimeInterval) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.formattedDuration = formattedDuration
        self.appName = appName
        self.onAnchor = onAnchor
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hold Fast Yer Momentum!")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(goldColor)
                
                Text("Ye just logged \(formattedDuration) of focus plunder in \(appName). Will ye guard this treasure?")
                    .font(.system(size: 13))
                    .foregroundColor(parchmentWhite.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack {
                Button(action: onDismiss) {
                    Text("Adrift (Take a Break)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(parchmentWhite.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.25))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: { onAnchor(900) }) {
                        Text("15 Bells")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(parchmentWhite)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(goldColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { onAnchor(1500) }) {
                        Text("25 Bells")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(parchmentWhite)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(goldColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { onAnchor(2700) }) {
                        Text("45 Bells")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(darkWood)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(goldColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.12, blue: 0.1), Color(red: 0.08, green: 0.07, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .cornerRadius(12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(goldColor.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
    }
}

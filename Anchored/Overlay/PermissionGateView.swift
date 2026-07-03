import SwiftUI

public struct PermissionGateView: View {
    let onGrant: () -> Void
    let onDismiss: () -> Void
    
    // Pirate colors
    private let goldColor = Color(red: 0.9, green: 0.75, blue: 0.3)
    private let parchmentWhite = Color(red: 0.95, green: 0.95, blue: 0.9)
    private let darkWood = Color(red: 0.12, green: 0.09, blue: 0.07)
    
    @State private var isPresented = false
    
    public init(onGrant: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onGrant = onGrant
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                // Spyglass/Anchor icon
                Image(systemName: "scope")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(goldColor)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unlock the Spyglass!")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(goldColor)
                    
                    Text("Ye've completed 10 successful voyages! To unlock URL-level awareness inside browsers (Safari, Chrome, Arc, Edge, Brave, Firefox) and detect distraction sites like YouTube and Reddit, grant us Accessibility permissions.")
                        .font(.system(size: 13))
                        .foregroundColor(parchmentWhite.opacity(0.85))
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack {
                Button(action: onDismiss) {
                    Text("Maybe Later")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(parchmentWhite.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: onGrant) {
                    Text("Grant Spyglass Access")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(darkWood)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(goldColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
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
        .scaleEffect(isPresented ? 1.0 : 0.8)
        .opacity(isPresented ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                isPresented = true
            }
        }
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
}

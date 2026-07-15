import SwiftUI

enum ControlRoomTheme {
    static let main = Color(hex: 0x2A2522)
    static let tile = Color(hex: 0x403A35)
    static let shellTop = Color(hex: 0x332E2A)
    static let shellMid = main
    static let shellBottom = Color(hex: 0x211E1C)
    static let cardTop = tile
    static let cardBottom = Color(hex: 0x34302C)
    static let footer = Color(hex: 0x302C29)
}

struct ControlRoomShellBackground: View {
    let palette: ThemePalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ControlRoomTheme.shellTop,
                    ControlRoomTheme.shellMid,
                    ControlRoomTheme.shellBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.accentColor.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: 250, y: -240)

            Circle()
                .fill(palette.bronzeColor.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -260, y: 240)
        }
        .ignoresSafeArea()
    }
}

struct ControlRoomCard<Content: View>: View {
    let title: String
    let subtitle: String
    let palette: ThemePalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(palette.textPrimaryColor)
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(palette.textSecondaryColor)
            }

            content()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    ControlRoomTheme.cardTop,
                    ControlRoomTheme.cardBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(palette.borderColor.opacity(0.9), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct ControlRoomFooterStrip: View {
    let palette: ThemePalette
    let activeSession: ActiveSession?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "anchor")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(palette.accentColor)
            Text("Everything is stored locally on your Mac")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
            Spacer()
            if let session = activeSession {
                Label(session.displayName, systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.textPrimaryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ControlRoomTheme.footer.opacity(0.78))
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

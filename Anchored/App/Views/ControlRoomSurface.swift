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
                    Color(hex: 0x231F1D),
                    ControlRoomTheme.shellMid,
                    Color(hex: 0x171412)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.accentColor.opacity(0.08))
                .frame(width: 460, height: 460)
                .blur(radius: 88)
                .offset(x: 260, y: -260)

            Circle()
                .fill(palette.bronzeColor.opacity(0.06))
                .frame(width: 340, height: 340)
                .blur(radius: 84)
                .offset(x: -260, y: 220)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.14),
                    Color.clear,
                    Color.black.opacity(0.26)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.multiply)
        }
        .ignoresSafeArea()
    }
}

struct ControlRoomSectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(accent.opacity(0.78))
                Rectangle()
                    .fill(accent.opacity(0.28))
                    .frame(height: 1)
            }

            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ControlRoomCard<Content: View>: View {
    let title: String
    let subtitle: String
    let palette: ThemePalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(palette.accentColor.opacity(0.8))
                        .frame(width: 24, height: 4)
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(palette.textSecondaryColor)
                }
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(palette.textSecondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    ControlRoomTheme.cardTop.opacity(0.98),
                    ControlRoomTheme.cardBottom.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.borderColor.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
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
            Text("Everything is stored locally on this Mac")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
            Spacer()
            if let session = activeSession {
                HStack(spacing: 6) {
                    Circle()
                        .fill(palette.accentColor)
                        .frame(width: 7, height: 7)
                    Text(session.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.textPrimaryColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ControlRoomTheme.footer.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.borderColor.opacity(0.55), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

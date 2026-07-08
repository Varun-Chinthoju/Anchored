import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PirateTheme.canvas,
                    PirateTheme.surface.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            // Glowing ambient layers tied to the active theme.
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(PirateTheme.ambientGlow.opacity(0.75))
                        .frame(width: 550, height: 550)
                        .blur(radius: 100)
                        .position(x: 100, y: 100)

                    Circle()
                        .fill(PirateTheme.surfaceRaised.opacity(0.45))
                        .frame(width: 600, height: 600)
                        .blur(radius: 110)
                        .position(x: geo.size.width - 150, y: geo.size.height - 150)

                    Circle()
                        .fill(PirateTheme.surfaceSubtle.opacity(0.8))
                        .frame(width: 450, height: 450)
                        .blur(radius: 90)
                        .position(x: geo.size.width - 250, y: 250)
                }
            }
        }
    }
}

// Safe system image loader for transparent AppKit hosted SwiftUI views
struct SafeSystemImage: View {
    let systemName: String
    let size: CGFloat
    var color: Color = PirateTheme.gold
    
    var body: some View {
        if let symbolName = resolvedSystemName(),
           let nsImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(color)
        } else {
            Image(systemName: "circle.hexagongrid.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(color)
        }
    }

    private func resolvedSystemName() -> String? {
        symbolCandidates(for: systemName).first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
    }

    private func symbolCandidates(for systemName: String) -> [String] {
        switch systemName {
        case "compass.fill":
            return ["safari.fill", "location.north.fill", "location.north.line.fill"]
        case "binoculars.fill":
            return ["eye.fill", "eye.circle.fill", "scope"]
        case "shield.fill":
            return ["checkmark.shield.fill", "shield.lefthalf.filled", "shield"]
        case "eye.slash.fill":
            return ["eye.slash", "eye.trianglebadge.exclamationmark", "moon.stars.fill"]
        default:
            return [systemName]
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

// Shared theme colors backed by the selected appearance palette.
struct PirateTheme {
    private static var palette: ThemePalette {
        PreferencesManager.shared.selectedThemePalette
    }

    static var gold: Color {
        palette.accentColor
    }

    static var darkGold: Color {
        palette.accentShadowColor
    }

    static var parchment: Color {
        palette.parchmentColor
    }

    static var darkWood: Color {
        palette.darkWoodColor
    }

    static var deepBlue: Color {
        palette.deepBlueColor
    }

    static var seaFoam: Color {
        palette.seaFoamColor
    }

    static var bronze: Color {
        palette.bronzeColor
    }

    static var canvas: Color {
        palette.canvasColor
    }

    static var ambientGlow: Color {
        palette.ambientGlowColor
    }

    static var surface: Color {
        palette.surfaceColor
    }

    static var surfaceRaised: Color {
        palette.surfaceRaisedColor
    }

    static var surfaceSubtle: Color {
        palette.surfaceSubtleColor
    }

    static var border: Color {
        palette.borderColor
    }

    static var separator: Color {
        palette.separatorColor
    }

    static var meterTrack: Color {
        palette.meterTrackColor
    }

    static var textPrimary: Color {
        palette.textPrimaryColor
    }

    static var textSecondary: Color {
        palette.textSecondaryColor
    }
}

import SwiftUI
import AppKit

public struct ThemeColorStop: Equatable, Identifiable {
    public let hex: UInt32

    public var id: UInt32 { hex }

    public init(_ hex: UInt32) {
        self.hex = hex
    }

    public var color: Color {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    public var nsColor: NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }
}

public struct ThemeGradient: Equatable {
    public let stops: [ThemeColorStop]

    public init(_ stops: [ThemeColorStop]) {
        self.stops = stops
    }

    public var colors: [Color] {
        stops.map(\.color)
    }
}

public struct ThemePalette: Equatable {
    public let accent: ThemeColorStop
    public let accentShadow: ThemeColorStop
    public let parchment: ThemeColorStop
    public let darkWood: ThemeColorStop
    public let deepBlue: ThemeColorStop
    public let seaFoam: ThemeColorStop
    public let bronze: ThemeColorStop

    public init(
        accent: ThemeColorStop,
        accentShadow: ThemeColorStop,
        parchment: ThemeColorStop,
        darkWood: ThemeColorStop,
        deepBlue: ThemeColorStop,
        seaFoam: ThemeColorStop,
        bronze: ThemeColorStop
    ) {
        self.accent = accent
        self.accentShadow = accentShadow
        self.parchment = parchment
        self.darkWood = darkWood
        self.deepBlue = deepBlue
        self.seaFoam = seaFoam
        self.bronze = bronze
    }

    public init(theme: AppTheme) {
        if theme.id == ThemeCatalog.defaultThemeID {
            self = .baldr
            return
        }

        let primary = theme.primary.stops
        let secondary = theme.secondary.stops

        self.accent = primary.first ?? Self.baldr.accent
        self.accentShadow = primary.last ?? self.accent
        self.parchment = Self.baldr.parchment
        self.darkWood = secondary.first ?? Self.baldr.darkWood
        self.deepBlue = secondary.last ?? Self.baldr.deepBlue
        self.seaFoam = primary.last ?? Self.baldr.seaFoam
        self.bronze = secondary.last ?? Self.baldr.bronze
    }

    public var accentColor: Color { accent.color }
    public var accentShadowColor: Color { accentShadow.color }
    public var parchmentColor: Color { parchment.color }
    public var darkWoodColor: Color { darkWood.color }
    public var deepBlueColor: Color { deepBlue.color }
    public var seaFoamColor: Color { seaFoam.color }
    public var bronzeColor: Color { bronze.color }

    public var canvasColor: Color {
        canvasStop.color
    }

    public var ambientGlowColor: Color {
        Self.mix(canvasStop, accent, amount: prefersLightCanvas ? 0.18 : 0.26).color.opacity(prefersLightCanvas ? 0.28 : 0.34)
    }

    public var surfaceColor: Color {
        surfaceStop.color
    }

    public var surfaceRaisedColor: Color {
        surfaceRaisedStop.color
    }

    public var surfaceSubtleColor: Color {
        surfaceSubtleStop.color
    }

    public var borderColor: Color {
        borderStop.color.opacity(prefersLightCanvas ? 0.72 : 0.88)
    }

    public var separatorColor: Color {
        separatorStop.color.opacity(prefersLightCanvas ? 0.55 : 0.30)
    }

    public var meterTrackColor: Color {
        prefersLightCanvas ? Color.black.opacity(0.10) : Color.white.opacity(0.08)
    }

    public var textPrimaryColor: Color {
        prefersLightCanvas ? Color.black.opacity(0.88) : Color.white.opacity(0.95)
    }

    public var textSecondaryColor: Color {
        prefersLightCanvas ? Color.black.opacity(0.62) : Color.white.opacity(0.70)
    }

    private var prefersLightCanvas: Bool {
        averageLuminance > 0.58
    }

    private var averageLuminance: Double {
        let samples = [accent, accentShadow, parchment, darkWood, deepBlue, seaFoam, bronze]
        let total = samples.reduce(0.0) { partial, sample in
            partial + Self.luminance(of: sample)
        }
        return total / Double(samples.count)
    }

    private var canvasStop: ThemeColorStop {
        if prefersLightCanvas {
            let warmBase = Self.mix(Self.lightCanvasBase, parchment, amount: 0.22)
            return Self.mix(warmBase, accent, amount: 0.10)
        }

        let darkBase = Self.mix(Self.darkCanvasBase, deepBlue, amount: 0.30)
        return Self.mix(darkBase, accentShadow, amount: 0.18)
    }

    private var surfaceStop: ThemeColorStop {
        if prefersLightCanvas {
            return Self.mix(canvasStop, darkWood, amount: 0.10)
        }

        return Self.mix(canvasStop, accentShadow, amount: 0.14)
    }

    private var surfaceRaisedStop: ThemeColorStop {
        if prefersLightCanvas {
            return Self.mix(canvasStop, accentShadow, amount: 0.14)
        }

        return Self.mix(canvasStop, accent, amount: 0.18)
    }

    private var surfaceSubtleStop: ThemeColorStop {
        if prefersLightCanvas {
            return Self.mix(canvasStop, accent, amount: 0.08)
        }

        return Self.mix(canvasStop, accent, amount: 0.12)
    }

    private var borderStop: ThemeColorStop {
        Self.mix(surfaceStop, accentShadow, amount: prefersLightCanvas ? 0.18 : 0.30)
    }

    private var separatorStop: ThemeColorStop {
        Self.mix(canvasStop, prefersLightCanvas ? darkWood : parchment, amount: prefersLightCanvas ? 0.14 : 0.10)
    }

    private static let lightCanvasBase = ThemeColorStop(0xF4EFE3)
    private static let darkCanvasBase = ThemeColorStop(0x2A2522)

    private static func mix(_ first: ThemeColorStop, _ second: ThemeColorStop, amount: Double) -> ThemeColorStop {
        let clamped = max(0.0, min(1.0, amount))
        let inverse = 1.0 - clamped

        let firstRed = Double((first.hex >> 16) & 0xFF)
        let firstGreen = Double((first.hex >> 8) & 0xFF)
        let firstBlue = Double(first.hex & 0xFF)

        let secondRed = Double((second.hex >> 16) & 0xFF)
        let secondGreen = Double((second.hex >> 8) & 0xFF)
        let secondBlue = Double(second.hex & 0xFF)

        let red = UInt32((firstRed * inverse + secondRed * clamped).rounded())
        let green = UInt32((firstGreen * inverse + secondGreen * clamped).rounded())
        let blue = UInt32((firstBlue * inverse + secondBlue * clamped).rounded())

        return ThemeColorStop((red << 16) | (green << 8) | blue)
    }

    private static func luminance(of stop: ThemeColorStop) -> Double {
        let color = stop.nsColor.usingColorSpace(.deviceRGB) ?? stop.nsColor
        return 0.2126 * Double(color.redComponent)
            + 0.7152 * Double(color.greenComponent)
            + 0.0722 * Double(color.blueComponent)
    }

    public static let baldr = ThemePalette(
        accent: ThemeColorStop(0xD8A64A),
        accentShadow: ThemeColorStop(0x9A7A3F),
        parchment: ThemeColorStop(0xF1E4CA),
        darkWood: ThemeColorStop(0x2A2522),
        deepBlue: ThemeColorStop(0x332E2A),
        seaFoam: ThemeColorStop(0x777064),
        bronze: ThemeColorStop(0xA47A3C)
    )
}

public struct AppTheme: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let summary: String
    public let primary: ThemeGradient
    public let secondary: ThemeGradient

    public init(
        id: String,
        name: String,
        summary: String,
        primary: ThemeGradient,
        secondary: ThemeGradient
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.primary = primary
        self.secondary = secondary
    }

    public var palette: ThemePalette {
        ThemePalette(theme: self)
    }
}

public enum ThemeCatalog {
    public static let defaultThemeID = "baldr"

    public static let all: [AppTheme] = [
        AppTheme(
            id: "odin",
            name: "Odin",
            summary: "Midnight command deck with an austere edge.",
            primary: ThemeGradient([ThemeColorStop(0x0D1B2A), ThemeColorStop(0x243B7A)]),
            secondary: ThemeGradient([ThemeColorStop(0x2B2D31), ThemeColorStop(0x0B0C10)])
        ),
        AppTheme(
            id: "thor",
            name: "Thor",
            summary: "Hard signal, bright impact, no hesitation.",
            primary: ThemeGradient([ThemeColorStop(0x9B1B30), ThemeColorStop(0xD72638)]),
            secondary: ThemeGradient([ThemeColorStop(0x555A61), ThemeColorStop(0x6B7280)])
        ),
        AppTheme(
            id: "loki",
            name: "Loki",
            summary: "Volatile green with a sharp warning glow.",
            primary: ThemeGradient([ThemeColorStop(0x2E8B57), ThemeColorStop(0x6B8E23)]),
            secondary: ThemeGradient([ThemeColorStop(0xD6C13A), ThemeColorStop(0x7A7465)])
        ),
        AppTheme(
            id: "heimdall",
            name: "Heimdall",
            summary: "Bright, prismatic, and impossible to miss.",
            primary: ThemeGradient([ThemeColorStop(0xF8F9FA), ThemeColorStop(0xD9DDE3)]),
            secondary: ThemeGradient([
                ThemeColorStop(0xFF5F6D),
                ThemeColorStop(0xFFC371),
                ThemeColorStop(0x47C7F4),
                ThemeColorStop(0x9B5DE5)
            ])
        ),
        AppTheme(
            id: "freyja",
            name: "Freyja",
            summary: "Warm, vivid tones with a polished sheen.",
            primary: ThemeGradient([ThemeColorStop(0xC98C7E), ThemeColorStop(0xFF6B6B)]),
            secondary: ThemeGradient([ThemeColorStop(0x7A5C8A), ThemeColorStop(0x4A235A)])
        ),
        AppTheme(
            id: "baldr",
            name: "Heritage",
            summary: "Dark smoked wood, muted brass, and warm parchment.",
            primary: ThemeGradient([ThemeColorStop(0xD8A64A), ThemeColorStop(0xF1E4CA)]),
            secondary: ThemeGradient([ThemeColorStop(0x2A2522), ThemeColorStop(0x4A433D)])
        ),
        AppTheme(
            id: "tyr",
            name: "Tyr",
            summary: "Steel-forward, disciplined, and grounded.",
            primary: ThemeGradient([ThemeColorStop(0xA7B0B8), ThemeColorStop(0x5B6770)]),
            secondary: ThemeGradient([ThemeColorStop(0x3B4652), ThemeColorStop(0x111827)])
        )
    ]

    public static func theme(for id: String) -> AppTheme {
        all.first(where: { $0.id == id }) ?? all.first(where: { $0.id == defaultThemeID }) ?? all[0]
    }

    public static func containsTheme(id: String) -> Bool {
        all.contains(where: { $0.id == id })
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}

import XCTest
import AppKit
import SwiftUI
@testable import Anchored

final class AppThemeTests: XCTestCase {
    func testThemeCatalogIncludesRequestedThemes() {
        XCTAssertEqual(ThemeCatalog.all.count, 7)

        let ids = Set(ThemeCatalog.all.map(\.id))
        XCTAssertTrue(ids.contains("odin"))
        XCTAssertTrue(ids.contains("thor"))
        XCTAssertTrue(ids.contains("loki"))
        XCTAssertTrue(ids.contains("heimdall"))
        XCTAssertTrue(ids.contains("freyja"))
        XCTAssertTrue(ids.contains("baldr"))
        XCTAssertTrue(ids.contains("tyr"))
    }

    func testHeimdallSecondaryPaletteUsesMultipleStops() {
        let heimdall = ThemeCatalog.theme(for: "heimdall")

        XCTAssertEqual(heimdall.name, "Heimdall")
        XCTAssertEqual(heimdall.primary.stops.count, 2)
        XCTAssertGreaterThanOrEqual(heimdall.secondary.stops.count, 4)
    }

    func testDefaultThemePalettePreservesBaldrColors() {
        let baldr = ThemeCatalog.theme(for: ThemeCatalog.defaultThemeID)

        XCTAssertEqual(baldr.palette, ThemePalette.baldr)
        XCTAssertEqual(baldr.palette.accent.hex, ThemePalette.baldr.accent.hex)
        XCTAssertEqual(baldr.palette.parchment.hex, ThemePalette.baldr.parchment.hex)
    }

    func testThemePaletteTracksCatalogStops() {
        let thor = ThemeCatalog.theme(for: "thor")

        XCTAssertEqual(thor.palette.accent.hex, thor.primary.stops.first?.hex)
        XCTAssertEqual(thor.palette.accentShadow.hex, thor.primary.stops.last?.hex)
        XCTAssertEqual(thor.palette.parchment.hex, ThemePalette.baldr.parchment.hex)
        XCTAssertEqual(thor.palette.darkWood.hex, thor.secondary.stops.first?.hex)
    }

    func testLightThemeUsesTintedCanvasAndDarkText() {
        let heimdall = ThemeCatalog.theme(for: "heimdall").palette

        let canvas = resolvedRGBColor(for: heimdall.canvasColor)
        let text = resolvedRGBColor(for: heimdall.textPrimaryColor)

        XCTAssertGreaterThan(luminance(of: canvas), 0.12)
        XCTAssertLessThan(luminance(of: text), 0.45)
    }

    private func resolvedRGBColor(for color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.deviceRGB) ?? .black
    }

    private func luminance(of color: NSColor) -> Double {
        0.2126 * Double(color.redComponent)
            + 0.7152 * Double(color.greenComponent)
            + 0.0722 * Double(color.blueComponent)
    }
}

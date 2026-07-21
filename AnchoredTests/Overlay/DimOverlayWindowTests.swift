import XCTest
@testable import Anchored

final class DimOverlayWindowTests: XCTestCase {
    func testDimOverlayWindowIsClickThrough() {
        guard let screen = NSScreen.screens.first else {
            return
        }

        let window = DimOverlayWindow(screen: screen)

        XCTAssertTrue(window.ignoresMouseEvents)
    }

    func testBackgroundColorIsThemeCanvasColor() {
        guard let screen = NSScreen.screens.first else {
            return
        }

        let window = DimOverlayWindow(screen: screen)

        XCTAssertEqual(window.backgroundColor, PirateTheme.canvasNSColor)
    }
}

import XCTest
@testable import Anchored

final class DimCenterPanelTests: XCTestCase {
    func testDimCenterPanelCanBecomeKeyAndMain() {
        let panel = DimCenterPanel()

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }
}

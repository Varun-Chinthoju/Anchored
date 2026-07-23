import XCTest
import AppKit
@testable import Anchored

final class UpdateManagerTests: XCTestCase {
    func testUpdatesAreDisabledWhenBuildFlagIsOff() {
        let manager = UpdateManager(updatesEnabled: false)
        let menuItem = NSMenuItem(title: "Check for Updates...", action: nil, keyEquivalent: "")

        XCTAssertFalse(manager.canCheckForUpdates)
        XCTAssertFalse(manager.validateMenuItem(menuItem))
    }
}

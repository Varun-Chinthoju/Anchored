import XCTest
@testable import Anchored

final class DistractionContextCloserTests: XCTestCase {
    func testClosesChromiumActiveTab() {
        let executor = MockAppleEventExecutor()
        executor.executeCallback = { _, _ in "" }
        let closer = DistractionContextCloser(
            appleEventExecutor: executor,
            closeFocusedWindow: { _ in
                XCTFail("Browser tab close should not fall back to the window")
                return false
            }
        )

        closer.closeContext(bundleID: "com.google.Chrome") {}

        XCTAssertEqual(executor.executedScripts.count, 1)
        XCTAssertTrue(executor.executedScripts[0].contains("close active tab of front window"))
    }

    func testClosesFocusedWindowForNonBrowserApp() {
        var closedBundleID: String?
        let closer = DistractionContextCloser(
            appleEventExecutor: MockAppleEventExecutor(),
            closeFocusedWindow: {
                closedBundleID = $0
                return true
            }
        )

        closer.closeContext(bundleID: "com.spotify.client") {}

        XCTAssertEqual(closedBundleID, "com.spotify.client")
    }

    func testFallsBackToFocusedWindowWhenBrowserAutomationFails() {
        let executor = MockAppleEventExecutor()
        var closedBundleID: String?
        let closer = DistractionContextCloser(
            appleEventExecutor: executor,
            closeFocusedWindow: {
                closedBundleID = $0
                return true
            }
        )

        closer.closeContext(bundleID: "com.apple.Safari") {}

        XCTAssertEqual(closedBundleID, "com.apple.Safari")
    }
}

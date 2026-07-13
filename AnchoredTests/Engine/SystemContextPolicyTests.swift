import XCTest
@testable import Anchored

final class SystemContextPolicyTests: XCTestCase {
    func testIgnoresLoginWindowAndSystemUI() {
        XCTAssertTrue(SystemContextPolicy.shouldIgnore(bundleID: "com.apple.loginwindow"))
        XCTAssertTrue(SystemContextPolicy.shouldIgnore(bundleID: "com.apple.WindowServer"))
        XCTAssertTrue(SystemContextPolicy.shouldIgnore(bundleID: "com.apple.systemuiserver"))
    }

    func testKeepsUserApplicationsEligible() {
        XCTAssertFalse(SystemContextPolicy.shouldIgnore(bundleID: "com.apple.dt.Xcode"))
        XCTAssertFalse(SystemContextPolicy.shouldIgnore(bundleID: "com.example.Focus"))
    }
}

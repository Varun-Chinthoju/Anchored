import XCTest
@testable import Anchored

final class AppDelegateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.varun.Anchored.AppDelegateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testShouldShowOnboardingWhenFlagIsMissingOrFalse() {
        let appDelegate = AppDelegate()

        XCTAssertTrue(appDelegate.shouldShowOnboardingFlow(defaults: defaults))

        defaults.set(false, forKey: "hasCompletedOnboarding")
        XCTAssertTrue(appDelegate.shouldShowOnboardingFlow(defaults: defaults))
    }

    func testShouldSkipOnboardingWhenCompletionFlagIsTrue() {
        let appDelegate = AppDelegate()
        defaults.set(true, forKey: "hasCompletedOnboarding")

        XCTAssertFalse(appDelegate.shouldShowOnboardingFlow(defaults: defaults))
    }
}

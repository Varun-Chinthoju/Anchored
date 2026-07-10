import XCTest
@testable import Anchored

final class AppDelegateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    private struct FlagOnlyChecker: FreshInstallChecking {
        func shouldShowOnboardingFlow(defaults: UserDefaults) -> Bool {
            return !defaults.bool(forKey: "hasCompletedOnboarding")
        }
    }

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

    private func makeSUT() -> AppDelegate {
        let appDelegate = AppDelegate()
        appDelegate.installChecker = FlagOnlyChecker()
        return appDelegate
    }

    func testShouldShowOnboardingWhenFlagIsMissingOrFalse() {
        let appDelegate = makeSUT()

        XCTAssertTrue(appDelegate.shouldShowOnboardingFlow(defaults: defaults))

        defaults.set(false, forKey: "hasCompletedOnboarding")
        XCTAssertTrue(appDelegate.shouldShowOnboardingFlow(defaults: defaults))
    }

    func testShouldSkipOnboardingWhenCompletionFlagIsTrue() {
        let appDelegate = makeSUT()
        defaults.set(true, forKey: "hasCompletedOnboarding")

        XCTAssertFalse(appDelegate.shouldShowOnboardingFlow(defaults: defaults))
    }

    func testLiveCheckerDetectsFreshInstall() {
        var providedPath = "/Applications/Anchored.app"
        let liveChecker = LiveFreshInstallChecker(
            fileManager: .default,
            appPathProvider: { providedPath }
        )
        let appDelegate = AppDelegate()
        appDelegate.installChecker = liveChecker

        XCTAssertTrue(appDelegate.shouldShowOnboardingFlow(defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: "lastInstalledPath"), providedPath)

        defaults.set(true, forKey: "hasCompletedOnboarding")
        XCTAssertFalse(appDelegate.shouldShowOnboardingFlow(defaults: defaults))

        providedPath = "/Applications/Anchored-Updated.app"
        XCTAssertTrue(appDelegate.shouldShowOnboardingFlow(defaults: defaults))
        XCTAssertFalse(defaults.bool(forKey: "hasCompletedOnboarding"))
    }
}

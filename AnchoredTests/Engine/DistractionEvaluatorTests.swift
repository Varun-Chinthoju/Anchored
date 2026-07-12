import XCTest
@testable import Anchored

final class DistractionEvaluatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var distractionListManager: DistractionListManager!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.varun.Anchored.DistractionEvaluatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        distractionListManager = DistractionListManager(defaults: defaults, applicationSearchRoots: [])
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        distractionListManager = nil
        defaults = nil
        super.tearDown()
    }

    func testAllowedDomainWinsWhenItAlsoAppearsInBlockedDomains() {
        let evaluator = makeEvaluator(
            WorkProfile(
                name: "Conflict",
                distractionDomains: ["youtube.com"],
                allowedDomains: ["youtube.com"]
            )
        )

        let decision = evaluator.evaluate(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=focus"),
            title: "Focus video"
        )

        XCTAssertEqual(decision.disposition, .focus)
        XCTAssertEqual(decision.source, .explicitAllowedDomain)
    }

    func testBlockedDomainWinsOverAllowedBrowserApp() {
        let evaluator = makeEvaluator(
            WorkProfile(
                name: "Browser",
                distractionDomains: ["youtube.com"],
                allowedApps: ["com.google.Chrome"]
            )
        )

        let decision = evaluator.evaluate(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=focus"),
            title: "Focus video"
        )

        XCTAssertEqual(decision.disposition, .distraction)
        XCTAssertEqual(decision.source, .explicitBlockedDomain)
    }

    func testExplicitBlockCannotBeOverriddenByLocalHeuristic() {
        let evaluator = makeEvaluator(
            WorkProfile(name: "Rules", distractionDomains: ["reddit.com"])
        )

        let decision = evaluator.evaluate(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.reddit.com/r/swift/comments/123"),
            title: "Swift programming forum"
        )

        XCTAssertEqual(decision.disposition, .distraction)
        XCTAssertEqual(decision.source, .explicitBlockedDomain)
    }

    func testBrowserWithoutAnActiveTabIsNeutral() {
        let decision = makeEvaluator(WorkProfile(name: "Browser")).evaluate(
            bundleID: "com.google.Chrome",
            url: nil,
            title: ""
        )

        XCTAssertEqual(decision.disposition, .neutral)
        XCTAssertEqual(decision.source, .neutralFallback)
    }

    func testProfileBlockedAppIsDeterministicallyDistraction() {
        let decision = makeEvaluator(
            WorkProfile(name: "Default", distractionApps: ["com.spotify.client"])
        ).evaluate(
            bundleID: "com.spotify.client",
            url: nil,
            title: "Spotify"
        )

        XCTAssertEqual(decision.disposition, .distraction)
        XCTAssertEqual(decision.source, .profileBlockedApp)
    }

    private func makeEvaluator(_ profile: WorkProfile) -> DistractionEvaluator {
        DistractionEvaluator(
            distractionListManager: distractionListManager,
            profileProvider: { profile }
        )
    }
}

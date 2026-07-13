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

        let decision = ClassificationResolver().resolve(evaluator.evidence(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=focus"),
            title: "Focus video"
        ))

        XCTAssertEqual(decision.label, .productive)
        XCTAssertEqual(decision.source, .explicitDomainRule)
    }

    func testBlockedDomainWinsOverAllowedBrowserApp() {
        let evaluator = makeEvaluator(
            WorkProfile(
                name: "Browser",
                distractionDomains: ["youtube.com"],
                allowedApps: ["com.google.Chrome"]
            )
        )

        let decision = ClassificationResolver().resolve(evaluator.evidence(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=focus"),
            title: "Focus video"
        ))

        XCTAssertEqual(decision.label, .distracting)
        XCTAssertEqual(decision.source, .explicitDomainRule)
    }

    func testExplicitBlockCannotBeOverriddenByLocalHeuristic() {
        let evaluator = makeEvaluator(
            WorkProfile(name: "Rules", distractionDomains: ["reddit.com"])
        )

        let decision = ClassificationResolver().resolve(evaluator.evidence(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.reddit.com/r/swift/comments/123"),
            title: "Swift programming forum"
        ))

        XCTAssertEqual(decision.label, .distracting)
        XCTAssertEqual(decision.source, .explicitDomainRule)
    }

    func testBrowserWithoutAnActiveTabIsNeutral() {
        let decision = ClassificationResolver().resolve(makeEvaluator(WorkProfile(name: "Browser")).evidence(
            bundleID: "com.google.Chrome",
            url: nil,
            title: ""
        ))

        XCTAssertEqual(decision.label, .neutral)
        XCTAssertEqual(decision.source, .neutralFallback)
    }

    func testProfileBlockedAppIsDeterministicallyDistraction() {
        let decision = ClassificationResolver().resolve(makeEvaluator(
            WorkProfile(name: "Default", distractionApps: ["com.spotify.client"])
        ).evidence(
            bundleID: "com.spotify.client",
            url: nil,
            title: "Spotify"
        ))

        XCTAssertEqual(decision.label, .distracting)
        XCTAssertEqual(decision.source, .explicitAppRule)
    }

    func testRulesExposeEvidenceForCentralResolver() {
        let evaluator = makeEvaluator(
            WorkProfile(
                name: "Evidence",
                distractionDomains: ["youtube.com"],
                allowedApps: ["com.google.Chrome"]
            )
        )

        let evidence = evaluator.evidence(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://www.youtube.com/watch?v=focus"),
            title: "Focus video"
        )

        XCTAssertEqual(evidence.map(\.label), [.distracting, .productive, .distracting])
        XCTAssertEqual(evidence.map(\.source), [.explicitDomainRule, .explicitAppRule, .heuristic])
        XCTAssertEqual(evidence.map(\.reason), [.explicitBlockRule, .explicitAllowRule, .deterministicHeuristic])
    }

    func testTitleOnlyBrowserHeuristicRemainsNeutralEvidence() {
        let evaluator = makeEvaluator(WorkProfile(name: "Heuristics"))

        let evidence = evaluator.evidence(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://example.com/article"),
            title: "Swift programming tutorial"
        )

        XCTAssertTrue(evidence.isEmpty)
    }

    private func makeEvaluator(_ profile: WorkProfile) -> DistractionEvaluator {
        DistractionEvaluator(
            distractionListManager: distractionListManager,
            profileProvider: { profile }
        )
    }
}

import XCTest
@testable import Anchored

final class LocalTextClassifierTests: XCTestCase {
    func testProductiveTextReturnsHighConfidenceProductiveResult() {
        let result = LocalTextClassifier().classify(snapshot: snapshot(
            bundleID: "com.google.Chrome",
            url: "https://developer.apple.com/documentation/swift",
            title: "Swift API documentation"
        ))

        XCTAssertEqual(result.label, .productive)
        XCTAssertGreaterThanOrEqual(result.confidence, ClassificationPolicy.highConfidenceThreshold)
        XCTAssertEqual(result.modelVersion, LocalTextClassifier.version)
    }

    func testLowSignalTextStaysNeutral() {
        let result = LocalTextClassifier().classify(snapshot: snapshot(
            bundleID: "com.google.Chrome",
            url: "https://example.com/page",
            title: "A page"
        ))

        XCTAssertEqual(result.label, .neutral)
    }

    func testVisibleWindowTextCanPromoteAnOtherwiseNeutralContext() {
        let result = LocalTextClassifier().classify(
            snapshot: snapshot(
                bundleID: "com.example.Reader",
                url: nil,
                title: "Overview"
            ),
            screenText: "Swift API documentation and code examples"
        )

        XCTAssertEqual(result.label, .productive)
        XCTAssertGreaterThanOrEqual(result.confidence, ClassificationPolicy.highConfidenceThreshold)
    }

    func testOnDeviceLocalClassificationUsesRealContextDataWhenEnabled() throws {
        let suiteName = "com.varun.Anchored.LocalTextClassifierTests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesManager(defaults: testDefaults)
        preferences.enableLocalTextClassification = true

        let result = LocalTextClassifier(preferences: preferences).classify(
            snapshot: snapshot(
                bundleID: "com.example.Reader",
                url: nil,
                title: "Overview"
            ),
            screenText: "Swift API documentation and code examples"
        )

        XCTAssertEqual(result.label, .productive)
        XCTAssertEqual(result.modelVersion, LocalTextClassifier.version)
        XCTAssertGreaterThanOrEqual(result.confidence, ClassificationPolicy.highConfidenceThreshold)
        XCTAssertEqual(result.explanation, "local productive signals")
    }

    func testConflictingSignalsStayNeutral() {
        let result = LocalTextClassifier().classify(snapshot: snapshot(
            bundleID: "com.google.Chrome",
            url: "https://www.youtube.com/watch",
            title: "Swift programming tutorial livestream"
        ))

        XCTAssertEqual(result.label, .neutral)
        XCTAssertEqual(result.explanation, "local signals conflict")
    }

    func testDistractingPredictionIsEnforcingThroughResolver() {
        let result = LocalTextClassifier().classify(snapshot: snapshot(
            bundleID: "com.spotify.client",
            url: nil,
            title: "Music"
        ))

        XCTAssertEqual(result.label, .distracting)

        let decision = ClassificationResolver().resolve([
            ClassificationEvidence(
                label: result.label,
                source: .localModel,
                confidence: result.confidence,
                reason: .modelEvidence
            )
        ])

        XCTAssertEqual(decision.label, .neutral)
        XCTAssertEqual(decision.reason, .optionalDistractionIsNonEnforcing)
    }

    private func snapshot(bundleID: String, url: String?, title: String) -> ContextSnapshot {
        ContextSnapshot(
            bundleIdentifier: bundleID,
            localizedName: "Test App",
            url: url.flatMap(URL.init(string:)),
            title: title,
            source: .chromium
        )
    }
}

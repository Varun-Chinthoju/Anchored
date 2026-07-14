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

    func testEvaluationReportsSafetyMetricsAndGate() {
        let fixtures = [
            LocalClassificationFixture(
                id: "productive-doc",
                snapshot: snapshot(
                    bundleID: "com.google.Chrome",
                    url: "https://developer.apple.com/documentation/swift",
                    title: "Swift API documentation"
                ),
                expectedLabel: .productive
            ),
            LocalClassificationFixture(
                id: "distracting-music",
                snapshot: snapshot(
                    bundleID: "com.spotify.client",
                    url: nil,
                    title: "Music"
                ),
                expectedLabel: .distracting
            ),
            LocalClassificationFixture(
                id: "unknown",
                snapshot: snapshot(
                    bundleID: "com.google.Chrome",
                    url: "https://example.com/page",
                    title: "A page"
                ),
                expectedLabel: .neutral
            )
        ]

        let report = LocalClassifierEvaluator.evaluate(
            classifier: LocalTextClassifier(),
            fixtures: fixtures,
            resourceMetrics: LocalClassifierResourceMetrics(
                cpuTimeMilliseconds: 2,
                peakMemoryBytes: 1024
            )
        )

        XCTAssertEqual(report.fixtureCount, 3)
        XCTAssertEqual(report.falseDistractionRate, 0)
        XCTAssertEqual(report.distractingPrecision, 1)
        XCTAssertEqual(report.cpuTimeMilliseconds, 2)
        XCTAssertEqual(report.peakMemoryBytes, 1024)
        XCTAssertTrue(report.precisionGatePassed)
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

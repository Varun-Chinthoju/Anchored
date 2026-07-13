import XCTest
@testable import Anchored

final class AutomaticDurationRecommendationTests: XCTestCase {
    func testUsesFallbackUntilEnoughSuccessfulSessionsExist() {
        let events = [session(duration: 30 * 60, outcome: .done)]

        XCTAssertEqual(
            AutomaticDurationRecommendation.recommendedDuration(from: events, fallback: 25 * 60),
            25 * 60
        )
    }

    func testUsesMedianOfRecentSuccessfulSessions() {
        let durations = [35, 50, 40, 45, 40].map { $0 * 60 }
        let events = durations.map { session(duration: $0, outcome: .done) }

        XCTAssertEqual(
            AutomaticDurationRecommendation.recommendedDuration(from: events, fallback: 25 * 60),
            40 * 60
        )
    }

    func testIgnoresAbandonedAndVeryShortSessions() {
        let successful = (30...33).map { session(duration: $0 * 60, outcome: .done) }
        let abandoned = session(duration: 8 * 60, outcome: .dismissed)
        let tooShort = session(duration: 2 * 60, outcome: .done)

        XCTAssertEqual(
            AutomaticDurationRecommendation.recommendedDuration(
                from: successful + [abandoned, tooShort],
                fallback: 25 * 60
            ),
            25 * 60
        )
    }

    func testClampsLongMedianToNinetyMinutes() {
        let events = (0..<5).map { session(duration: 3 * 60 * 60 + $0 * 60, outcome: .done) }

        XCTAssertEqual(
            AutomaticDurationRecommendation.recommendedDuration(from: events, fallback: 25 * 60),
            90 * 60
        )
    }

    private func session(duration: Int, outcome: SessionCompletionOutcome) -> SessionEvent {
        SessionEvent(
            type: .sessionEnd,
            appBundleID: "com.example.Focus",
            appName: "Focus",
            sessionDurationSeconds: duration,
            completionOutcome: outcome
        )
    }
}

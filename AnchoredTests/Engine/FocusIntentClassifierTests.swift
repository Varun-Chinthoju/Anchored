import XCTest
@testable import Anchored

final class FocusIntentClassifierTests: XCTestCase {
    func testGenericBrowserContextWithoutTaskSignalStaysUncertain() {
        let goalContext = ContextSnapshot(
            bundleIdentifier: "com.apple.dt.Xcode",
            localizedName: "Xcode",
            url: nil,
            title: "Project",
            source: .application
        )
        let intent = FocusIntent.make(
            goal: "Write docs",
            baselineContext: goalContext,
            activeProfileName: "Work",
            activeProfileCategory: "Focus"
        )

        let result = LocalIntentClassifier().classify(input: intent.makeInput(
            snapshot: ContextSnapshot(
                bundleIdentifier: "com.google.Chrome",
                localizedName: "Google Chrome",
                url: URL(string: "https://example.com/page"),
                title: "A page",
                source: .chromium
            )
        ))

        XCTAssertEqual(result.relation, .uncertain)
        XCTAssertEqual(result.reason, .insufficientIntent)
    }

    func testNonBrowserMismatchCanStillBeUnrelated() {
        let goalContext = ContextSnapshot(
            bundleIdentifier: "com.apple.dt.Xcode",
            localizedName: "Xcode",
            url: nil,
            title: "Project",
            source: .application
        )
        let intent = FocusIntent.make(
            goal: "Write docs",
            baselineContext: goalContext,
            activeProfileName: "Work",
            activeProfileCategory: "Focus"
        )

        let result = LocalIntentClassifier().classify(input: intent.makeInput(
            snapshot: ContextSnapshot(
                bundleIdentifier: "com.example.Player",
                localizedName: "Player",
                url: nil,
                title: "Game Night",
                source: .application
            )
        ))

        XCTAssertEqual(result.relation, .unrelated)
        XCTAssertEqual(result.reason, .goalMismatched)
    }
}

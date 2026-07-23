import XCTest
@testable import Anchored

final class ContextualSiteHeuristicTests: XCTestCase {
    func testReviewChoicesForBrowserIncludePageWebsiteAndApp() {
        let choices = ContextualSiteHeuristic.reviewChoices(
            for: "com.google.Chrome",
            url: URL(string: "https://example.com/article"),
            title: "Example Article"
        )

        XCTAssertEqual(choices, [.page, .website, .app])
    }

    func testReviewChoicesForAppStayAppOnly() {
        let choices = ContextualSiteHeuristic.reviewChoices(
            for: "com.example.editor",
            url: nil,
            title: "Draft"
        )

        XCTAssertEqual(choices, [.app])
    }

    func testReviewActionTitleStaysNeutralForBrowserItems() {
        let title = ContextualSiteHeuristic.reviewActionTitle()

        XCTAssertEqual(title, "Review Current Item")
    }
}

import XCTest
@testable import Anchored

final class SettingsSearchSupportTests: XCTestCase {
    func testLockQueryReturnsCommitmentLockFirstAndRoutesToSystemSettings() throws {
        let results = SettingsSearchIndex.results(
            query: "lock",
            isPirateMode: false,
            activeProfileName: "Focus"
        )

        let firstResult = try XCTUnwrap(results.first)
        XCTAssertEqual(firstResult.title, "Commitment Lock")
        XCTAssertEqual(firstResult.route.sidebarItem, .general)
        XCTAssertEqual(firstResult.route.scrollTarget, .generalSystem)
        XCTAssertFalse(results.contains(where: { $0.title == "Add Profile" }))
    }

    func testPrivacyQueryReturnsPrivacyRelatedSettingsOnly() {
        let results = SettingsSearchIndex.results(
            query: "privacy",
            isPirateMode: false,
            activeProfileName: "Focus"
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.title == "Enable Context History" }))
        XCTAssertTrue(results.contains(where: { $0.title == "Clear All History" }))
        XCTAssertTrue(results.contains(where: { $0.title == "Privacy" }))
        XCTAssertTrue(results.allSatisfy { $0.paneTitle == "Privacy & Data" || $0.title == "Privacy" })
    }

    func testDiagnosticQueryReturnsCopyDiagnosticReport() {
        let results = SettingsSearchIndex.results(
            query: "diagnostic",
            isPirateMode: false,
            activeProfileName: "Focus"
        )

        XCTAssertTrue(results.contains(where: { $0.title == "Copy Diagnostic Report" }))
        XCTAssertTrue(results.contains(where: { $0.route.scrollTarget == .privacyDiagnostics }))
    }

    func testOllamaQueryRoutesToProductivityIntelligence() throws {
        let results = SettingsSearchIndex.results(
            query: "ollama",
            isPirateMode: false,
            activeProfileName: "Focus"
        )

        let firstResult = try XCTUnwrap(results.first)
        XCTAssertEqual(firstResult.title, "Cloud Provider")
        XCTAssertEqual(firstResult.paneTitle, "Productivity Intelligence")
        XCTAssertEqual(firstResult.route.sidebarItem, .intelligence)
        XCTAssertEqual(firstResult.route.scrollTarget, .intelligenceCloud)
    }

    func testScheduleQueryReturnsScheduleSettingsOnly() {
        let results = SettingsSearchIndex.results(
            query: "schedule",
            isPirateMode: false,
            activeProfileName: "Focus"
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.title == "Enable Schedule" }))
        XCTAssertTrue(results.contains(where: { $0.title == "Start Time" }))
        XCTAssertTrue(results.allSatisfy { $0.sectionTitle == "Focus Schedule" })
    }

    func testSearchOmitsEmptySectionsAndUnrelatedActions() {
        let sections = SettingsSearchIndex.sections(
            query: "profile",
            isPirateMode: false,
            activeProfileName: "Focus"
        )

        let results = flattenedResults(in: sections)

        XCTAssertFalse(results.contains(where: { $0.title == "Add Profile" }))
        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.allSatisfy { !$0.results.isEmpty })
    }

    func testPartialAndCaseInsensitiveQueriesMatchTheSameSettings() throws {
        let lockResults = SettingsSearchIndex.results(
            query: "LoCk",
            isPirateMode: false,
            activeProfileName: "Focus"
        )
        let lockResult = try XCTUnwrap(lockResults.first)
        XCTAssertEqual(lockResult.title, "Commitment Lock")

        let scheduleResults = SettingsSearchIndex.results(
            query: "sched",
            isPirateMode: false,
            activeProfileName: "Focus"
        )
        XCTAssertTrue(scheduleResults.contains(where: { $0.title == "Enable Schedule" }))
    }

    func testMissingQueryReturnsNoResultsState() {
        let sections = SettingsSearchIndex.sections(
            query: "zzzz-not-a-setting",
            isPirateMode: false,
            activeProfileName: "Focus"
        )

        XCTAssertTrue(sections.isEmpty)
        XCTAssertTrue(flattenedResults(in: sections).isEmpty)
    }

    private func flattenedResults(in sections: [SettingsSearchSection]) -> [SettingsSearchResult] {
        sections.flatMap(\.results)
    }
}

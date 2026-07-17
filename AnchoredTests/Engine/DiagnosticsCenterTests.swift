import XCTest
@testable import Anchored

final class DiagnosticsCenterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsCenter.shared.reset()
    }

    override func tearDown() {
        DiagnosticsCenter.shared.reset()
        super.tearDown()
    }

    func testRedactionHelperHidesSensitiveValues() {
        let samples = [
            "Secret Title",
            "https://example.com/private?q=token",
            "Raw OCR text",
            "sk-proj-123456",
            "typed password"
        ]

        for sample in samples {
            XCTAssertEqual(DiagnosticsPrivacy.redactedText(sample), "<redacted>")
        }
    }

    func testDiagnosticReportIsBoundedAndSafe() {
        let center = DiagnosticsCenter.shared
        for index in 0..<130 {
            center.recordSanitizedError(category: index.isMultiple(of: 2) ? .unknown : .reportGeneration)
        }

        XCTAssertEqual(center.recentEvents(limit: 200).count, 120)

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersion = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let header = DiagnosticReportHeader(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.2.3",
            buildVersion: "456",
            macOSVersion: macOSVersion,
            databaseMigrationVersion: "7",
            accessibilityPermissionGranted: true,
            screenRecordingPermissionGranted: false,
            enabledSubsystems: ["engine", "timers", "permissions"]
        )

        let report = center.makeDiagnosticReport(header: header)

        XCTAssertTrue(report.contains("Anchored Diagnostic Report"))
        XCTAssertTrue(report.contains("App Version: 1.2.3 (Build 456)"))
        XCTAssertTrue(report.contains(macOSVersion))
        XCTAssertTrue(report.contains("Database Migration Version: 7"))
        XCTAssertTrue(report.contains("Accessibility: granted"))
        XCTAssertTrue(report.contains("Screen Recording: denied"))
        XCTAssertTrue(report.contains("engine"))
        XCTAssertTrue(report.contains("timers"))
        XCTAssertFalse(report.contains("Secret Title"))
        XCTAssertFalse(report.contains("https://example.com/private"))
        XCTAssertFalse(report.contains("Raw OCR text"))
        XCTAssertFalse(report.contains("sk-proj-123456"))
        XCTAssertFalse(report.contains("typed password"))
    }
}

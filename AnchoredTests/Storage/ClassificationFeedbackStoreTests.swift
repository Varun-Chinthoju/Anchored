import XCTest
@testable import Anchored

final class ClassificationFeedbackStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ClassificationFeedbackStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Feedback-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ClassificationFeedbackStore(
            sqliteStore: SQLiteSessionStore(databaseURL: directory.appendingPathComponent("feedback.db")),
            isEnabled: false
        )
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testDisabledFeedbackCreatesNoWrite() {
        let feedback = ClassificationFeedback(
            bundleID: " com.example.Editor ",
            domain: "Example.COM",
            originalLabel: .neutral,
            correctedLabel: .productive,
            correction: .allowApp,
            source: .neutralFallback
        )
        let writeExpectation = expectation(description: "disabled write completes")
        store.record(feedback) { _ in writeExpectation.fulfill() }
        wait(for: [writeExpectation], timeout: 1)

        let countExpectation = expectation(description: "count completes")
        store.count { result in
            XCTAssertEqual(try? result.get(), 0)
            countExpectation.fulfill()
        }
        wait(for: [countExpectation], timeout: 1)
        XCTAssertEqual(feedback.bundleID, "com.example.Editor")
        XCTAssertEqual(feedback.domain, "example.com")
    }

    func testEnabledFeedbackPersistsOnlyStructuredSanitizedFields() {
        store.isEnabled = true
        let feedback = ClassificationFeedback(
            bundleID: "com.example.Editor",
            domain: "example.com",
            originalLabel: .distracting,
            correctedLabel: .productive,
            correction: .allowDomain,
            source: .heuristic
        )
        let writeExpectation = expectation(description: "enabled write completes")
        store.record(feedback) { result in
            if case .failure(let error) = result {
                XCTFail("Feedback write failed: \(error)")
            }
            writeExpectation.fulfill()
        }
        wait(for: [writeExpectation], timeout: 1)

        let countExpectation = expectation(description: "count completes")
        store.count { result in
            XCTAssertEqual(try? result.get(), 1)
            countExpectation.fulfill()
        }
        wait(for: [countExpectation], timeout: 1)
    }
}

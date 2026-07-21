import XCTest
import GRDB
@testable import Anchored

final class ContextualLearningStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var dbURL: URL!
    private var sqliteStore: SQLiteSessionStore!
    private var store: ContextualLearningStore!

    override func setUp() {
        super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextualLearningStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dbURL = tempDirectory.appendingPathComponent("contextual-learning.db")
        sqliteStore = SQLiteSessionStore(databaseURL: dbURL)
        store = ContextualLearningStore(sqliteStore: sqliteStore, isEnabled: true)
    }

    override func tearDown() {
        store = nil
        sqliteStore = nil
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    private func awaitWrite(_ write: (@escaping StorageWriteCompletion) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = expectation(description: "storage write")
        var result: Result<Void, Error>?
        write { writeResult in
            result = writeResult
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        guard let result else {
            XCTFail("Missing write result", file: file, line: line)
            return
        }

        if case .failure(let error) = result {
            XCTFail("Write failed: \(error)", file: file, line: line)
        }
    }

    private func fetchRecords() throws -> [ContextualLearningRecord] {
        try sqliteStore.fetchContextualLearningRecords()
    }

    private func makeSnapshot(
        url: String,
        title: String
    ) -> ContextSnapshot {
        ContextSnapshot(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            url: URL(string: url),
            title: title,
            source: .chromium,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testRecordPersistsOnlyStructuredPrivacySafeFields() throws {
        let record = ContextualLearningRecord(
            normalizedDomain: " ChatGPT.com ",
            pageCategory: .chat,
            intentCategory: .coding,
            decision: .productive,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        awaitWrite { store.record(record, completion: $0) }

        let persisted = try fetchRecords()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted[0].normalizedDomain, "chatgpt.com")
        XCTAssertEqual(persisted[0].pageCategory, .chat)
        XCTAssertEqual(persisted[0].intentCategory, .coding)
        XCTAssertEqual(persisted[0].decision, .productive)
        XCTAssertEqual(persisted[0].timestamp.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testEvidenceOnlyMatchesTheExactDomainPageAndIntentBucket() {
        let record = ContextualLearningRecord(
            normalizedDomain: "chatgpt.com",
            pageCategory: .chat,
            intentCategory: .coding,
            decision: .productive,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        awaitWrite { store.record(record, completion: $0) }
        awaitWrite { store.record(record, completion: $0) }

        let codingSnapshot = makeSnapshot(
            url: "https://chatgpt.com/c/123",
            title: "ChatGPT - coding help"
        )
        let unrelatedSnapshot = makeSnapshot(
            url: "https://chatgpt.com/c/456",
            title: "ChatGPT - unrelated question"
        )

        let codingEvidence = store.evidence(
            for: codingSnapshot,
            focusIntent: FocusIntent(sanitizedGoal: "Write Swift code")
        )
        let unrelatedEvidence = store.evidence(
            for: unrelatedSnapshot,
            focusIntent: FocusIntent()
        )

        XCTAssertEqual(codingEvidence?.label, .productive)
        XCTAssertEqual(codingEvidence?.source, .deterministicRule)
        XCTAssertNil(unrelatedEvidence)
    }

    func testContradictoryCorrectionsStayContextual() {
        let productive = ContextualLearningRecord(
            normalizedDomain: "reddit.com",
            pageCategory: .community,
            intentCategory: .research,
            decision: .productive,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let distracting = ContextualLearningRecord(
            normalizedDomain: "reddit.com",
            pageCategory: .community,
            intentCategory: .research,
            decision: .distracting,
            timestamp: Date(timeIntervalSince1970: 1_700_000_060)
        )

        awaitWrite { store.record(productive, completion: $0) }
        awaitWrite { store.record(distracting, completion: $0) }

        let snapshot = makeSnapshot(
            url: "https://www.reddit.com/r/swift/comments/123",
            title: "Swift discussion"
        )

        let evidence = store.evidence(
            for: snapshot,
            focusIntent: FocusIntent(sanitizedGoal: "Learn about history")
        )

        XCTAssertEqual(evidence?.label, .contextual)
        XCTAssertEqual(evidence?.source, .heuristic)
        XCTAssertEqual(evidence?.reason, .contextualLearning)
    }
}

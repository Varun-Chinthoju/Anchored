import XCTest
import GRDB
@testable import Anchored

final class ClassificationOutcomeStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var dbURL: URL!
    private var sqliteStore: SQLiteSessionStore!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ClassificationOutcomeStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dbURL = tempDirectory.appendingPathComponent("outcomes.db")
        defaultsSuiteName = "ClassificationOutcomeStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        sqliteStore = SQLiteSessionStore(databaseURL: dbURL)
    }

    override func tearDown() {
        sqliteStore = nil
        defaults?.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil

        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        super.tearDown()
    }

    func testDisabledStoreIsOptInAndClearsWithoutPersisting() {
        let store = makeStore(isEnabled: false)
        let outcome = makeOutcome(
            appName: "  Editor  ",
            intentSummary: "  goal:code  ",
            modelVersion: "  intent-local-v1  "
        )

        let recordExpectation = expectation(description: "disabled record completes")
        store.record(outcome) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected record failure: \(error)")
            }
            recordExpectation.fulfill()
        }
        wait(for: [recordExpectation], timeout: 1)

        XCTAssertEqual(try readOutcomes().count, 0)

        let clearExpectation = expectation(description: "disabled clear completes")
        store.clearAll { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected clear failure: \(error)")
            }
            clearExpectation.fulfill()
        }
        wait(for: [clearExpectation], timeout: 1)
    }

    func testEnabledStoreDeduplicatesSanitizesAndClears() {
        let store = makeStore(isEnabled: true)
        let first = makeOutcome(
            id: UUID(),
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appName: "  Editor  ",
            intentSummary: "  goal:code  ",
            modelVersion: "  intent-local-v1  ",
            confidence: 0.92
        )
        let duplicate = ClassificationOutcome.make(
            bundleID: " com.example.Editor ",
            appName: "  Editor 2  ",
            contextGeneration: 7,
            sessionID: first.identity.sessionID,
            contextIdentity: ContextIdentity(
                bundleID: " com.example.Editor ",
                sanitizedURL: " https://example.com/path ",
                normalizedTitle: "  Project One  "
            ),
            intentSummary: "  goal:code  ",
            relation: .related,
            mappedLabel: .productive,
            confidence: 0.88,
            source: .heuristic,
            modelVersion: "  intent-local-v2  ",
            latency: 0.02,
            graceStarted: true,
            enforcementOccurred: false,
            observedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )

        let firstWrite = expectation(description: "first write")
        store.record(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected record failure: \(error)")
            }
            firstWrite.fulfill()
        }
        wait(for: [firstWrite], timeout: 1)

        let secondWrite = expectation(description: "second write")
        store.record(duplicate) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected record failure: \(error)")
            }
            secondWrite.fulfill()
        }
        wait(for: [secondWrite], timeout: 1)

        let outcomes = try! readOutcomes()
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].appName, "Editor 2")
        XCTAssertEqual(outcomes[0].intentSummary, "goal:code")
        XCTAssertEqual(outcomes[0].modelVersion, "intent-local-v2")
        XCTAssertEqual(outcomes[0].identity.contextIdentity.bundleID, "com.example.Editor")
        XCTAssertEqual(outcomes[0].identity.contextIdentity.sanitizedURL, "https://example.com/path")
        XCTAssertEqual(outcomes[0].identity.contextIdentity.normalizedTitle, "Project One")

        let clearExpectation = expectation(description: "clear writes")
        store.clearAll { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected clear failure: \(error)")
            }
            clearExpectation.fulfill()
        }
        wait(for: [clearExpectation], timeout: 1)
        XCTAssertEqual(try! readOutcomes().count, 0)
    }

    func testRecordCorrectionUpdatesPersistedRow() {
        let store = makeStore(isEnabled: true)
        let outcome = makeOutcome()

        let writeExpectation = expectation(description: "record outcome")
        store.record(outcome) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected record failure: \(error)")
            }
            writeExpectation.fulfill()
        }
        wait(for: [writeExpectation], timeout: 1)

        let correctionExpectation = expectation(description: "record correction")
        store.recordCorrection(
            identity: outcome.identity,
            correction: .allowApp,
            correctedAt: Date(timeIntervalSince1970: 1_700_000_999)
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected correction failure: \(error)")
            }
            correctionExpectation.fulfill()
        }
        wait(for: [correctionExpectation], timeout: 1)

        let outcomes = try! readOutcomes()
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].correction, .allowApp)
        XCTAssertEqual(outcomes[0].correctedAt?.timeIntervalSince1970 ?? 0, 1_700_000_999, accuracy: 0.001)
    }

    func testWritesRunOffTheMainThread() {
        let recordThreadExpectation = expectation(description: "record thread captured")
        let correctionThreadExpectation = expectation(description: "correction thread captured")
        var recordWasMain = true
        var correctionWasMain = true

        let store = makeStore(
            isEnabled: true,
            onRecord: { _ in
                recordWasMain = Thread.isMainThread
                recordThreadExpectation.fulfill()
            },
            onCorrection: { _, _ in
                correctionWasMain = Thread.isMainThread
                correctionThreadExpectation.fulfill()
            }
        )

        let outcome = makeOutcome()
        store.record(outcome, completion: nil)
        wait(for: [recordThreadExpectation], timeout: 1)

        store.recordCorrection(
            identity: outcome.identity,
            correction: .allowApp,
            correctedAt: Date(),
            completion: nil
        )
        wait(for: [correctionThreadExpectation], timeout: 1)

        XCTAssertFalse(recordWasMain)
        XCTAssertFalse(correctionWasMain)
    }

    private func makeStore(
        isEnabled: Bool,
        onRecord: ((ClassificationOutcome) -> Void)? = nil,
        onCorrection: ((ClassificationOutcome.Identity, ClassificationCorrection) -> Void)? = nil
    ) -> ClassificationOutcomeStore {
        ClassificationOutcomeStore(
            sqliteStore: sqliteStore,
            defaults: defaults,
            isEnabled: isEnabled,
            onRecord: onRecord,
            onCorrection: onCorrection
        )
    }

    private func makeOutcome(
        id: UUID = UUID(),
        observedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        appName: String = "Editor",
        intentSummary: String? = "goal:code",
        modelVersion: String = "intent-local-v1",
        confidence: Double = 0.91
    ) -> ClassificationOutcome {
        ClassificationOutcome(
            id: id,
            observedAt: observedAt,
            identity: ClassificationOutcome.Identity(
                contextGeneration: 7,
                sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
                contextIdentity: ContextIdentity(
                    bundleID: " com.example.Editor ",
                    sanitizedURL: " https://example.com/path ",
                    normalizedTitle: "  Project One  "
                )
            ),
            appName: appName,
            intentSummary: intentSummary,
            relation: .related,
            mappedLabel: .productive,
            confidence: confidence,
            source: .heuristic,
            modelVersion: modelVersion,
            latency: 0.02,
            graceStarted: true,
            enforcementOccurred: false
        )
    }

    private func readOutcomes() throws -> [ClassificationOutcome] {
        try sqliteStore.dbQueue.read { db in
            try ClassificationOutcome
                .order(Column("timestamp").asc, Column("rowid").asc)
                .fetchAll(db)
        }
    }
}

import XCTest
import GRDB
@testable import Anchored

final class ContextHistoryStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var dbURL: URL!
    private var sqliteStore: SQLiteSessionStore!
    private var historyStore: ContextHistoryStore!
    private var defaults: UserDefaults!
    private var now: Date!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        let baseURL = FileManager.default.temporaryDirectory
        tempDirectory = baseURL.appendingPathComponent("ContextHistoryStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dbURL = tempDirectory.appendingPathComponent("history.db")
        now = Date(timeIntervalSince1970: 1_700_000_000)
        defaultsSuiteName = "ContextHistoryStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        sqliteStore = SQLiteSessionStore(databaseURL: dbURL)
        historyStore = ContextHistoryStore(
            sqliteStore: sqliteStore,
            defaults: defaults,
            isEnabled: false,
            clock: { [unowned self] in self.now }
        )
    }

    override func tearDown() {
        historyStore = nil
        sqliteStore = nil
        if let defaults, let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    private func makeObservation(
        observedAt: Date,
        title: String,
        url: String,
        sessionState: SessionState = .anchored
    ) -> PersistedContextObservation {
        PersistedContextObservation(
            observedAt: observedAt,
            bundleID: " com.apple.Safari ",
            appName: " Safari ",
            source: .safari,
            title: title,
            sanitizedURL: url,
            domain: "EXAMPLE.COM",
            sessionState: sessionState
        )
    }

    private func fetchObservations() throws -> [PersistedContextObservation] {
        try sqliteStore.dbQueue.read { db in
            try PersistedContextObservation
                .order(Column("timestamp").asc, Column("rowid").asc)
                .fetchAll(db)
        }
    }

    private func awaitWrite(_ write: (@escaping StorageWriteCompletion) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = expectation(description: "Storage write")
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

    private func awaitCount() -> Int {
        let expectation = expectation(description: "Count")
        var result: Result<Int, Error>?
        historyStore.observationCount { countResult in
            result = countResult
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        switch result {
        case .success(let count):
            return count
        case .failure(let error):
            XCTFail("Count failed: \(error)")
            return -1
        case nil:
            XCTFail("Missing count result")
            return -1
        }
    }

    private func awaitOldestDate() -> Date? {
        let expectation = expectation(description: "Oldest date")
        var result: Result<Date?, Error>?
        historyStore.oldestObservationDate { dateResult in
            result = dateResult
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        switch result {
        case .success(let date):
            return date
        case .failure(let error):
            XCTFail("Oldest date query failed: \(error)")
            return nil
        case nil:
            XCTFail("Missing oldest date result")
            return nil
        }
    }

    func testRecordSkipsWhenDisabled() throws {
        let observation = makeObservation(
            observedAt: now,
            title: " Project One ",
            url: "https://user:pass@example.com/path?query=1#fragment"
        )

        awaitWrite { historyStore.record(observation, completion: $0) }

        XCTAssertEqual(try fetchObservations().count, 0)
        XCTAssertEqual(awaitCount(), 0)
        XCTAssertNil(awaitOldestDate())
    }

    func testRecordSanitizesAndDeduplicatesConsecutiveIdenticalObservations() throws {
        historyStore.isEnabled = true

        let first = makeObservation(
            observedAt: now,
            title: "  Project\nOne  ",
            url: "https://user:pass@Example.COM/path?query=1#fragment"
        )
        let duplicate = makeObservation(
            observedAt: now.addingTimeInterval(30),
            title: "Project One",
            url: "https://example.com/path"
        )
        let changedTitle = makeObservation(
            observedAt: now.addingTimeInterval(60),
            title: "Project Two",
            url: "https://example.com/path"
        )

        awaitWrite { historyStore.record(first, completion: $0) }
        awaitWrite { historyStore.record(duplicate, completion: $0) }
        awaitWrite { historyStore.record(changedTitle, completion: $0) }

        let observations = try fetchObservations()
        XCTAssertEqual(observations.count, 2)

        XCTAssertEqual(observations[0].bundleID, "com.apple.Safari")
        XCTAssertEqual(observations[0].appName, "Safari")
        XCTAssertEqual(observations[0].source, .safari)
        XCTAssertEqual(observations[0].title, "Project One")
        XCTAssertEqual(observations[0].sanitizedURL, "https://example.com/path")
        XCTAssertEqual(observations[0].domain, "example.com")
        XCTAssertEqual(observations[0].sessionState, .anchored)

        XCTAssertEqual(observations[1].title, "Project Two")
        XCTAssertEqual(awaitCount(), 2)
    }

    func testPruneAndClearOnlyAffectContextObservations() throws {
        historyStore.isEnabled = true

        let oldObservation = makeObservation(
            observedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
            title: "Old Project",
            url: "https://example.com/old"
        )
        let recentObservation = makeObservation(
            observedAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            title: "Recent Project",
            url: "https://example.com/recent"
        )
        let sessionEvent = SessionEvent(
            type: .sessionEnd,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            sessionDurationSeconds: 900
        )

        awaitWrite { historyStore.record(oldObservation, completion: $0) }
        awaitWrite { historyStore.record(recentObservation, completion: $0) }
        awaitWrite { sqliteStore.log(sessionEvent, completion: $0) }

        awaitWrite { historyStore.prune(retentionDays: 7, completion: $0) }

        let retained = try fetchObservations()
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained[0].title, "Recent Project")
        XCTAssertEqual(sqliteStore.allEvents().count, 1)

        awaitWrite { historyStore.clearAll(completion: $0) }

        XCTAssertEqual(try fetchObservations().count, 0)
        XCTAssertEqual(sqliteStore.allEvents().count, 1)
        XCTAssertEqual(awaitCount(), 0)
        XCTAssertNil(awaitOldestDate())
    }

    func testObservationCountAndOldestObservationDateQueries() throws {
        historyStore.isEnabled = true

        let first = makeObservation(
            observedAt: now.addingTimeInterval(-3600),
            title: "First",
            url: "https://example.com/first"
        )
        let second = makeObservation(
            observedAt: now,
            title: "Second",
            url: "https://example.com/second"
        )

        awaitWrite { historyStore.record(first, completion: $0) }
        awaitWrite { historyStore.record(second, completion: $0) }

        XCTAssertEqual(awaitCount(), 2)
        let oldestDate = awaitOldestDate()
        XCTAssertEqual(oldestDate?.timeIntervalSince1970 ?? 0, first.observedAt.timeIntervalSince1970, accuracy: 1.0)
    }
}

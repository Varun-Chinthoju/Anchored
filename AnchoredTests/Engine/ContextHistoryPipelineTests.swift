import XCTest
import AppKit
import GRDB
@testable import Anchored

final class ContextHistoryPipelineTests: XCTestCase {
    private var tempDirectory: URL!
    private var dbURL: URL!
    private var sqliteStore: SQLiteSessionStore!
    private var historyStore: ContextHistoryStore!
    private var engine: FocusEngine!
    private var monitor: MockActivityMonitor!
    private var profileManager: ProfileManager!
    private var testDefaults: UserDefaults!
    private var testDefaultsSuiteName: String!
    private var pipeline: ContextHistoryPipeline!
    private var previousUserActivityProvider: UserActivityProviding!

    override func setUp() {
        super.setUp()

        let fileManager = FileManager.default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("ContextHistoryPipelineTests-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        dbURL = tempDirectory.appendingPathComponent("history.db")
        sqliteStore = SQLiteSessionStore(databaseURL: dbURL)
        testDefaultsSuiteName = "ContextHistoryPipelineTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!
        profileManager = ProfileManager(defaults: testDefaults)
        monitor = MockActivityMonitor()
        previousUserActivityProvider = UserActivityEnvironment.shared
        UserActivityEnvironment.shared = MockUserActivityProvider()
        engine = FocusEngine(
            activityMonitor: monitor,
            distractionListManager: DistractionListManager(defaults: testDefaults),
            sessionStore: SessionStore(fileURL: tempDirectory.appendingPathComponent("sessions.json")),
            profileManager: profileManager,
            focusThreshold: 600.0,
            preferencesManager: PreferencesManager(defaults: testDefaults),
            ocrProvider: MockOCRProvider(),
            visualChecker: MockVisualChecker()
        )
        historyStore = ContextHistoryStore(sqliteStore: sqliteStore, defaults: testDefaults, isEnabled: true)
        pipeline = ContextHistoryPipeline(focusEngine: engine, historyStore: historyStore)
    }

    override func tearDown() {
        pipeline = nil
        engine.stop()
        engine = nil
        historyStore = nil
        sqliteStore = nil
        monitor = nil
        profileManager = nil
        if let testDefaults, let testDefaultsSuiteName {
            testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        }
        testDefaults = nil
        testDefaultsSuiteName = nil

        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        UserActivityEnvironment.shared = previousUserActivityProvider
        previousUserActivityProvider = nil

        super.tearDown()
    }

    func testPipelinePersistsAcceptedContextChanges() {
        let expectation = XCTestExpectation(description: "History entry persisted")

        monitor.simulateContextChange(
            bundleID: "com.apple.dt.Xcode",
            url: URL(string: "https://user:pass@example.com/path?token=1#fragment"),
            title: "  Project\nOne  "
        )

        historyStore.observationCount { result in
            switch result {
            case .success(let count):
                XCTAssertEqual(count, 1)
            case .failure(let error):
                XCTFail("Unexpected count failure: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        let rows = try! sqliteStore.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM context_observations;")
        }
        XCTAssertEqual(rows.count, 1)
        let title: String = rows[0]["title"]
        let sanitizedURL: String = rows[0]["url"]
        XCTAssertEqual(title, "Project One")
        XCTAssertEqual(sanitizedURL, "https://example.com/path")
    }
}

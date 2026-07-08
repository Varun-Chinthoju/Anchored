import XCTest
import Combine
@testable import Anchored

final class DistractionListManagerTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var tempDirectoryURL: URL!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        suiteName = "com.varun.Anchored.DistractionListManagerTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Anchored-DistractionListManagerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        cancellables = []
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        testDefaults = nil
        tempDirectoryURL = nil
        cancellables = nil
        super.tearDown()
    }
    
    func testDefaultDistractionsListAndPersistence() {
        // Given a clean UserDefaults instance (no prior values)
        // When initializing DistractionListManager
        let manager = DistractionListManager(defaults: testDefaults)
        
        // Then it should expose the default distraction list
        let expectedDefaults = DistractionListManager.defaultDistractions
        XCTAssertEqual(manager.allDistractions, expectedDefaults)
        
        // And isDistraction should return true for default apps and false for others
        for bundleID in expectedDefaults {
            XCTAssertTrue(manager.isDistraction(bundleID), "\(bundleID) should be a distraction by default")
        }
        XCTAssertFalse(manager.isDistraction("com.apple.dt.Xcode"))
        
        // And the defaults should be immediately persisted in UserDefaults
        let storedList = testDefaults.stringArray(forKey: "com.varun.Anchored.distractionList")
        XCTAssertEqual(storedList, expectedDefaults)
    }
    
    func testLoadingFromExistingUserDefaults() {
        // Given an existing saved distraction list in UserDefaults
        let customList = ["com.apple.dt.Xcode", "com.google.Chrome"]
        testDefaults.set(customList, forKey: "com.varun.Anchored.distractionList")
        
        // When initializing DistractionListManager
        let manager = DistractionListManager(defaults: testDefaults)
        
        // Then it should load the custom list instead of the default list
        XCTAssertEqual(manager.allDistractions, customList)
        XCTAssertTrue(manager.isDistraction("com.apple.dt.Xcode"))
        XCTAssertTrue(manager.isDistraction("com.google.Chrome"))
        XCTAssertFalse(manager.isDistraction("com.apple.Music")) // part of defaults, but shouldn't be loaded
    }
    
    func testAddDistraction() {
        let manager = DistractionListManager(defaults: testDefaults)
        let newApp = "com.google.Chrome"
        
        // Setup notification expectation
        let notificationExpectation = expectation(forNotification: .distractionListDidChange, object: manager, handler: nil)
        
        // Setup @Published observer expectation
        var publishedList: [String]?
        let publishedExpectation = expectation(description: "allDistractions should publish changes")
        
        manager.$allDistractions
            .dropFirst() // ignore initial value
            .sink { list in
                publishedList = list
                publishedExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        // When adding a new app
        manager.add(newApp)
        
        // Then it should trigger notifications and update properties
        wait(for: [notificationExpectation, publishedExpectation], timeout: 1.0)
        
        XCTAssertTrue(manager.isDistraction(newApp))
        XCTAssertTrue(manager.allDistractions.contains(newApp))
        XCTAssertEqual(publishedList, manager.allDistractions)
        
        // And it should persist the change to UserDefaults
        let storedList = testDefaults.stringArray(forKey: "com.varun.Anchored.distractionList")
        XCTAssertEqual(storedList, manager.allDistractions)
    }
    
    func testAddDuplicateDistractionDoesNothing() {
        let manager = DistractionListManager(defaults: testDefaults)
        let defaultCount = manager.allDistractions.count
        let existingApp = DistractionListManager.defaultDistractions.first!
        
        // Setup notification observer that should NOT be triggered
        var notificationTriggered = false
        let token = NotificationCenter.default.addObserver(
            forName: .distractionListDidChange,
            object: manager,
            queue: nil
        ) { _ in
            notificationTriggered = true
        }
        
        // When adding an existing app
        manager.add(existingApp)
        
        // Then nothing should change
        XCTAssertEqual(manager.allDistractions.count, defaultCount)
        XCTAssertFalse(notificationTriggered)
        
        NotificationCenter.default.removeObserver(token)
    }
    
    func testRemoveDistraction() {
        let manager = DistractionListManager(defaults: testDefaults)
        let appToRemove = DistractionListManager.defaultDistractions.first!
        
        // Setup notification expectation
        let notificationExpectation = expectation(forNotification: .distractionListDidChange, object: manager, handler: nil)
        
        // Setup @Published observer expectation
        var publishedList: [String]?
        let publishedExpectation = expectation(description: "allDistractions should publish changes")
        
        manager.$allDistractions
            .dropFirst() // ignore initial value
            .sink { list in
                publishedList = list
                publishedExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        // When removing the app
        manager.remove(appToRemove)
        
        // Then it should trigger notifications and update properties
        wait(for: [notificationExpectation, publishedExpectation], timeout: 1.0)
        
        XCTAssertFalse(manager.isDistraction(appToRemove))
        XCTAssertFalse(manager.allDistractions.contains(appToRemove))
        XCTAssertEqual(publishedList, manager.allDistractions)
        
        // And it should persist the change to UserDefaults
        let storedList = testDefaults.stringArray(forKey: "com.varun.Anchored.distractionList")
        XCTAssertEqual(storedList, manager.allDistractions)
    }
    
    func testRemoveNonExistentDistractionDoesNothing() {
        let manager = DistractionListManager(defaults: testDefaults)
        let defaultCount = manager.allDistractions.count
        let nonExistentApp = "com.apple.dt.Xcode"
        
        // Setup notification observer that should NOT be triggered
        var notificationTriggered = false
        let token = NotificationCenter.default.addObserver(
            forName: .distractionListDidChange,
            object: manager,
            queue: nil
        ) { _ in
            notificationTriggered = true
        }
        
        // When removing a non-existent app
        manager.remove(nonExistentApp)
        
        // Then nothing should change
        XCTAssertEqual(manager.allDistractions.count, defaultCount)
        XCTAssertFalse(notificationTriggered)
        
        NotificationCenter.default.removeObserver(token)
    }
    
    func testInstalledSuggestionsScansNestedApplicationFoldersForChatApps() throws {
        let rootURL = tempDirectoryURL.appendingPathComponent("Applications", isDirectory: true)
        let nestedAppURL = rootURL
            .appendingPathComponent("Teams", isDirectory: true)
            .appendingPathComponent("OrbitChat.app", isDirectory: true)
        let topLevelAppURL = rootURL.appendingPathComponent("WorkChat.app", isDirectory: true)
        
        try createFakeApp(
            at: nestedAppURL,
            bundleID: "com.example.OrbitChat",
            displayName: "OrbitChat",
            category: "public.app-category.social-networking"
        )
        try createFakeApp(
            at: topLevelAppURL,
            bundleID: "com.example.WorkChat",
            displayName: "WorkChat",
            category: "public.app-category.business"
        )
        
        let manager = DistractionListManager(
            defaults: testDefaults,
            applicationSearchRoots: [rootURL]
        )
        
        let suggestions = manager.installedSuggestions
        XCTAssertTrue(suggestions.contains { $0.bundleID == "com.example.OrbitChat" && $0.name == "OrbitChat" })
        XCTAssertTrue(suggestions.contains { $0.bundleID == "com.example.WorkChat" && $0.name == "WorkChat" })
    }
    
    private func createFakeApp(
        at appURL: URL,
        bundleID: String,
        displayName: String,
        category: String
    ) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleDisplayName": displayName,
            "CFBundleName": displayName,
            "LSApplicationCategoryType": category
        ]
        
        let data = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
    }
}

import XCTest
import Combine
@testable import Anchored

final class ProfileManagerTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        suiteName = "com.varun.Anchored.ProfileManagerTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        cancellables = []
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        cancellables = nil
        super.tearDown()
    }
    
    func testInitializationWithDefaults() {
        // Given a clean UserDefaults instance
        // When initializing ProfileManager
        let manager = ProfileManager(defaults: testDefaults)
        
        // Then standard profiles should be initialized
        XCTAssertEqual(manager.profiles.count, 3)
        XCTAssertTrue(manager.profiles.contains { $0.name == "Coding" })
        XCTAssertTrue(manager.profiles.contains { $0.name == "Writing" })
        XCTAssertTrue(manager.profiles.contains { $0.name == "Video" })
        
        // And activeProfile should be "Coding" by default
        XCTAssertEqual(manager.activeProfile.name, "Coding")
        
        // Check that distraction lists contain default apps
        if let codingProfile = manager.profiles.first(where: { $0.name == "Coding" }) {
            XCTAssertTrue(codingProfile.distractionApps.contains("com.hnc.Discord"))
            XCTAssertTrue(codingProfile.distractionDomains.contains("youtube.com"))
            XCTAssertTrue(codingProfile.allowedApps.contains("com.apple.dt.Xcode"))
            XCTAssertTrue(codingProfile.allowedDomains.contains("github.com"))
        } else {
            XCTFail("Coding profile should exist")
        }
    }

    func testLegacyProfileDecodingDefaultsAllowedAppsToEmptyArray() {
        let legacyProfileJSON = """
        [
          {
            "id": "D8E246F0-4F95-4F76-8FA8-5E5EEC9D2A2F",
            "name": "Legacy",
            "distractionApps": ["com.spotify.client"],
            "distractionDomains": ["youtube.com"],
            "allowedDomains": ["github.com"]
          }
        ]
        """

        testDefaults.set(legacyProfileJSON.data(using: .utf8), forKey: "com.varun.Anchored.profiles")
        testDefaults.set("Legacy", forKey: "com.varun.Anchored.activeProfileName")

        let manager = ProfileManager(defaults: testDefaults)

        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.activeProfile.name, "Legacy")
        XCTAssertEqual(manager.activeProfile.allowedApps, [])
    }
    
    func testSerializationAndPersistence() {
        // Given a ProfileManager with default profiles initialized
        let manager1 = ProfileManager(defaults: testDefaults)
        
        // When updating a profile
        var codingProfile = manager1.profiles.first(where: { $0.name == "Coding" })!
        codingProfile.distractionDomains.append("reddit.com")
        manager1.updateProfile(codingProfile)
        
        // And switching profile to "Writing"
        manager1.switchProfile(to: "Writing")
        
        // Then initializing a new ProfileManager with the same UserDefaults
        let manager2 = ProfileManager(defaults: testDefaults)
        
        // It should load the persisted profiles and active profile
        XCTAssertEqual(manager2.activeProfile.name, "Writing")
        if let loadedCoding = manager2.profiles.first(where: { $0.name == "Coding" }) {
            XCTAssertTrue(loadedCoding.distractionDomains.contains("reddit.com"))
        } else {
            XCTFail("Persisted Coding profile should exist")
        }
    }
    
    func testSwitchProfile() {
        let manager = ProfileManager(defaults: testDefaults)
        
        // Setup expectations
        let notificationExpectation = expectation(forNotification: .activeProfileDidChange, object: manager, handler: nil)
        
        var publishedProfile: WorkProfile?
        let publishedExpectation = expectation(description: "activeProfile should publish change")
        
        manager.$activeProfile
            .dropFirst() // ignore initial value
            .sink { profile in
                publishedProfile = profile
                publishedExpectation.fulfill()
            }
            .store(in: &cancellables)
            
        // When switching active profile
        manager.switchProfile(to: "Video")
        
        // Then
        wait(for: [notificationExpectation, publishedExpectation], timeout: 1.0)
        XCTAssertEqual(manager.activeProfile.name, "Video")
        XCTAssertEqual(publishedProfile?.name, "Video")
        
        // And persistence is updated
        let storedActiveName = testDefaults.string(forKey: "com.varun.Anchored.activeProfileName")
        XCTAssertEqual(storedActiveName, "Video")
    }
    
    func testAddAndDeleteProfile() {
        let manager = ProfileManager(defaults: testDefaults)
        
        let customProfile = WorkProfile(
            name: "CustomFocus",
            distractionApps: ["com.custom.app"],
            distractionDomains: ["distraction.com"],
            allowedApps: ["com.custom.productivity"],
            allowedDomains: ["allowed.com"]
        )
        
        // When adding a profile
        let notificationExpectation = expectation(forNotification: .profilesDidChange, object: manager, handler: nil)
        manager.addProfile(customProfile)
        
        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(manager.profiles.count, 4)
        XCTAssertTrue(manager.profiles.contains { $0.name == "CustomFocus" })
        
        // When deleting the profile
        if let index = manager.profiles.firstIndex(where: { $0.name == "CustomFocus" }) {
            let deleteNotificationExpectation = expectation(forNotification: .profilesDidChange, object: manager, handler: nil)
            manager.deleteProfile(at: index)
            wait(for: [deleteNotificationExpectation], timeout: 1.0)
        } else {
            XCTFail("CustomFocus index should exist")
        }
        
        XCTAssertEqual(manager.profiles.count, 3)
        XCTAssertFalse(manager.profiles.contains { $0.name == "CustomFocus" })
    }
    
    func testDomainUpdates() {
        // Given a ProfileManager
        let manager = ProfileManager(defaults: testDefaults)
        
        // When updating distractionDomains and allowedDomains for the active profile
        var activeProfile = manager.activeProfile
        activeProfile.distractionDomains = ["tiktok.com", "reddit.com"]
        activeProfile.allowedApps = ["com.apple.dt.Xcode", "com.apple.Terminal"]
        activeProfile.allowedDomains = ["github.com", "google.com"]
        
        manager.updateProfile(activeProfile)
        
        // Then the domains should be saved correctly in the profile
        let updatedProfile = manager.profiles.first(where: { $0.id == activeProfile.id })
        XCTAssertNotNil(updatedProfile)
        XCTAssertEqual(updatedProfile?.distractionDomains, ["tiktok.com", "reddit.com"])
        XCTAssertEqual(updatedProfile?.allowedApps, ["com.apple.dt.Xcode", "com.apple.Terminal"])
        XCTAssertEqual(updatedProfile?.allowedDomains, ["github.com", "google.com"])
        
        // And they should persist in a new instance of ProfileManager
        let newManager = ProfileManager(defaults: testDefaults)
        let loadedProfile = newManager.profiles.first(where: { $0.id == activeProfile.id })
        XCTAssertNotNil(loadedProfile)
        XCTAssertEqual(loadedProfile?.distractionDomains, ["tiktok.com", "reddit.com"])
        XCTAssertEqual(loadedProfile?.allowedApps, ["com.apple.dt.Xcode", "com.apple.Terminal"])
        XCTAssertEqual(loadedProfile?.allowedDomains, ["github.com", "google.com"])
    }
}

import XCTest
@testable import Anchored

final class LanguageManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.varun.Anchored.LanguageManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeManager() -> LanguageManager {
        LanguageManager(defaults: defaults)
    }

    func testDefaultsUseNormalOnboardingLanguage() {
        let manager = makeManager()

        XCTAssertFalse(manager.isPirateMode)
        XCTAssertEqual(manager.currentLanguage, .english)
        XCTAssertEqual(manager.translate("lang_fun_route"), "Additional Languages")
        XCTAssertEqual(manager.translate("welcome_title"), "Welcome to Anchored")
        XCTAssertEqual(manager.translate("welcome_btn"), "Get Started")
        XCTAssertEqual(manager.translate("perm_title"), "Grant\nPermissions")
    }

    func testPermissionStepUsesNormalLanguageByDefault() {
        let manager = makeManager()

        XCTAssertEqual(manager.translate("perm_desc"), "Anchored needs Accessibility permission to monitor browser domains and window titles. This helps detect distracting websites and apps.")
        XCTAssertEqual(manager.translate("perm_step_ax_title"), "Accessibility Permission")
        XCTAssertEqual(manager.translate("perm_step_ax_desc"), "Detects browser tabs and distracting URLs.")
        XCTAssertEqual(manager.translate("perm_step_enable"), "Enable")
        XCTAssertEqual(manager.translate("perm_step_skip"), "Skip For Now (local visual checks will be limited)")
        XCTAssertEqual(manager.translate("perm_gate_title"), "Unlock Permissions")
        XCTAssertEqual(manager.translate("perm_gate_later"), "Maybe Later")
    }

    func testCompletionStepUsesNormalLanguageByDefault() {
        let manager = makeManager()

        XCTAssertEqual(manager.translate("sail_title"), "Ready to Focus")
        XCTAssertEqual(manager.translate("sail_desc"), "Your setup is complete and your settings are saved. You're ready to focus.")
        XCTAssertEqual(manager.translate("sail_btn"), "Start Focusing")
    }

    func testPirateModeDoesNotChangeOnboardingCopy() {
        let manager = makeManager()
        manager.setLanguage(.english, isPirateMode: true)

        XCTAssertFalse(manager.isPirateMode)
        XCTAssertEqual(manager.translate("welcome_btn"), "Get Started")
        XCTAssertEqual(manager.translate("sail_btn"), "Start Focusing")
        XCTAssertEqual(manager.translate("perm_gate_later"), "Maybe Later")
    }

    func testDisablingPirateModeRestoresNormalCopy() {
        let manager = makeManager()
        manager.setLanguage(.english, isPirateMode: true)
        manager.setLanguage(.english, isPirateMode: false)

        XCTAssertEqual(manager.translate("welcome_btn"), "Get Started")
        XCTAssertEqual(manager.translate("sail_btn"), "Start Focusing")
        XCTAssertEqual(manager.translate("perm_gate_later"), "Maybe Later")
    }

    func testPersistedLanguageSelectionIsRespectedAfterRelaunch() {
        let initialManager = makeManager()
        initialManager.setLanguage(.french, isPirateMode: false)

        let relaunchedManager = makeManager()

        XCTAssertEqual(relaunchedManager.currentLanguage, .french)
        XCTAssertFalse(relaunchedManager.isPirateMode)
        XCTAssertEqual(relaunchedManager.translate("welcome_btn"), "Commencer")
    }

    func testOnboardingAndSettingsResolveTheSameActiveLanguageMode() {
        let onboardingManager = makeManager()
        onboardingManager.setLanguage(.spanishLA, isPirateMode: true)

        let settingsManager = makeManager()

        XCTAssertEqual(settingsManager.currentLanguage, onboardingManager.currentLanguage)
        XCTAssertEqual(settingsManager.isPirateMode, onboardingManager.isPirateMode)
        XCTAssertEqual(settingsManager.translate("sail_btn"), "¡Comenzar!")
    }

    func testLegacyPirateSelectionResolvesToPlainEnglish() {
        let manager = makeManager()
        manager.setLanguage(.english, isPirateMode: true)
        manager.setLanguage(.pirate, isPirateMode: true)

        let route = manager.translate("lang_fun_route")

        XCTAssertEqual(route, "Additional Languages")
        XCTAssertEqual(manager.translate("welcome_btn"), "Get Started")
        XCTAssertEqual(manager.translate("sail_btn"), "Start Focusing")
        XCTAssertFalse(route.contains("Ahoy!"))
        XCTAssertFalse(route.contains("matey"))
    }
}

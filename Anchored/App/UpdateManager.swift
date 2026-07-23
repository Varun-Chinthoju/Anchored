import AppKit
import Sparkle

final class UpdateManager: NSObject, NSMenuItemValidation {
    static let shared = UpdateManager()

    private let updatesEnabled: Bool
    private let updaterController: SPUStandardUpdaterController?

    var canCheckForUpdates: Bool {
        updatesEnabled && updaterController?.updater.canCheckForUpdates == true
    }

    init(updatesEnabled: Bool = Bundle.main.anchoredSparkleUpdatesEnabled) {
        self.updatesEnabled = updatesEnabled
        if updatesEnabled {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard canCheckForUpdates, let updaterController else { return }
        updaterController.checkForUpdates(sender)
    }

    func checkForUpdates() {
        checkForUpdates(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        canCheckForUpdates
    }
}

private extension Bundle {
    var anchoredSparkleUpdatesEnabled: Bool {
        guard let value = object(forInfoDictionaryKey: "SPARKLE_UPDATES_ENABLED") as? String else {
            return false
        }

        return value.uppercased() == "YES"
    }
}

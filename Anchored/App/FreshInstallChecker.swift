import Foundation

protocol FreshInstallChecking {
    func shouldShowOnboardingFlow(defaults: UserDefaults) -> Bool
}

struct LiveFreshInstallChecker: FreshInstallChecking {
    private static let onboardingCompletionKey = "hasCompletedOnboarding"
    private static let lastInstalledPathKey = "lastInstalledPath"

    private let fileManager: FileManager
    private let appPathProvider: () -> String

    init(
        fileManager: FileManager = .default,
        appPathProvider: @escaping () -> String = { Bundle.main.executablePath ?? Bundle.main.bundlePath }
    ) {
        self.fileManager = fileManager
        self.appPathProvider = appPathProvider
    }

    func shouldShowOnboardingFlow(defaults: UserDefaults) -> Bool {
        _ = fileManager
        let appPath = appPathProvider()
        let lastPath = defaults.string(forKey: Self.lastInstalledPathKey)

        if lastPath != appPath {
            defaults.set(appPath, forKey: Self.lastInstalledPathKey)
            defaults.set(false, forKey: Self.onboardingCompletionKey)
            return true
        }

        return !defaults.bool(forKey: Self.onboardingCompletionKey)
    }
}

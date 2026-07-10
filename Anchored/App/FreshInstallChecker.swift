import Foundation

protocol FreshInstallChecking {
    func shouldShowOnboardingFlow(defaults: UserDefaults) -> Bool
}

struct LiveFreshInstallChecker: FreshInstallChecking {
    private static let onboardingCompletionKey = "hasCompletedOnboarding"
    private static let lastInstalledModDateKey = "lastInstalledModDate"
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
        let appPath = appPathProvider()
        let attrs = try? fileManager.attributesOfItem(atPath: appPath)
        let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        let lastModDate = defaults.double(forKey: Self.lastInstalledModDateKey)
        let lastPath = defaults.string(forKey: Self.lastInstalledPathKey)

        if lastModDate != modDate || lastPath != appPath {
            defaults.set(modDate, forKey: Self.lastInstalledModDateKey)
            defaults.set(appPath, forKey: Self.lastInstalledPathKey)
            defaults.set(false, forKey: Self.onboardingCompletionKey)
            return true
        }

        return !defaults.bool(forKey: Self.onboardingCompletionKey)
    }
}

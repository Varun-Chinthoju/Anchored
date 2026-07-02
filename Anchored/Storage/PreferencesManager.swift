import Foundation
import Combine
import ServiceManagement

/// A protocol to abstract SMAppService operations for mockability in unit tests.
public protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Manages the application preferences, persisting them in `UserDefaults` and syncing the launch at login setting with `SMAppService`.
public final class PreferencesManager: ObservableObject {
    public static let shared = PreferencesManager()
    
    private let defaults: UserDefaults
    private let loginItemService: LoginItemService
    
    public enum Keys {
        public static let countdownDuration = "com.varun.Anchored.countdownDuration"
        public static let focusThreshold = "com.varun.Anchored.focusThreshold"
        public static let launchAtLogin = "com.varun.Anchored.launchAtLogin"
    }
    
    // Default values
    public static let defaultCountdownDuration = 10
    public static let defaultFocusThreshold: TimeInterval = 600.0
    
    /// The distraction countdown duration in seconds. Clamped to [5, 20].
    @Published public var countdownDuration: Int {
        didSet {
            let clamped = max(5, min(20, countdownDuration))
            if clamped != countdownDuration {
                self.countdownDuration = clamped
            } else {
                defaults.set(clamped, forKey: Keys.countdownDuration)
            }
        }
    }
    
    /// The focus threshold duration in seconds.
    @Published public var focusThreshold: TimeInterval {
        didSet {
            defaults.set(focusThreshold, forKey: Keys.focusThreshold)
        }
    }
    
    /// Whether the app is registered to launch at login.
    @Published public var launchAtLogin: Bool {
        didSet {
            updateLaunchAtLogin(launchAtLogin)
        }
    }
    
    /// Initializes a new instance of `PreferencesManager`.
    /// - Parameters:
    ///   - defaults: The `UserDefaults` instance to use (defaults to `.standard`).
    ///   - loginItemService: The login item service wrapper to use (defaults to `SMAppService.mainApp`).
    public init(defaults: UserDefaults = .standard, loginItemService: LoginItemService = SMAppService.mainApp) {
        self.defaults = defaults
        self.loginItemService = loginItemService
        
        // Load countdown duration
        let storedCountdown = defaults.object(forKey: Keys.countdownDuration) as? Int ?? Self.defaultCountdownDuration
        self.countdownDuration = max(5, min(20, storedCountdown))
        
        // Load focus threshold
        self.focusThreshold = defaults.object(forKey: Keys.focusThreshold) as? TimeInterval ?? Self.defaultFocusThreshold
        
        // Initialize launchAtLogin state based on current SMAppService status
        let serviceStatus = loginItemService.status
        self.launchAtLogin = (serviceStatus == .enabled)
    }
    
    /// Synchronizes the actual SMAppService status back to the published property if modified externally.
    public func refreshLaunchAtLoginStatus() {
        let isRegistered = (loginItemService.status == .enabled)
        if launchAtLogin != isRegistered {
            launchAtLogin = isRegistered
        }
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        let currentStatus = loginItemService.status
        if enabled {
            if currentStatus != .enabled {
                do {
                    try loginItemService.register()
                    defaults.set(true, forKey: Keys.launchAtLogin)
                } catch {
                    print("PreferencesManager Error: Failed to register login item service: \(error.localizedDescription)")
                    defaults.set(false, forKey: Keys.launchAtLogin)
                    
                    // Revert setting on next run loop iteration to avoid triggering didSet recursively synchronously
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if self.launchAtLogin {
                            self.launchAtLogin = false
                        }
                    }
                }
            } else {
                defaults.set(true, forKey: Keys.launchAtLogin)
            }
        } else {
            if currentStatus == .enabled {
                do {
                    try loginItemService.unregister()
                    defaults.set(false, forKey: Keys.launchAtLogin)
                } catch {
                    print("PreferencesManager Error: Failed to unregister login item service: \(error.localizedDescription)")
                    defaults.set(true, forKey: Keys.launchAtLogin)
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if !self.launchAtLogin {
                            self.launchAtLogin = true
                        }
                    }
                }
            } else {
                defaults.set(false, forKey: Keys.launchAtLogin)
            }
        }
    }
}

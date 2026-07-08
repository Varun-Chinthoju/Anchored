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
        public static let focusThresholdOverride = "com.varun.Anchored.focusThresholdOverride"
        public static let launchAtLogin = "com.varun.Anchored.launchAtLogin"
        public static let enableSmartNudges = "com.varun.Anchored.enableSmartNudges"
        public static let focusPromptExperimentEnabled = "com.varun.Anchored.focusPromptExperimentEnabled"
        public static let selectedThemeID = "com.varun.Anchored.selectedThemeID"
        public static let enableImageClassification = "com.varun.Anchored.enableImageClassification"
        public static let useLocalGemma = "com.varun.Anchored.useLocalGemma"
        public static let localModelEndpoint = "com.varun.Anchored.localModelEndpoint"
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
    
    /// Whether background app tracking for Smart Nudges is enabled.
    @Published public var enableSmartNudges: Bool {
        didSet {
            defaults.set(enableSmartNudges, forKey: Keys.enableSmartNudges)
        }
    }

    /// The currently selected theme identifier used by theme-aware settings surfaces.
    @Published public var selectedThemeID: String {
        didSet {
            if !ThemeCatalog.containsTheme(id: selectedThemeID) {
                selectedThemeID = ThemeCatalog.defaultThemeID
                return
            }
            defaults.set(selectedThemeID, forKey: Keys.selectedThemeID)
        }
    }
    
    /// Whether the AI image model is allowed to analyze active application window visuals
    @Published public var enableImageClassification: Bool {
        didSet {
            defaults.set(enableImageClassification, forKey: Keys.enableImageClassification)
        }
    }

    /// Whether to run local Gemma 3 270m or another LLM model for screen classification
    @Published public var useLocalGemma: Bool {
        didSet {
            defaults.set(useLocalGemma, forKey: Keys.useLocalGemma)
        }
    }

    /// The endpoint URL of the local model server (Ollama or llama.cpp)
    @Published public var localModelEndpoint: String {
        didSet {
            defaults.set(localModelEndpoint, forKey: Keys.localModelEndpoint)
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
        
        // Load smart nudges preference
        self.enableSmartNudges = defaults.object(forKey: Keys.enableSmartNudges) as? Bool ?? true

        // Load theme selection
        let storedTheme = defaults.string(forKey: Keys.selectedThemeID) ?? ThemeCatalog.defaultThemeID
        let resolvedTheme = ThemeCatalog.containsTheme(id: storedTheme) ? storedTheme : ThemeCatalog.defaultThemeID
        self.selectedThemeID = resolvedTheme
        if defaults.string(forKey: Keys.selectedThemeID) != resolvedTheme {
            defaults.set(resolvedTheme, forKey: Keys.selectedThemeID)
        }
        
        // Load image classification preferences
        self.enableImageClassification = defaults.object(forKey: Keys.enableImageClassification) as? Bool ?? true
        self.useLocalGemma = defaults.object(forKey: Keys.useLocalGemma) as? Bool ?? false
        self.localModelEndpoint = defaults.string(forKey: Keys.localModelEndpoint) ?? "http://localhost:11434/api/generate"
        
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

    /// The active theme definition resolved from the stored theme identifier.
    public var selectedTheme: AppTheme {
        ThemeCatalog.theme(for: selectedThemeID)
    }

    /// The active palette resolved from the stored theme identifier.
    public var selectedThemePalette: ThemePalette {
        selectedTheme.palette
    }

    /// A hidden launch-time override used for short live verification runs.
    public var runtimeFocusThresholdOverride: TimeInterval? {
        guard let override = defaults.object(forKey: Keys.focusThresholdOverride) as? NSNumber else {
            return nil
        }
        let value = override.doubleValue
        return value > 0 ? value : nil
    }

    /// The focus threshold used by the running engine.
    public var effectiveFocusThreshold: TimeInterval {
        runtimeFocusThresholdOverride ?? focusThreshold
    }

    /// Hidden rollout switch. Auto Voyage remains the fallback when this experiment is disabled.
    public var focusPromptExperimentEnabled: Bool {
        defaults.object(forKey: Keys.focusPromptExperimentEnabled) as? Bool ?? true
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
    
    @Published public var gemmaDownloadStatus: String = "Not Downloaded"

    public func downloadGemmaModel() {
        gemmaDownloadStatus = "Installing mlx-lm..."
        
        DispatchQueue.global(qos: .background).async {
            let installProcess = Process()
            installProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            installProcess.arguments = ["python3", "-m", "pip", "install", "mlx-lm", "pillow"]
            
            do {
                try installProcess.run()
                installProcess.waitUntilExit()
            } catch {
                // continue to download
            }
            
            DispatchQueue.main.async {
                self.gemmaDownloadStatus = "Downloading..."
            }
            
            let downloadProcess = Process()
            downloadProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            downloadProcess.arguments = ["python3", "-c", "import mlx_lm; mlx_lm.load('mlx-community/SmolVLM-256M-Instruct-4bit')"]
            
            do {
                try downloadProcess.run()
                downloadProcess.waitUntilExit()
                
                DispatchQueue.main.async {
                    if downloadProcess.terminationStatus == 0 {
                        self.gemmaDownloadStatus = "Downloaded"
                    } else {
                        self.gemmaDownloadStatus = "Failed (Check python3)"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.gemmaDownloadStatus = "Failed to run python3"
                }
            }
        }
    }
}

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
        public static let automaticSessionDuration = "com.varun.Anchored.automaticSessionDuration"
        public static let launchAtLogin = "com.varun.Anchored.launchAtLogin"
        public static let enableSmartNudges = "com.varun.Anchored.enableSmartNudges"
        public static let focusPromptExperimentEnabled = "com.varun.Anchored.focusPromptExperimentEnabled"
        public static let selectedThemeID = "com.varun.Anchored.selectedThemeID"
        public static let enableImageClassification = "com.varun.Anchored.enableImageClassification"
        public static let useLocalGemma = "com.varun.Anchored.useLocalGemma"
        public static let localModelEndpoint = "com.varun.Anchored.localModelEndpoint"
        public static let enableCloudClassification = "com.varun.Anchored.enableCloudClassification"
        public static let cloudProvider = "com.varun.Anchored.cloudProvider"
        public static let cloudModel = "com.varun.Anchored.cloudModel"
        public static let cloudEndpoint = "com.varun.Anchored.cloudEndpoint"
        public static let contextHistoryEnabled = "com.varun.Anchored.contextHistoryEnabled"
        public static let contextHistoryRetentionDays = "com.varun.Anchored.contextHistoryRetentionDays"
        public static let classificationFeedbackEnabled = "com.varun.Anchored.classificationFeedbackEnabled"
        public static let interactionSummaryEnabled = "com.varun.Anchored.interactionSummaryEnabled"
        public static let enableLocalTextClassification = "com.varun.Anchored.enableLocalTextClassification"
        public static let sessionSummaryPromptEnabled = "com.varun.Anchored.sessionSummaryPromptEnabled"
        public static let weeklyReviewNotificationsEnabled = "com.varun.Anchored.weeklyReviewNotificationsEnabled"
    }
    
    // Default values
    public static let defaultCountdownDuration = 10
    public static let defaultFocusThreshold: TimeInterval = 600.0
    public static let defaultAutomaticSessionDuration: TimeInterval = 25 * 60
    
    public static let defaultEnableCloudClassification = false
    public static let defaultCloudProvider = 0 // 0 = Gemini, 1 = OpenAI, 2 = Anthropic
    public static let defaultCloudModelGemini = "gemini-2.5-flash"
    public static let defaultCloudModelOpenAI = "gpt-4o-mini"
    public static let defaultCloudModelAnthropic = "claude-3-5-haiku"
    public static let defaultCloudEndpointGemini = "https://generativelanguage.googleapis.com/v1beta/models/"
    public static let defaultCloudEndpointOpenAI = "https://api.openai.com/v1/chat/completions"
    public static let defaultCloudEndpointAnthropic = "https://api.anthropic.com/v1/messages"

    public static let defaultContextHistoryEnabled = false
    public static let defaultContextHistoryRetentionDays = 30
    public static let defaultClassificationFeedbackEnabled = false
    public static let defaultInteractionSummaryEnabled = false
    public static let defaultEnableLocalTextClassification = false
    public static let defaultSessionSummaryPromptEnabled = false
    public static let defaultWeeklyReviewNotificationsEnabled = true
    
    /// The distraction countdown duration in seconds. Clamped to [5, 20].
    @Published public var countdownDuration: Int {
        didSet {
            let clamped = max(0, min(3600, countdownDuration))
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

    /// The duration used for sessions started automatically by shadow tracking.
    /// This is deliberately separate from the focus threshold that starts tracking.
    @Published public var automaticSessionDuration: TimeInterval {
        didSet {
            let clamped = max(60, min(24 * 60 * 60, automaticSessionDuration))
            if clamped != automaticSessionDuration {
                self.automaticSessionDuration = clamped
            } else {
                defaults.set(clamped, forKey: Keys.automaticSessionDuration)
            }
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

    /// Whether cloud AI classification is enabled.
    @Published public var enableCloudClassification: Bool {
        didSet {
            defaults.set(enableCloudClassification, forKey: Keys.enableCloudClassification)
        }
    }

    /// The selected cloud provider (0 = Gemini, 1 = OpenAI, 2 = Anthropic)
    @Published public var cloudProvider: Int {
        didSet {
            defaults.set(cloudProvider, forKey: Keys.cloudProvider)
            
            let defaultModel: String
            let defaultEndpoint: String
            switch cloudProvider {
            case 1:
                defaultModel = Self.defaultCloudModelOpenAI
                defaultEndpoint = Self.defaultCloudEndpointOpenAI
            case 2:
                defaultModel = Self.defaultCloudModelAnthropic
                defaultEndpoint = Self.defaultCloudEndpointAnthropic
            default:
                defaultModel = Self.defaultCloudModelGemini
                defaultEndpoint = Self.defaultCloudEndpointGemini
            }
            
            let oldProvider = oldValue
            let oldDefaultModel: String
            let oldDefaultEndpoint: String
            switch oldProvider {
            case 1:
                oldDefaultModel = Self.defaultCloudModelOpenAI
                oldDefaultEndpoint = Self.defaultCloudEndpointOpenAI
            case 2:
                oldDefaultModel = Self.defaultCloudModelAnthropic
                oldDefaultEndpoint = Self.defaultCloudEndpointAnthropic
            default:
                oldDefaultModel = Self.defaultCloudModelGemini
                oldDefaultEndpoint = Self.defaultCloudEndpointGemini
            }
            
            if cloudModel == oldDefaultModel {
                cloudModel = defaultModel
            }
            if cloudEndpoint == oldDefaultEndpoint {
                cloudEndpoint = defaultEndpoint
            }
        }
    }

    /// The selected cloud model name
    @Published public var cloudModel: String {
        didSet {
            defaults.set(cloudModel, forKey: Keys.cloudModel)
        }
    }

    /// The custom or default endpoint URL for the cloud provider
    @Published public var cloudEndpoint: String {
        didSet {
            defaults.set(cloudEndpoint, forKey: Keys.cloudEndpoint)
        }
    }

    /// Whether detailed context history recording is enabled.
    @Published public var contextHistoryEnabled: Bool {
        didSet {
            defaults.set(contextHistoryEnabled, forKey: Keys.contextHistoryEnabled)
        }
    }

    /// Retention in days for context observations.
    @Published public var contextHistoryRetentionDays: Int {
        didSet {
            let clamped = max(1, min(365, contextHistoryRetentionDays))
            if clamped != contextHistoryRetentionDays {
                self.contextHistoryRetentionDays = clamped
            } else {
                defaults.set(clamped, forKey: Keys.contextHistoryRetentionDays)
            }
        }
    }

    /// Whether sanitized correction examples may be stored locally.
    @Published public var classificationFeedbackEnabled: Bool {
        didSet { defaults.set(classificationFeedbackEnabled, forKey: Keys.classificationFeedbackEnabled) }
    }

    /// Whether the memory-only interaction summary may be collected.
    @Published public var interactionSummaryEnabled: Bool {
        didSet { defaults.set(interactionSummaryEnabled, forKey: Keys.interactionSummaryEnabled) }
    }

    /// Whether the experimental local text classifier may promote neutral contexts.
    @Published public var enableLocalTextClassification: Bool {
        didSet { defaults.set(enableLocalTextClassification, forKey: Keys.enableLocalTextClassification) }
    }

    /// Whether Done should offer a local user-authored session summary prompt.
    @Published public var sessionSummaryPromptEnabled: Bool {
        didSet { defaults.set(sessionSummaryPromptEnabled, forKey: Keys.sessionSummaryPromptEnabled) }
    }

    /// Whether the weekly review notification feature is enabled. System permission is separate.
    @Published public var weeklyReviewNotificationsEnabled: Bool {
        didSet { defaults.set(weeklyReviewNotificationsEnabled, forKey: Keys.weeklyReviewNotificationsEnabled) }
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
        self.countdownDuration = max(0, min(3600, storedCountdown))
        
        // Load focus threshold
        self.focusThreshold = defaults.object(forKey: Keys.focusThreshold) as? TimeInterval ?? Self.defaultFocusThreshold

        let storedAutomaticDuration = defaults.object(forKey: Keys.automaticSessionDuration) as? TimeInterval ?? Self.defaultAutomaticSessionDuration
        self.automaticSessionDuration = max(60, min(24 * 60 * 60, storedAutomaticDuration))
        
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
        self.enableImageClassification = defaults.object(forKey: Keys.enableImageClassification) as? Bool ?? false
        self.useLocalGemma = defaults.object(forKey: Keys.useLocalGemma) as? Bool ?? false
        self.localModelEndpoint = defaults.string(forKey: Keys.localModelEndpoint) ?? "http://localhost:11434/api/generate"
        
        // Load cloud classification preferences
        self.enableCloudClassification = defaults.object(forKey: Keys.enableCloudClassification) as? Bool ?? Self.defaultEnableCloudClassification
        
        let storedCloudProvider = defaults.object(forKey: Keys.cloudProvider) as? Int ?? Self.defaultCloudProvider
        let defaultModel: String
        let defaultEndpoint: String
        switch storedCloudProvider {
        case 1:
            defaultModel = Self.defaultCloudModelOpenAI
            defaultEndpoint = Self.defaultCloudEndpointOpenAI
        case 2:
            defaultModel = Self.defaultCloudModelAnthropic
            defaultEndpoint = Self.defaultCloudEndpointAnthropic
        default:
            defaultModel = Self.defaultCloudModelGemini
            defaultEndpoint = Self.defaultCloudEndpointGemini
        }
        
        self.cloudModel = defaults.string(forKey: Keys.cloudModel) ?? defaultModel
        self.cloudEndpoint = defaults.string(forKey: Keys.cloudEndpoint) ?? defaultEndpoint
        self.cloudProvider = storedCloudProvider

        let storedHistoryEnabled = defaults.object(forKey: Keys.contextHistoryEnabled) as? Bool ?? Self.defaultContextHistoryEnabled
        self.contextHistoryEnabled = storedHistoryEnabled

        let storedRetention = defaults.object(forKey: Keys.contextHistoryRetentionDays) as? Int ?? Self.defaultContextHistoryRetentionDays
        let clampedRetention = max(1, min(365, storedRetention))
        self.contextHistoryRetentionDays = clampedRetention
        if clampedRetention != storedRetention {
            defaults.set(clampedRetention, forKey: Keys.contextHistoryRetentionDays)
        }

        self.classificationFeedbackEnabled = defaults.object(forKey: Keys.classificationFeedbackEnabled) as? Bool ?? Self.defaultClassificationFeedbackEnabled
        self.interactionSummaryEnabled = defaults.object(forKey: Keys.interactionSummaryEnabled) as? Bool ?? Self.defaultInteractionSummaryEnabled
        self.enableLocalTextClassification = defaults.object(forKey: Keys.enableLocalTextClassification) as? Bool ?? Self.defaultEnableLocalTextClassification
        self.sessionSummaryPromptEnabled = defaults.object(forKey: Keys.sessionSummaryPromptEnabled) as? Bool ?? Self.defaultSessionSummaryPromptEnabled
        self.weeklyReviewNotificationsEnabled = defaults.object(forKey: Keys.weeklyReviewNotificationsEnabled) as? Bool ?? Self.defaultWeeklyReviewNotificationsEnabled
        
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
            installProcess.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "")]
            installProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            installProcess.arguments = ["python3", "-m", "pip", "install", "mlx-lm", "pillow", "--break-system-packages"]
            
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
            downloadProcess.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "")]
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

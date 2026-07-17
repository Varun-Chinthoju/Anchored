import Combine
import Foundation
import AppKit
import ApplicationServices
import Vision
import ImageIO
import UniformTypeIdentifiers

protocol WindowTextExtracting {
    func extractText() -> String
}

struct LiveOCRProvider: WindowTextExtracting {
    func extractText() -> String {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return ""
        }
        let pid = frontmostApp.processIdentifier
        let windowListInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        var targetWindowID: CGWindowID?
        for info in windowListInfo {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID == pid {
                if let windowID = info[kCGWindowNumber as String] as? CGWindowID {
                    targetWindowID = windowID
                    break
                }
            }
        }
        guard let windowID = targetWindowID,
              let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming) else {
            return ""
        }
        var extractedScreenText = ""
        let textRequest = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            for observation in observations.prefix(20) {
                if let candidate = observation.topCandidates(1).first {
                    extractedScreenText += candidate.string + " "
                }
            }
        }
        textRequest.recognitionLevel = .fast
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try requestHandler.perform([textRequest])
        } catch {}
        return extractedScreenText
    }
}

protocol VisualProductivityChecking {
    func isProductiveVisual(profileName: String) -> Bool
}

struct LiveVisualProductivityChecker: VisualProductivityChecking {
    private let preferences: PreferencesManager

    init(preferences: PreferencesManager = .shared) {
        self.preferences = preferences
    }

    func isProductiveVisual(profileName: String) -> Bool {
        return SmartImageClassifier.isProductiveVisual(profileName: profileName, preferences: preferences)
    }
}

/// The central engine that coordinates focus session tracking and state transitions.
final class FocusEngine {
    private let activityMonitor: ActivityMonitor
    private let distractionListManager: DistractionListManager
    private let sessionStore: SessionStore
    private let profileManager: ProfileManager
    
    private let preferencesManager: PreferencesManager
    private let distractionEvaluator: DistractionEvaluator
    private let classificationResolver: ClassificationResolver
    private let cloudClassificationService: CloudClassificationServing
    private let ocrProvider: WindowTextExtracting
    private let visualChecker: VisualProductivityChecking
    private let interactionSummaryProvider: InteractionSummaryProviding
    private let localTextClassifier: ContextClassifying
    private let intentClassifier: IntentClassifying
    private let classificationOutcomeStore: ClassificationOutcomeRecording
    private let breakReviewChecker: BreakReviewChecking
    private let sessionTimerScheduler: OneShotTimerScheduling
    private let breakTimerScheduler: OneShotTimerScheduling
    private let distractionTimerScheduler: OneShotTimerScheduling
    private let breakReturnGraceTimerScheduler: OneShotTimerScheduling
    private let doomscrollTimerScheduler: OneShotTimerScheduling
    private let focusPromptTimerScheduler: OneShotTimerScheduling
    private let diagnosticsRecorder: DiagnosticsRecording
    private var preferencesCancellables = Set<AnyCancellable>()
    
    /// The delegate to receive state transition callbacks.
    weak var delegate: FocusEngineDelegate?
    
    /// The bundle identifier of the current active application in the foreground.
    private(set) var currentApp: String?
    
    /// The URL of the current active page in the browser (if applicable).
    private(set) var currentURL: URL?
    
    /// The title of the current active window or page.
    private(set) var currentTitle: String = ""
    
    /// The current context of the active window/tab.
    private(set) var currentContext: AppContext?

    /// The identity of the current context.
    private var currentIdentity: ContextIdentity {
        ContextIdentity(
            bundleID: currentApp ?? "",
            sanitizedURL: ContextSanitizer.sanitizePersistedURL(currentURL),
            normalizedTitle: ContextSanitizer.sanitizeTitle(currentTitle)
        )
    }

    /// The latest safe, UI-facing classification decision for the current context.
    private(set) var currentClassification: ClassificationDecision = .neutral()

    /// In-memory cache of resolved model/ML classifications to avoid repeated cloud requests and screenshot analysis.
    private var classificationCache: [ContextIdentity: ClassificationDecision] = [:]

    /// In-progress classifications to avoid concurrent redundant pipelines.
    private var inProgressClassifications: Set<ContextIdentity> = []

    /// The latest intent-relative result for the current context, if any.
    private(set) var currentIntentResult: IntentClassificationResult?
    
    /// The start date of the current work session (focused time).
    var workSessionStart: Date?
    
    /// The active session if the user has anchored.
    var activeSession: ActiveSession?
    
    /// The bundle identifier of the last work/neutral app in the foreground.
    private(set) var lastWorkAppBundleID: String?
    
    /// A flag indicating whether the user is currently being escalated/dimmed.
    private(set) var isDimming = false
    
    /// Declared activity for the temporary bypass.
    private(set) var declaredActivity: String? = nil
    /// A flag indicating if the declared activity bypass is active.
    private(set) var isDeclaredActivityBypassActive = false
    /// Timer checking the declared activity every 2 minutes.
    private var declaredActivityCheckTimer: Timer? = nil
    
    /// Productive time selected in onboarding before a focus session auto-starts.
    var focusThreshold: TimeInterval {
        didSet {
            scheduleFocusPromptTimer()
        }
    }

    /// Whether the onboarding Smart Nudges preference allows proactive automatic starts.
    var focusPromptsEnabled = true {
        didSet {
            if focusPromptsEnabled {
                scheduleFocusPromptTimer()
            } else {
                cancelFocusPromptTimer()
            }
        }
    }
    
    /// The threshold for the distraction countdown pill / grace period (default 30 seconds).
    var distractionCountdownThreshold: TimeInterval = 30.0
    
    // Timers
    private var distractionTimer: OneShotTimerHandle?
    private var distractionTimerGeneration: Int = 0
    private var activeDistractionTimerGeneration: Int?
    private var breakReturnGraceTimer: OneShotTimerHandle?
    private var breakReturnGraceGeneration: Int = 0
    private var activeBreakReturnGraceGeneration: Int?
    private var breakReturnGraceSessionID: UUID?
    private var breakReturnGraceContextGeneration: Int?
    private var breakReturnGraceContextIdentity: ContextIdentity?
    private var sessionTimer: OneShotTimerHandle?
    private var sessionTimerGeneration: Int = 0
    private var activeSessionTimerGeneration: Int?
    private var sessionTimerExpiration: Date?
    private var focusPromptTimer: OneShotTimerHandle?
    private var focusPromptTimerGeneration: Int = 0
    private var activeFocusPromptTimerGeneration: Int?
    private var scheduleTransitionTimer: Timer?
    private var hasPromptedForCurrentFocusRun = false
    private var lastReturnToWorkGeneration: Int?

    private func notifyReturnToWorkOncePerContext() {
        guard lastReturnToWorkGeneration != contextGeneration else { return }
        lastReturnToWorkGeneration = contextGeneration
        delegate?.didReturnToWork()
    }

    private func recordClassificationDecision(_ decision: ClassificationDecision) {
        diagnosticsRecorder.recordClassificationDecision(
            source: decision.source,
            decision: decision.label,
            reason: decision.reason,
            confidence: decision.confidence
        )
    }
    
    // Doomscroll loop breaker
    private var doomscrollTimer: OneShotTimerHandle?
    /// The bundle ID of the app the user started doomscrolling in.
    private(set) var doomscrollingBundleID: String?
    private var doomscrollTimerGeneration: Int = 0
    private var activeDoomscrollTimerGeneration: Int?
    private var doomscrollContextGeneration: Int?
    private var doomscrollContextIdentity: ContextIdentity?
    private var doomscrollThresholdAtSchedule: TimeInterval?
    private var doomscrollStartedAt: Date?
    private(set) var hasFiredDoomscrollAlert = false
    
    // Idle tracking
    var totalIdleTime: TimeInterval = 0.0
    private var idleTimer: Timer?
    
    /// The date when the user entered a distraction app.
    private var distractionStartDate: Date?
    /// The distraction context currently being timed for grace.
    private var distractionBundleID: String?
    
    /// The date when the active focus session was paused.
    public var pausedDate: Date?

    /// The current memory-only break lifecycle, if a break is in flight.
    private(set) var breakState: CommitmentState?
    private(set) var activeBreakCommitment: BreakCommitment?
    private var breakTimer: OneShotTimerHandle?
    private var breakTimerGeneration: Int = 0
    private var activeBreakTimerGeneration: Int?
    private var breakStartedAt: Date?
    private(set) var breakReturnGraceStartedAt: Date?
    private var hasSeenNonFocusContextSinceBreakStarted = false
    /// How long a returned work context must remain stable before a break resumes.
    var breakReturnGraceThreshold: TimeInterval = 15.0
    private var excludedBreakDuration: TimeInterval = 0

    /// The current task intent captured when the active session started.
    private var activeFocusIntent: FocusIntent?

    /// The point at which focus accounting was frozen for sleep or a locked session.
    private var lifecyclePauseStartedAt: Date?
    private var isSleeping = false
    private var isSessionInactive = false

    /// Invalidates optional classifier results whenever the foreground context changes.
    private var contextGeneration = 0

    /// Whether the current time falls inside the user-configured focus schedule.
    private(set) var isFocusScheduleActive = true
    
    /// The current state of the focus engine.
    var state: SessionState {
        if activeSession != nil {
            return .anchored
        } else if workSessionStart != nil {
            return .watching
        } else {
            return .idle
        }
    }
    
    /// Initializes a new FocusEngine.
    init(
        activityMonitor: ActivityMonitor,
        distractionListManager: DistractionListManager,
        sessionStore: SessionStore = .shared,
        profileManager: ProfileManager = .shared,
        focusThreshold: TimeInterval = 600.0,
        preferencesManager: PreferencesManager = .shared,
        ocrProvider: WindowTextExtracting = LiveOCRProvider(),
        visualChecker: VisualProductivityChecking = LiveVisualProductivityChecker(),
        cloudClassificationService: CloudClassificationServing? = nil,
        interactionSummaryProvider: InteractionSummaryProviding? = nil,
        localTextClassifier: ContextClassifying? = nil,
        intentClassifier: IntentClassifying? = nil,
        classificationOutcomeStore: ClassificationOutcomeRecording? = nil,
        breakReviewChecker: BreakReviewChecking = ConservativeBreakReviewChecker(),
        sessionTimerScheduler: OneShotTimerScheduling = LiveOneShotTimerScheduler(),
        breakTimerScheduler: OneShotTimerScheduling = LiveOneShotTimerScheduler(),
        distractionTimerScheduler: OneShotTimerScheduling = LiveOneShotTimerScheduler(),
        breakReturnGraceTimerScheduler: OneShotTimerScheduling = LiveOneShotTimerScheduler(),
        doomscrollTimerScheduler: OneShotTimerScheduling = LiveOneShotTimerScheduler(),
        focusPromptTimerScheduler: OneShotTimerScheduling = LiveOneShotTimerScheduler(),
        diagnosticsRecorder: DiagnosticsRecording = DiagnosticsCenter.shared
    ) {
        self.activityMonitor = activityMonitor
        self.distractionListManager = distractionListManager
        self.sessionStore = sessionStore
        self.profileManager = profileManager
        self.focusThreshold = focusThreshold
        self.preferencesManager = preferencesManager
        self.distractionEvaluator = DistractionEvaluator(
            distractionListManager: distractionListManager,
            profileProvider: { profileManager.activeProfile }
        )
        self.classificationResolver = ClassificationResolver()
        self.ocrProvider = ocrProvider
        self.visualChecker = visualChecker
        self.cloudClassificationService = cloudClassificationService ?? LiveCloudClassificationService(preferences: preferencesManager)
        self.interactionSummaryProvider = interactionSummaryProvider ?? LocalInteractionSummaryProvider()
        self.localTextClassifier = localTextClassifier ?? LocalTextClassifier(preferences: preferencesManager)
        self.intentClassifier = intentClassifier ?? LocalIntentClassifier()
        self.classificationOutcomeStore = classificationOutcomeStore ?? ClassificationOutcomeStore.shared
        self.breakReviewChecker = breakReviewChecker
        self.sessionTimerScheduler = sessionTimerScheduler
        self.breakTimerScheduler = breakTimerScheduler
        self.distractionTimerScheduler = distractionTimerScheduler
        self.breakReturnGraceTimerScheduler = breakReturnGraceTimerScheduler
        self.doomscrollTimerScheduler = doomscrollTimerScheduler
        self.focusPromptTimerScheduler = focusPromptTimerScheduler
        self.diagnosticsRecorder = diagnosticsRecorder
        
        self.activityMonitor.onContextChange = { [weak self] snapshot in
            self?.handleContextChange(bundleID: snapshot.bundleIdentifier, url: snapshot.url, title: snapshot.title, snapshot: snapshot)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleActiveProfileChange),
            name: .activeProfileDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfilesDidChange),
            name: .profilesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScheduleChange),
            name: .focusScheduleDidChange,
            object: preferencesManager
        )
        preferencesManager.$enableDoomscrollLoopBreaker
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.refreshDoomscrollTimerIfNeeded(loopBreakerEnabled: isEnabled)
            }
            .store(in: &preferencesCancellables)
        preferencesManager.$doomscrollThreshold
            .dropFirst()
            .sink { [weak self] threshold in
                self?.refreshDoomscrollTimerIfNeeded(threshold: threshold)
            }
            .store(in: &preferencesCancellables)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceSessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceSessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    /// Starts monitoring application switch events.
    func start() {
        RuntimeTrace.event("focus_engine_start", fields: [
            "focusThreshold": String(focusThreshold),
            "promptsEnabled": String(focusPromptsEnabled)
        ])
        refreshScheduleState()
        activityMonitor.start()
    }
    
    /// Stops monitoring application switch events.
    func stop() {
        RuntimeTrace.event("focus_engine_stop")
        activityMonitor.stop()
        cancelSessionTimer(reason: .engineStopped)
        cancelDistractionTimer()
        cancelFocusPromptTimer()
        cancelScheduleTransitionTimer()
        cancelIdleTimer()
        cancelBreakTimer()
        cancelBreakReturnGraceTimer()
        resetDoomscrollTimer()
        clearBreakState(at: Date())
    }

    @objc private func handleWorkspaceWillSleep() {
        isSleeping = true
        pauseFocusAccountingForWorkspaceLifecycle()
    }

    @objc private func handleWorkspaceDidWake() {
        isSleeping = false
        resumeFocusAccountingIfActive()
    }

    @objc private func handleWorkspaceSessionDidResignActive() {
        isSessionInactive = true
        pauseFocusAccountingForWorkspaceLifecycle()
    }

    @objc private func handleWorkspaceSessionDidBecomeActive() {
        isSessionInactive = false
        resumeFocusAccountingIfActive()
    }

    internal func pauseFocusAccountingForWorkspaceLifecycle(now: Date = Date()) {
        guard lifecyclePauseStartedAt == nil else { return }
        lifecyclePauseStartedAt = now

        cancelSessionTimer(reason: .workspacePaused)
        cancelDistractionTimer()
        cancelFocusPromptTimer()
        cancelIdleTimer()
        cancelBreakTimer()
        cancelDeclaredActivityCheckTimer()
        cancelBreakReturnGraceTimer()
        cancelDoomscrollTimer()

        diagnosticsRecorder.recordWorkspaceLifecycle(action: .paused, pauseSeconds: nil)
        RuntimeTrace.event("focus_accounting_paused_for_workspace_lifecycle", fields: [
            "activeSession": String(activeSession != nil),
            "watching": String(workSessionStart != nil)
        ])
    }

    internal func resumeFocusAccountingForWorkspaceLifecycle(now: Date = Date()) {
        guard let pauseStartedAt = lifecyclePauseStartedAt else { return }
        let pauseDuration = max(0, now.timeIntervalSince(pauseStartedAt))
        lifecyclePauseStartedAt = nil

        if let workSessionStart {
            self.workSessionStart = workSessionStart.addingTimeInterval(pauseDuration)
        }
        if let activeSession {
            self.activeSession = ActiveSession(
                startDate: activeSession.startDate.addingTimeInterval(pauseDuration),
                anchoredDuration: activeSession.anchoredDuration,
                appName: activeSession.appName,
                category: activeSession.category,
                goal: activeSession.goal
            )
        }
        if let distractionStartDate {
            self.distractionStartDate = distractionStartDate.addingTimeInterval(pauseDuration)
        }
        if let pausedDate {
            self.pausedDate = pausedDate.addingTimeInterval(pauseDuration)
        }
        if let breakStartedAt {
            self.breakStartedAt = breakStartedAt.addingTimeInterval(pauseDuration)
        }

        if let session = activeSession {
            if breakState == .breakActive, activeBreakCommitment != nil, let breakStartedAt {
                scheduleBreakTimer(duration: max(0, CommitmentPolicy.breakDuration - now.timeIntervalSince(breakStartedAt)))
            } else if !isDimming {
                startIdleTimer()
                scheduleSessionTimer(duration: max(0, session.anchoredDuration - currentSessionFocusedTime(at: now)))
            }
        } else if workSessionStart != nil {
            scheduleFocusPromptTimer()
        }

        if let bundleID = currentApp,
           distractionStartDate != nil,
           activeSession != nil,
           !isDimming,
           activeBreakCommitment == nil {
            scheduleDistractionTimer(distractionBundleID: bundleID)
        }
        if isDeclaredActivityBypassActive {
            scheduleDeclaredActivityCheckTimer()
        }
        if doomscrollingBundleID != nil, !hasFiredDoomscrollAlert {
            refreshDoomscrollTimerIfNeeded(observedAt: now)
        }

        RuntimeTrace.event("focus_accounting_resumed_after_workspace_lifecycle", fields: [
            "pauseSeconds": String(pauseDuration)
        ])
        diagnosticsRecorder.recordWorkspaceLifecycle(action: .resumed, pauseSeconds: pauseDuration)
    }

    private func resumeFocusAccountingIfActive() {
        guard !isSleeping, !isSessionInactive else { return }
        resumeFocusAccountingForWorkspaceLifecycle()
    }

    func refreshScheduleState(now: Date = Date()) {
        let schedule = preferencesManager.focusSchedule.normalized()
        let wasActive = isFocusScheduleActive
        let isActive = schedule.enabled ? schedule.isActive(at: now) : true
        isFocusScheduleActive = isActive

        if !schedule.enabled {
            cancelScheduleTransitionTimer()
            if wasActive != isActive {
                handleFocusScheduleTransition(isActive: true, now: now)
            }
            return
        }

        if wasActive != isActive {
            handleFocusScheduleTransition(isActive: isActive, now: now)
        }

        scheduleFocusScheduleTransitionTimer(from: now, schedule: schedule)
    }

    private func handleFocusScheduleTransition(isActive: Bool, now: Date) {
        if isActive {
            if activeSession != nil {
                if let bundleID = currentApp,
                   currentClassification.isDistraction,
                   distractionStartDate == nil,
                   !isDimming {
                    distractionStartDate = now
                    scheduleDistractionTimer(distractionBundleID: bundleID, observedAt: now)
                } else if isDimming {
                    resumeSessionIfNeeded()
                }
            } else if workSessionStart != nil {
                scheduleFocusPromptTimer()
            }

            refreshDoomscrollTimerIfNeeded(observedAt: now)
        } else {
            cancelFocusPromptTimer()
            cancelDistractionTimer()
            cancelDoomscrollTimer()

            if isDimming {
                isDimming = false
                pausedDate = nil
                notifyReturnToWorkOncePerContext()
            }

            if activeSession != nil {
                resumeSessionIfNeeded()
            } else {
                resetFocusTracking()
            }

            distractionStartDate = nil
        }

        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    private func scheduleFocusScheduleTransitionTimer(from now: Date, schedule: FocusSchedule) {
        cancelScheduleTransitionTimer()
        guard let nextTransition = schedule.nextTransition(after: now) else { return }
        let remaining = max(0, nextTransition.timeIntervalSince(now))
        scheduleTransitionTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.refreshScheduleState()
        }
    }

    private func cancelScheduleTransitionTimer() {
        scheduleTransitionTimer?.invalidate()
        scheduleTransitionTimer = nil
    }
    
    private func classifyContext(bundleID: String, url: URL?, title: String) -> ClassificationDecision {
        classificationResolver.resolve(
            distractionEvaluator.evidence(bundleID: bundleID, url: url, title: title),
            interactionSummary: preferencesManager.interactionSummaryEnabled
                ? interactionSummaryProvider.summary(at: Date())
                : nil
        )
    }

    private func shouldImmediatelyResumeSession(for snapshot: ContextSnapshot, decision: ClassificationDecision) -> Bool {
        guard decision.isFocus else { return false }

        if decision.source.isExplicitRule {
            return true
        }

        guard let baseline = activeFocusIntent?.baseline else {
            return false
        }

        return baseline.identity == snapshot.identity
    }

    func suggestedSessionGoal() -> String? {
        if shouldSuppressSuggestedGoalCandidate(
            bundleID: currentContext?.bundleIdentifier ?? currentApp,
            url: currentURL,
            title: currentTitle
        ) {
            return nil
        }

        let candidates: [String?] = [
            ContextSanitizer.sanitizeTitle(currentTitle),
            currentURL?.host?.replacingOccurrences(of: "www.", with: "")
        ]

        for candidate in candidates {
            guard let cleaned = Self.cleanedSuggestedLabel(candidate),
                  !Self.isGenericSuggestedLabel(cleaned) else {
                continue
            }
            return cleaned
        }

        return nil
    }

    func suggestedSessionProfile() -> WorkProfile {
        Self.bestSuggestedProfile(
            bundleID: currentApp ?? currentContext?.bundleIdentifier,
            url: currentURL,
            title: currentTitle,
            profiles: profileManager.profiles,
            fallback: profileManager.activeProfile
        )
    }

    private func isDistraction(bundleID: String, url: URL?, title: String) -> Bool {
        classifyContext(bundleID: bundleID, url: url, title: title).isDistraction
    }

    private func isFocusContext(bundleID: String, url: URL?, title: String) -> Bool {
        classifyContext(bundleID: bundleID, url: url, title: title).isFocus
    }

    private static func isSensitiveContext(bundleID: String, url: URL?, title: String) -> Bool {
        let bundleLower = bundleID.lowercased()
        let titleLower = title.lowercased()
        let urlLower = url?.absoluteString.lowercased() ?? ""
        
        // Exclude system keychain / password managers
        if bundleLower.contains("keychain") || bundleLower.contains("1password") || bundleLower.contains("bitwarden") || bundleLower.contains("keepass") {
            return true
        }
        
        let sensitiveKeywords = [
            "bank", "finance", "checkout", "paypal", "stripe", "chase", "wellsfargo", "fidelity",
            "login", "signin", "signup", "register", "verification", "security", "auth", "portal",
            "password", "creditcard", "billing", "tax", "sensitive"
        ]
        
        for keyword in sensitiveKeywords {
            if titleLower.contains(keyword) || urlLower.contains(keyword) {
                return true
            }
        }
        
        return false
    }

    private func triggerCloudOrVisualFallback(bundleID: String, url: URL?, title: String, generation: Int) {
        let targetIdentity = ContextIdentity(bundleID: bundleID, sanitizedURL: ContextSanitizer.sanitizePersistedURL(url), normalizedTitle: ContextSanitizer.sanitizeTitle(title))
        let isStale = (generation != self.contextGeneration) && (self.currentIdentity != targetIdentity)
        if isStale {
            inProgressClassifications.remove(targetIdentity)
            return
        }

        if preferencesManager.enableCloudClassification {
            RuntimeTrace.event("fallback_cloud_selected", fields: ["bundleID": bundleID, "generation": String(generation)])
            triggerAsyncCloudClassification(bundleID: bundleID, url: url, title: title, generation: generation)
        } else if preferencesManager.enableImageClassification {
            RuntimeTrace.event("fallback_visual_selected", fields: ["bundleID": bundleID, "generation": String(generation)])
            triggerAsyncVisualClassification(bundleID: bundleID, url: url, title: title, generation: generation)
        } else {
            RuntimeTrace.event("fallbacks_disabled", fields: ["bundleID": bundleID, "generation": String(generation)])
            // End of pipeline, cache as neutral
            classificationCache[targetIdentity] = .neutral()
            inProgressClassifications.remove(targetIdentity)
        }
    }

    private func triggerAsyncCloudClassification(bundleID: String, url: URL?, title: String, generation: Int) {
        let targetIdentity = ContextIdentity(bundleID: bundleID, sanitizedURL: ContextSanitizer.sanitizePersistedURL(url), normalizedTitle: ContextSanitizer.sanitizeTitle(title))
        let isStale = (generation != self.contextGeneration) && (self.currentIdentity != targetIdentity)
        if isStale {
            inProgressClassifications.remove(targetIdentity)
            return
        }

        guard preferencesManager.enableCloudClassification else {
            if preferencesManager.enableImageClassification {
                triggerAsyncVisualClassification(bundleID: bundleID, url: url, title: title, generation: generation)
            } else {
                classificationCache[targetIdentity] = .neutral()
                inProgressClassifications.remove(targetIdentity)
            }
            return
        }

        let input = CloudClassificationFeatureExtractor.make(
            appName: getAppName(for: bundleID),
            bundleID: bundleID,
            url: url,
            title: title,
            source: bundleID == "com.apple.Safari"
                ? .safari
                : (BrowserStrategyFactory.isSupportedBrowser(bundleID) ? .chromium : .application)
        )
        RuntimeTrace.event("cloud_classification_started", fields: [
            "bundleID": bundleID,
            "generation": String(generation),
            "appCategory": input.appCategory.rawValue,
            "domainCategory": input.domainCategory.rawValue,
            "titleFeatures": input.titleFeatures.map(\.rawValue).joined(separator: ","),
            "source": input.source.rawValue
        ])
        cloudClassificationService.classify(input) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                let identity = ContextIdentity(bundleID: bundleID, sanitizedURL: ContextSanitizer.sanitizePersistedURL(url), normalizedTitle: ContextSanitizer.sanitizeTitle(title))
                let isActiveContext = (self.currentIdentity == identity)

                guard generation == self.contextGeneration else {
                    self.classificationCache.removeValue(forKey: identity)
                    self.inProgressClassifications.remove(identity)
                    return
                }

                switch result {
                case .success(let evidence):
                    RuntimeTrace.event("cloud_classification_finished", fields: [
                        "bundleID": bundleID,
                        "label": evidence.label.rawValue,
                        "confidence": String(evidence.confidence),
                        "latencyMs": String(Int(evidence.latency * 1000))
                    ])
                case .failure:
                    RuntimeTrace.event("cloud_classification_failed", fields: ["bundleID": bundleID])
                }

                var promoted = false
                if case .success(let evidence) = result,
                   evidence.label == .productive,
                   evidence.confidence >= ClassificationPolicy.highConfidenceThreshold {
                    
                    let currentEvidence = self.distractionEvaluator.evidence(bundleID: bundleID, url: url, title: title)
                    let promotionEvidence = ClassificationEvidence(
                        label: .productive,
                        source: .cloudModel,
                        confidence: evidence.confidence,
                        reason: .modelEvidence
                    )
                    let promotedDecision = self.classificationResolver.resolve(currentEvidence + [promotionEvidence])
                    
                    if promotedDecision.isFocus {
                        self.classificationCache[identity] = promotedDecision
                        self.inProgressClassifications.remove(identity)
                        promoted = true
                        
                        let isCurrentlyActive = (generation == self.contextGeneration) || isActiveContext
                        if isCurrentlyActive {
                            self.applyPromotedFocus(bundleID: bundleID)
                            self.currentClassification = promotedDecision
                            self.recordClassificationDecision(promotedDecision)
                            NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)
                            self.persistClassificationOutcome(
                                snapshot: ContextSnapshot(
                                    bundleIdentifier: bundleID,
                                    localizedName: self.getAppName(for: bundleID),
                                    url: url,
                                    title: title,
                                    source: BrowserStrategyFactory.isSupportedBrowser(bundleID)
                                        ? (bundleID == "com.apple.Safari" ? .safari : .chromium)
                                        : .application,
                                    observedAt: Date()
                                ),
                                decision: promotedDecision,
                                intentResult: nil,
                                graceStarted: false,
                                enforcementOccurred: false
                            )
                        }
                    }
                }

                if promoted {
                    return
                }

                if self.preferencesManager.enableImageClassification {
                    RuntimeTrace.event("cloud_did_not_promote_using_visual_fallback", fields: ["bundleID": bundleID])
                    self.triggerAsyncVisualClassification(bundleID: bundleID, url: url, title: title, generation: generation)
                } else {
                    RuntimeTrace.event("cloud_did_not_promote_no_visual_fallback", fields: ["bundleID": bundleID])
                    self.classificationCache[identity] = .neutral()
                    self.inProgressClassifications.remove(identity)
                }
            }
        }
    }

    private func triggerAsyncVisualClassification(bundleID: String, url: URL?, title: String, generation: Int) {
        let targetIdentity = ContextIdentity(bundleID: bundleID, sanitizedURL: ContextSanitizer.sanitizePersistedURL(url), normalizedTitle: ContextSanitizer.sanitizeTitle(title))
        let isStale = (generation != self.contextGeneration) && (self.currentIdentity != targetIdentity)
        if isStale {
            inProgressClassifications.remove(targetIdentity)
            return
        }

        guard preferencesManager.enableImageClassification else {
            classificationCache[targetIdentity] = .neutral()
            inProgressClassifications.remove(targetIdentity)
            return
        }

        // Skip visual check for sensitive contexts (protect privacy and avoid false positives)
        if FocusEngine.isSensitiveContext(bundleID: bundleID, url: url, title: title) {
            RuntimeTrace.event("visual_classification_skipped_sensitive", fields: ["bundleID": bundleID])
            self.classificationCache[targetIdentity] = .neutral()
            inProgressClassifications.remove(targetIdentity)
            return
        }

        let profileName = profileManager.activeProfile.name
        RuntimeTrace.event("visual_classification_started", fields: ["bundleID": bundleID, "generation": String(generation)])
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

             var isBackgroundStale = false
             DispatchQueue.main.sync {
                 let identityMatches = (generation == self.contextGeneration) && (self.currentIdentity == targetIdentity)
                 var frontAppMatches = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID)
                 if NSClassFromString("XCTestCase") != nil {
                     frontAppMatches = true
                 }
                 isBackgroundStale = !identityMatches || !frontAppMatches
             }
            if isBackgroundStale {
                DispatchQueue.main.async { [weak self] in
                    self?.classificationCache.removeValue(forKey: targetIdentity)
                    self?.inProgressClassifications.remove(targetIdentity)
                }
                return
            }

            let isProductive = self.visualChecker.isProductiveVisual(profileName: profileName) == true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                let isActiveContext = (self.currentIdentity == targetIdentity)

                guard generation == self.contextGeneration else {
                    self.classificationCache.removeValue(forKey: targetIdentity)
                    self.inProgressClassifications.remove(targetIdentity)
                    return
                }

                self.inProgressClassifications.remove(targetIdentity)

                if isProductive {
                    let currentEvidence = self.distractionEvaluator.evidence(bundleID: bundleID, url: url, title: title)
                    let promotionEvidence = ClassificationEvidence(
                        label: .productive,
                        source: .visualFallback,
                        confidence: 0.85,
                        reason: .modelEvidence
                    )
                    let promotedDecision = self.classificationResolver.resolve(currentEvidence + [promotionEvidence])

                    if promotedDecision.isFocus {
                        self.classificationCache[targetIdentity] = promotedDecision

                        let isCurrentlyActive = (generation == self.contextGeneration) || isActiveContext
                        if isCurrentlyActive {
                            self.applyPromotedFocus(bundleID: bundleID)
                            self.currentClassification = promotedDecision
                            self.recordClassificationDecision(promotedDecision)
                            NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)
                            self.persistClassificationOutcome(
                                snapshot: ContextSnapshot(
                                    bundleIdentifier: bundleID,
                                    localizedName: self.getAppName(for: bundleID),
                                    url: url,
                                    title: title,
                                    source: BrowserStrategyFactory.isSupportedBrowser(bundleID)
                                        ? (bundleID == "com.apple.Safari" ? .safari : .chromium)
                                        : .application,
                                    observedAt: Date()
                                ),
                                decision: promotedDecision,
                                intentResult: nil,
                                graceStarted: false,
                                enforcementOccurred: false
                            )
                        }
                        return
                    }
                }

                // If not productive/promoted:
                self.classificationCache[targetIdentity] = .neutral()
            }
        }
    }

    private func applyPromotedFocus(bundleID: String) {
        lastWorkAppBundleID = bundleID
        if activeSession != nil {
            let needsUIUpdate = distractionStartDate != nil && !isDimming
            resumeSessionIfNeeded()
            if needsUIUpdate {
                notifyReturnToWorkOncePerContext()
            }
            cancelDistractionTimer()
            distractionStartDate = nil
        } else {
            if workSessionStart == nil {
                workSessionStart = Date()
                hasPromptedForCurrentFocusRun = false
            }
            scheduleFocusPromptTimer()
        }
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    @discardableResult
    private func promoteNeutralContextIfCurrent(
        bundleID: String,
        url: URL?,
        title: String,
        generation: Int,
        promotion: ClassificationEvidence
    ) -> Bool {
        let identity = ContextIdentity(bundleID: bundleID, sanitizedURL: ContextSanitizer.sanitizePersistedURL(url), normalizedTitle: ContextSanitizer.sanitizeTitle(title))
        guard generation == contextGeneration,
              self.currentIdentity == identity,
              classifyContext(bundleID: bundleID, url: url, title: title).isNeutral else {
            return false
        }

        let currentEvidence = distractionEvaluator.evidence(bundleID: bundleID, url: url, title: title)
        let promotedDecision = classificationResolver.resolve(currentEvidence + [promotion])
        // ONLY promote to focus (productive). Distraction model output is advisory and non-enforcing.
        guard promotedDecision.isFocus else {
            return false
        }

        currentClassification = promotedDecision
        recordClassificationDecision(promotedDecision)
        classificationCache[identity] = promotedDecision
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)

        applyPromotedFocus(bundleID: bundleID)

        persistClassificationOutcome(
            snapshot: ContextSnapshot(
                bundleIdentifier: bundleID,
                localizedName: getAppName(for: bundleID),
                url: url,
                title: title,
                source: BrowserStrategyFactory.isSupportedBrowser(bundleID)
                    ? (bundleID == "com.apple.Safari" ? .safari : .chromium)
                    : .application,
                observedAt: Date()
            ),
            decision: promotedDecision,
            intentResult: nil,
            graceStarted: false,
            enforcementOccurred: false
        )
        
        return true
    }
    
    @objc private func handleActiveProfileChange() {
        contextGeneration += 1
        classificationCache.removeAll()
        inProgressClassifications.removeAll()
        guard let currentApp = currentApp else { return }
        
        let now = Date()
        let currentSnapshot = ContextSnapshot(
            bundleIdentifier: currentApp,
            localizedName: getAppName(for: currentApp),
            url: currentURL,
            title: currentTitle,
            source: BrowserStrategyFactory.isSupportedBrowser(currentApp) ? (currentApp == "com.apple.Safari" ? .safari : .chromium) : .application,
            observedAt: now
        )
        let decision = classifyContext(
            bundleID: currentApp,
            url: currentURL,
            title: currentTitle
        )
        currentClassification = decision
        recordClassificationDecision(decision)
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)
        persistClassificationOutcome(
            snapshot: currentSnapshot,
            decision: decision,
            intentResult: nil,
            graceStarted: false,
            enforcementOccurred: isDimming
        )
        if activeBreakCommitment != nil {
            updateBreakReturnGrace(for: decision, snapshot: currentSnapshot, observedAt: now)
            return
        }
        if activeSession != nil,
           activeFocusIntent?.hasIntentSignal == true,
           !decision.source.isExplicitRule,
           activeBreakCommitment == nil,
           !isDeclaredActivityBypassActive {
            triggerAsyncIntentClassification(
                snapshot: currentSnapshot,
                generation: contextGeneration,
                baseDecision: decision
            )
        }
        let isCurrentlyDistraction = decision.isDistraction
        
        if isCurrentlyDistraction {
            // It is now a distraction under the new active profile
            if activeSession != nil {
                // If we have an active session
                if distractionStartDate == nil {
                    // It wasn't previously flagged as a distraction
                    distractionStartDate = now
                    
                    let event = SessionEvent(
                        type: .distractionDetected,
                        appBundleID: lastWorkAppBundleID ?? "",
                        appName: getAppName(for: lastWorkAppBundleID ?? ""),
                        url: currentURL?.absoluteString,
                        distractionAppBundleID: currentApp,
                        distraction_domain: currentURL?.host
                    )
                    sessionStore.log(event)
                    
                    delegate?.didDetectDistraction(bundleID: currentApp)
                    scheduleDistractionTimer(distractionBundleID: currentApp)
                    persistClassificationOutcome(
                        snapshot: currentSnapshot,
                        decision: decision,
                        intentResult: currentIntentResult,
                        graceStarted: true,
                        enforcementOccurred: isDimming
                    )
                }
            } else if workSessionStart != nil {
                // No active session: automatically convert the completed focus run into a session.
                if !requestFocusPromptIfEligible(now: now) {
                    resetFocusTracking()
                }
            }
        } else {
            // It is now allowed (NOT a distraction) under the new active profile
            if activeSession != nil {
                // Cancel warning/dimming
                if isDimming {
                    isDimming = false
                    notifyReturnToWorkOncePerContext()
                }
                cancelDistractionTimer()
                distractionStartDate = nil
            } else {
                // No active session: it is now a work or neutral app
                if decision.isFocus {
                    lastWorkAppBundleID = currentApp
                    if workSessionStart == nil {
                        workSessionStart = now
                        hasPromptedForCurrentFocusRun = false
                    }
                    scheduleFocusPromptTimer()
                }
            }
        }
    }

    @objc private func handleProfilesDidChange() {
        contextGeneration += 1
        classificationCache.removeAll()
        inProgressClassifications.removeAll()
        guard let currentApp = currentApp else { return }
        
        let now = Date()
        let currentSnapshot = ContextSnapshot(
            bundleIdentifier: currentApp,
            localizedName: getAppName(for: currentApp),
            url: currentURL,
            title: currentTitle,
            source: BrowserStrategyFactory.isSupportedBrowser(currentApp) ? (currentApp == "com.apple.Safari" ? .safari : .chromium) : .application,
            observedAt: now
        )
        let decision = classifyContext(
            bundleID: currentApp,
            url: currentURL,
            title: currentTitle
        )
        currentClassification = decision
        recordClassificationDecision(decision)
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)
        persistClassificationOutcome(
            snapshot: currentSnapshot,
            decision: decision,
            intentResult: nil,
            graceStarted: false,
            enforcementOccurred: isDimming
        )
        if activeBreakCommitment != nil {
            updateBreakReturnGrace(for: decision, snapshot: currentSnapshot, observedAt: now)
            return
        }
        if activeSession != nil,
           activeFocusIntent?.hasIntentSignal == true,
           !decision.source.isExplicitRule,
           activeBreakCommitment == nil,
           !isDeclaredActivityBypassActive {
            triggerAsyncIntentClassification(
                snapshot: currentSnapshot,
                generation: contextGeneration,
                baseDecision: decision
            )
        }
        let isCurrentlyDistraction = decision.isDistraction
        
        if isCurrentlyDistraction {
            // It is now a distraction under the new active profile
            if activeSession != nil {
                // If we have an active session
                if distractionStartDate == nil {
                    // It wasn't previously flagged as a distraction
                    distractionStartDate = now
                    
                    let event = SessionEvent(
                        type: .distractionDetected,
                        appBundleID: lastWorkAppBundleID ?? "",
                        appName: getAppName(for: lastWorkAppBundleID ?? ""),
                        url: currentURL?.absoluteString,
                        distractionAppBundleID: currentApp,
                        distraction_domain: currentURL?.host
                    )
                    sessionStore.log(event)
                    
                    delegate?.didDetectDistraction(bundleID: currentApp)
                    scheduleDistractionTimer(distractionBundleID: currentApp)
                    persistClassificationOutcome(
                        snapshot: currentSnapshot,
                        decision: decision,
                        intentResult: currentIntentResult,
                        graceStarted: true,
                        enforcementOccurred: isDimming
                    )
                }
            } else if workSessionStart != nil {
                // No active session: automatically convert the completed focus run into a session.
                if !requestFocusPromptIfEligible(now: now) {
                    resetFocusTracking()
                }
            }
        } else {
            // It is now allowed (NOT a distraction) under the new active profile
            if activeSession != nil {
                // Cancel warning/dimming
                if isDimming {
                    isDimming = false
                    delegate?.didReturnToWork()
                }
                cancelDistractionTimer()
                distractionStartDate = nil
            } else {
                // No active session: it is now a work or neutral app
                if decision.isFocus {
                    lastWorkAppBundleID = currentApp
                    if workSessionStart == nil {
                        workSessionStart = now
                        hasPromptedForCurrentFocusRun = false
                    }
                    scheduleFocusPromptTimer()
                }
            }
        }
    }
    @objc private func handleScheduleChange() {
        refreshScheduleState()
    }
    
    /// Handles context changes from the activity monitor.
    private func handleContextChange(bundleID: String, url: URL?, title: String, snapshot: ContextSnapshot? = nil) {
        guard bundleID != "com.varun.Anchored",
              !SystemContextPolicy.shouldIgnore(bundleID: bundleID) else {
            RuntimeTrace.event("system_context_ignored", fields: ["bundleID": bundleID])
            return
        }
        
        currentApp = bundleID
        currentURL = url
        currentTitle = title
        contextGeneration += 1
        let now = Date()
        if preferencesManager.interactionSummaryEnabled {
            interactionSummaryProvider.beginContext(at: now)
        }
        
        let context = AppContext(
            bundleIdentifier: bundleID,
            localizedName: getAppName(for: bundleID),
            title: title
        )
        currentContext = context
        
        let actualSnapshot = snapshot ?? ContextSnapshot(
            bundleIdentifier: bundleID,
            localizedName: context.localizedName,
            url: url,
            title: title,
            source: BrowserStrategyFactory.isSupportedBrowser(bundleID) ? (bundleID == "com.apple.Safari" ? .safari : .chromium) : .application,
            observedAt: now
        )
        
        let decision: ClassificationDecision
        if let cached = classificationCache[actualSnapshot.identity] {
            decision = cached
            RuntimeTrace.event("context_decision_cached", fields: [
                "bundleID": bundleID,
                "label": decision.label.rawValue,
                "source": decision.source.rawValue
            ])
            if cached.isFocus {
                applyPromotedFocus(bundleID: bundleID)
            }
        } else {
            let baseDecision = classifyContext(bundleID: bundleID, url: url, title: title)
            if !baseDecision.isNeutral {
                decision = baseDecision
                classificationCache[actualSnapshot.identity] = decision
            } else {
                decision = baseDecision // neutral
            }
        }

        currentClassification = decision
        recordClassificationDecision(decision)
        RuntimeTrace.event("context_decision", fields: [
            "bundleID": bundleID,
            "generation": String(contextGeneration),
            "label": decision.label.rawValue,
            "source": decision.source.rawValue,
            "reason": decision.reason.rawValue,
            "confidence": String(decision.confidence),
            "evidence": decision.evidence.map { "\($0.source.rawValue):\($0.label.rawValue):\($0.reason.rawValue)" }.joined(separator: ","),
            "activeSession": String(activeSession != nil),
            "dimming": String(isDimming),
            "urlPresent": String(url != nil),
            "titleLength": String(title.count)
        ])
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)
        let isFocus = decision.isFocus
        let sanitizedDomain = url?.host ?? "nil"
        print("📱 [Context Switch] bundleID=\(bundleID) appName=\(context.localizedName) domain=\(sanitizedDomain) focus=\(isFocus) titleLen=\(title.count)")
        
        NotificationCenter.default.post(
            name: .focusEngineContextDidChange,
            object: self,
            userInfo: [
                "bundleID": bundleID,
                "url": url as Any,
                "title": title,
                "isFocus": isFocus,
                "context": context,
                "snapshot": actualSnapshot
            ]
        )

        persistClassificationOutcome(
            snapshot: actualSnapshot,
            decision: decision,
            intentResult: nil,
            graceStarted: false,
            enforcementOccurred: false
        )
        refreshScheduleState(now: now)
        if activeBreakCommitment != nil {
            updateBreakReturnGrace(for: decision, snapshot: actualSnapshot, observedAt: now)
            return
        }

        if activeSession != nil,
           activeFocusIntent?.hasIntentSignal == true,
           !decision.source.isExplicitRule,
           activeBreakCommitment == nil,
           !isDeclaredActivityBypassActive {
            triggerAsyncIntentClassification(
                snapshot: actualSnapshot,
                generation: contextGeneration,
                baseDecision: decision
            )
        }

        if decision.isNeutral && classificationCache[actualSnapshot.identity] == nil {
            let identity = actualSnapshot.identity
            if !inProgressClassifications.contains(identity) {
                classificationCache[identity] = .neutral()
                inProgressClassifications.insert(identity)
                runClassificationPipeline(snapshot: actualSnapshot, generation: contextGeneration)
            }
        }

        // A committed break or declared activity bypass suspends normal enforcement
        if activeBreakCommitment != nil || isDeclaredActivityBypassActive {
            return
        }

        guard isFocusScheduleActive else {
            cancelFocusPromptTimer()
            cancelDistractionTimer()
            cancelDoomscrollTimer()
            return
        }
        
        if decision.isDistraction {
            // Distraction app/URL detected
            RuntimeTrace.event("distraction_detected", fields: [
                "bundleID": bundleID,
                "activeSession": String(activeSession != nil),
                "countdownSeconds": String(distractionCountdownThreshold)
            ])
            print("🚨 [Distraction Detected] bundleID=\(bundleID) domain=\(url?.host ?? "nil") titleLen=\(title.count)")
            if activeSession != nil {
                // Distraction app detected + active session -> delegate call to show countdown pill
                if distractionStartDate == nil {
                    distractionStartDate = now
                    
                    // Log distraction_detected event
                    let event = SessionEvent(
                        type: .distractionDetected,
                        appBundleID: lastWorkAppBundleID ?? "",
                        appName: getAppName(for: lastWorkAppBundleID ?? ""),
                        url: url?.absoluteString,
                        distractionAppBundleID: bundleID,
                        distraction_domain: url?.host
                    )
                    sessionStore.log(event)
                    
                    delegate?.didDetectDistraction(bundleID: bundleID)
                    RuntimeTrace.event("distraction_countdown_started", fields: ["bundleID": bundleID])
                    
                    // Start countdown timer
                    scheduleDistractionTimer(distractionBundleID: bundleID)
                    persistClassificationOutcome(
                        snapshot: actualSnapshot,
                        decision: decision,
                        intentResult: currentIntentResult,
                        graceStarted: true,
                        enforcementOccurred: isDimming
                    )
                }
            } else {
                // Distraction app detected + no session → start doomscroll timer
                refreshDoomscrollTimerIfNeeded(observedAt: now)
                if !requestFocusPromptIfEligible(now: now) {
                    resetFocusTracking()
                }
            }
        } else if decision.isFocus {
            // Whitelisted focus app/URL detected
            RuntimeTrace.event("focus_context_applied", fields: ["bundleID": bundleID, "activeSession": String(activeSession != nil)])
            print("📈 [Focus Context] bundleID=\(bundleID) appName=\(context.localizedName) domain=\(url?.host ?? "nil") focus=true titleLen=\(title.count)")
            
            if activeSession != nil {
                if shouldImmediatelyResumeSession(for: actualSnapshot, decision: decision) {
                    // Returning to a confirmed focus app ends the grace period
                    // immediately. Do not leave a stale timer armed while the
                    // user is back in the app they are trying to work in.
                    let wasDimming = isDimming
                    lastWorkAppBundleID = bundleID
                    resumeSessionIfNeeded()
                    cancelDistractionTimer()
                    distractionStartDate = nil
                    if !wasDimming {
                        notifyReturnToWorkOncePerContext()
                    }
                }
            } else {
                lastWorkAppBundleID = bundleID
                resetDoomscrollTimer()
                if workSessionStart == nil {
                    workSessionStart = now
                    hasPromptedForCurrentFocusRun = false
                }
                scheduleFocusPromptTimer()
            }
        } else {
            // Neutral app/URL detected
            RuntimeTrace.event("neutral_context_applied", fields: ["bundleID": bundleID, "activeSession": String(activeSession != nil)])
            if activeSession != nil {
                // Keep an active grace period running until a related or
                // explicitly allowed context clears it. Neutral contexts may
                // be transitory while the intent classifier is still settling.
            } else {
                // Neutral context: cancel any doomscroll tracking
                resetDoomscrollTimer()
                // Check if the user accumulated enough focus time on the previous focus app before switching away
                if !requestFocusPromptIfEligible(now: now) {
                    resetFocusTracking()
                }
            }
        }
    }

    private func runClassificationPipeline(snapshot: ContextSnapshot, generation: Int) {
        guard generation == contextGeneration,
              self.currentIdentity == snapshot.identity else { return }

        if preferencesManager.enableLocalTextClassification {
            RuntimeTrace.event("neutral_local_text_selected", fields: ["bundleID": snapshot.bundleIdentifier, "generation": String(generation)])
            triggerAsyncLocalTextClassification(snapshot: snapshot, generation: generation)
        } else {
            triggerCloudOrVisualFallback(
                bundleID: snapshot.bundleIdentifier,
                url: snapshot.url,
                title: snapshot.title,
                generation: generation
            )
        }
    }

    private func triggerAsyncIntentClassification(
        snapshot: ContextSnapshot,
        generation: Int,
        baseDecision: ClassificationDecision
    ) {
        guard let focusIntent = activeFocusIntent, focusIntent.hasIntentSignal else {
            return
        }
        guard activeBreakCommitment == nil, !isDeclaredActivityBypassActive else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var isBackgroundStale = false
            DispatchQueue.main.sync {
                isBackgroundStale = (generation != self.contextGeneration) || (self.currentIdentity != snapshot.identity)
            }
            if isBackgroundStale {
                return
            }

            let visibleText: String?
            if FocusEngine.isSensitiveContext(bundleID: snapshot.bundleIdentifier, url: snapshot.url, title: snapshot.title) {
                visibleText = nil
            } else {
                visibleText = self.normalizedVisibleText(self.ocrProvider.extractText())
            }

            let input = focusIntent.makeInput(
                snapshot: snapshot,
                activeProfileName: self.profileManager.activeProfile.name,
                screenText: visibleText
            )
            let result = self.intentClassifier.classify(input: input)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.contextGeneration,
                      self.currentIdentity == snapshot.identity else {
                    RuntimeTrace.event("intent_result_discarded_stale", fields: [
                        "bundleID": snapshot.bundleIdentifier,
                        "generation": String(generation)
                    ])
                    return
                }

                self.applyIntentClassificationResult(
                    result,
                    snapshot: snapshot,
                    generation: generation,
                    baseDecision: baseDecision
                )
            }
        }
    }

    private func applyIntentClassificationResult(
        _ result: IntentClassificationResult,
        snapshot: ContextSnapshot,
        generation: Int,
        baseDecision: ClassificationDecision
    ) {
        guard self.currentIdentity == snapshot.identity else { return }

        currentIntentResult = result

        let mappedReason = reason(for: result.relation)
        let mappedDecision = ClassificationDecision(
            label: result.mappedLabel,
            confidence: result.confidence,
            source: result.source,
            reason: mappedReason,
            evidence: [
                ClassificationEvidence(
                    label: result.mappedLabel,
                    source: result.source,
                    confidence: result.confidence,
                    reason: mappedReason
                )
            ]
        )

        currentClassification = mappedDecision
        recordClassificationDecision(mappedDecision)
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)

        switch result.relation {
        case .related:
            lastWorkAppBundleID = snapshot.bundleIdentifier
            cancelIntentGraceIfNeeded()
        case .entertainment, .unrelated:
            if result.isHighConfidence {
                beginIntentGraceIfNeeded(
                    snapshot: snapshot,
                    result: result,
                    generation: generation,
                    baseDecision: baseDecision
                )
            } else {
                cancelIntentGraceIfNeeded()
            }
        case .uncertain:
            cancelIntentGraceIfNeeded()
        }

        persistClassificationOutcome(
            snapshot: snapshot,
            decision: mappedDecision,
            intentResult: result,
            graceStarted: result.isHighConfidence && (result.relation == .entertainment || result.relation == .unrelated),
            enforcementOccurred: isDimming
        )

        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    private func beginIntentGraceIfNeeded(
        snapshot: ContextSnapshot,
        result: IntentClassificationResult,
        generation: Int,
        baseDecision: ClassificationDecision
    ) {
        guard activeSession != nil,
              activeBreakCommitment == nil,
              !isDeclaredActivityBypassActive else {
            return
        }

        if distractionStartDate == nil {
            distractionStartDate = snapshot.observedAt

            let event = SessionEvent(
                type: .distractionDetected,
                appBundleID: lastWorkAppBundleID ?? "",
                appName: getAppName(for: lastWorkAppBundleID ?? ""),
                url: snapshot.url?.absoluteString,
                distractionAppBundleID: snapshot.bundleIdentifier,
                distraction_domain: snapshot.url?.host
            )
            sessionStore.log(event)

            delegate?.didDetectDistraction(bundleID: snapshot.bundleIdentifier)
            RuntimeTrace.event("intent_grace_started", fields: [
                "bundleID": snapshot.bundleIdentifier,
                "generation": String(generation),
                "relation": result.relation.rawValue,
                "confidence": String(result.confidence)
            ])

            scheduleDistractionTimer(
                distractionBundleID: snapshot.bundleIdentifier,
                observedAt: snapshot.observedAt
            )
        } else if !isDimming {
            RuntimeTrace.event("intent_grace_continued", fields: [
                "bundleID": snapshot.bundleIdentifier,
                "generation": String(generation),
                "relation": result.relation.rawValue
            ])
        }

    }

    private func cancelIntentGraceIfNeeded() {
        guard distractionStartDate != nil else { return }
        cancelDistractionTimer()
        distractionStartDate = nil
        if isDimming {
            resumeSessionIfNeeded()
        } else {
            notifyReturnToWorkOncePerContext()
        }
    }

    private func reason(for relation: IntentRelation) -> ClassificationReason {
        switch relation {
        case .related:
            return .intentRelated
        case .entertainment:
            return .intentEntertainment
        case .unrelated:
            return .intentUnrelated
        case .uncertain:
            return .intentUncertain
        }
    }

    private func persistClassificationOutcome(
        snapshot: ContextSnapshot,
        decision: ClassificationDecision,
        intentResult: IntentClassificationResult?,
        graceStarted: Bool,
        enforcementOccurred: Bool
    ) {
        guard classificationOutcomeStore.isEnabled else { return }

        let intentSummary = activeFocusIntent?.safeTrackingSummary
        let relation: IntentRelation
        if let intentResult {
            relation = intentResult.relation
        } else if decision.isFocus {
            relation = .related
        } else if decision.isDistraction {
            relation = .unrelated
        } else {
            relation = .uncertain
        }

        let outcome = ClassificationOutcome.make(
            bundleID: snapshot.bundleIdentifier,
            appName: snapshot.localizedName,
            contextGeneration: contextGeneration,
            sessionID: activeSessionIdentity,
            contextIdentity: snapshot.identity,
            intentSummary: intentSummary,
            relation: relation,
            mappedLabel: decision.label,
            confidence: decision.confidence,
            source: decision.source,
            modelVersion: intentResult?.modelVersion ?? decision.source.rawValue,
            latency: intentResult?.latency ?? 0,
            graceStarted: graceStarted,
            enforcementOccurred: enforcementOccurred,
            observedAt: snapshot.observedAt
        )

        classificationOutcomeStore.record(outcome, completion: nil)
    }

    private func triggerAsyncLocalTextClassification(snapshot: ContextSnapshot, generation: Int) {
        let isStale = (generation != self.contextGeneration) && (self.currentIdentity != snapshot.identity)
        if isStale {
            inProgressClassifications.remove(snapshot.identity)
            return
        }

        guard preferencesManager.enableLocalTextClassification else {
            self.triggerCloudOrVisualFallback(
                bundleID: snapshot.bundleIdentifier,
                url: snapshot.url,
                title: snapshot.title,
                generation: generation
            )
            return
        }

        let identity = snapshot.identity
        let sanitizedSnapshot = ContextSnapshot(
            bundleIdentifier: identity.bundleID,
            localizedName: snapshot.localizedName,
            url: identity.sanitizedURL.flatMap(URL.init(string:)),
            title: identity.normalizedTitle,
            source: snapshot.source,
            observedAt: snapshot.observedAt
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var isBackgroundStale = false
            DispatchQueue.main.sync {
                isBackgroundStale = (generation != self.contextGeneration) || (self.currentIdentity != snapshot.identity)
            }
            if isBackgroundStale {
                DispatchQueue.main.async { [weak self] in
                    self?.classificationCache.removeValue(forKey: snapshot.identity)
                    self?.inProgressClassifications.remove(snapshot.identity)
                }
                return
            }

            let visibleText: String?
            if FocusEngine.isSensitiveContext(bundleID: snapshot.bundleIdentifier, url: snapshot.url, title: snapshot.title) {
                RuntimeTrace.event("local_text_classification_skipped_sensitive", fields: [
                    "bundleID": snapshot.bundleIdentifier
                ])
                visibleText = nil
            } else {
                visibleText = self.normalizedVisibleText(self.ocrProvider.extractText())
            }

            let result = self.localTextClassifier.classify(
                snapshot: sanitizedSnapshot,
                screenText: visibleText
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                let isActiveContext = (self.currentIdentity == identity)

                guard generation == self.contextGeneration else {
                    self.classificationCache.removeValue(forKey: identity)
                    self.inProgressClassifications.remove(identity)
                    return
                }

                RuntimeTrace.event("local_text_classification_finished", fields: [
                    "bundleID": snapshot.bundleIdentifier,
                    "label": result.label.rawValue,
                    "confidence": String(result.confidence),
                    "latencyMs": String(Int(result.latency * 1000))
                ])

                // ONLY promote if productive (focus).
                if result.label == .productive,
                   result.confidence >= ClassificationPolicy.highConfidenceThreshold {
                    let currentEvidence = self.distractionEvaluator.evidence(bundleID: snapshot.bundleIdentifier, url: snapshot.url, title: snapshot.title)
                    let promotionEvidence = ClassificationEvidence(
                        label: .productive,
                        source: .localModel,
                        confidence: result.confidence,
                        reason: .modelEvidence
                    )
                    let promotedDecision = self.classificationResolver.resolve(currentEvidence + [promotionEvidence])

                    if promotedDecision.isFocus {
                        self.classificationCache[identity] = promotedDecision
                        self.inProgressClassifications.remove(identity)

                        let isCurrentlyActive = (generation == self.contextGeneration) || isActiveContext
                        if isCurrentlyActive {
                            self.applyPromotedFocus(bundleID: snapshot.bundleIdentifier)
                            self.currentClassification = promotedDecision
                            self.recordClassificationDecision(promotedDecision)
                            NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)
                            self.persistClassificationOutcome(
                                snapshot: snapshot,
                                decision: promotedDecision,
                                intentResult: nil,
                                graceStarted: false,
                                enforcementOccurred: false
                            )
                        }
                        return
                    }
                }

                self.triggerCloudOrVisualFallback(
                    bundleID: snapshot.bundleIdentifier,
                    url: snapshot.url,
                    title: snapshot.title,
                    generation: generation
                )
            }
        }
    }

    private func normalizedVisibleText(_ text: String) -> String? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }
    
    private func resumeSessionIfNeeded() {
        if isDimming {
            isDimming = false
            
            if let pausedAt = pausedDate {
                let pausedDiff = Date().timeIntervalSince(pausedAt)
                if let session = activeSession {
                    activeSession = ActiveSession(
                        startDate: session.startDate.addingTimeInterval(pausedDiff),
                        anchoredDuration: session.anchoredDuration,
                        appName: session.appName,
                        category: session.category,
                        goal: session.goal
                    )
                }
                pausedDate = nil
            }
            
            if let session = activeSession {
                let elapsed = Date().timeIntervalSince(session.startDate)
                let remaining = max(0, session.anchoredDuration - elapsed)
                scheduleSessionTimer(duration: remaining)
            }
            
            notifyReturnToWorkOncePerContext()
        }
    }

    /// Requests a memory-only break from the active session.
    @discardableResult
    func requestBreak(intention: String, now: Date = Date(), bypassMinimum: Bool = false) -> BreakRequestDecision {
        guard activeSession != nil else {
            return .refusedUnderMinimum
        }

        let decision = CommitmentPolicy.breakRequest(
            netFocusedDuration: currentSessionFocusedTime(at: now),
            intention: intention,
            now: now,
            sessionID: sessionIdentity,
            contextGeneration: UInt64(contextGeneration),
            bypassMinimum: bypassMinimum
        )

        switch decision {
        case .refusedUnderMinimum:
            delegate?.didRefuseBreak()
        case .accepted(let commitment):
            activeBreakCommitment = commitment
            breakState = .breakActive
            breakStartedAt = now
            hasSeenNonFocusContextSinceBreakStarted = false
            cancelBreakReturnGraceTimer()
            cancelSessionTimer(reason: .breakStarted)
            cancelDistractionTimer()
            distractionStartDate = nil
            isDimming = false
            delegate?.didReturnToWork()
            scheduleBreakTimer(duration: CommitmentPolicy.breakDuration)
            NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
        }

        return decision
    }

    /// Resumes the active session after a break review or explicit cancellation.
    func resumeAfterBreakReview(now: Date = Date()) {
        guard activeBreakCommitment != nil else { return }
        cancelBreakTimer()
        cancelBreakReturnGraceTimer()
        clearBreakState(at: now)
        guard let session = activeSession else { return }
        let remaining = max(0, session.anchoredDuration - currentSessionFocusedTime(at: now))
        scheduleSessionTimer(duration: remaining)
        delegate?.didReturnToWork()
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    func resumeSessionFromUI() {
        let wasDimming = isDimming
        resumeSessionIfNeeded()
        cancelDistractionTimer()
        distractionStartDate = nil
        if !wasDimming {
            delegate?.didReturnToWork()
        }
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    /// Forces the current session into the dimmed state immediately.
    func forceImmediateDim() {
        guard activeSession != nil, !isDimming else { return }

        let bundleID = currentApp ?? lastWorkAppBundleID ?? ""
        let appName = getAppName(for: bundleID)
        isDimming = true
        cancelSessionTimer(reason: .manualAction)
        cancelDistractionTimer()
        distractionStartDate = Date()
        distractionBundleID = bundleID.isEmpty ? nil : bundleID
        pausedDate = Date()

        RuntimeTrace.event("manual_force_dim_triggered", fields: [
            "bundleID": bundleID,
            "appName": appName
        ])

        sessionStore.log(
            SessionEvent(
                type: .escalationTriggered,
                appBundleID: lastWorkAppBundleID ?? bundleID,
                appName: getAppName(for: lastWorkAppBundleID ?? bundleID),
                distractionAppBundleID: bundleID.isEmpty ? nil : bundleID,
                action: .escalated
            )
        )

        delegate?.didRequestImmediateDim()
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    func startDeclaredActivityBypass(activity: String) {
        guard activeSession != nil else { return }
        declaredActivity = activity
        isDeclaredActivityBypassActive = true

        let wasDimming = isDimming
        resumeSessionIfNeeded()
        cancelDistractionTimer()
        distractionStartDate = nil
        if !wasDimming {
            delegate?.didReturnToWork()
        }
        
        scheduleDeclaredActivityCheckTimer()
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }
    
    func stopDeclaredActivityBypass() {
        declaredActivity = nil
        isDeclaredActivityBypassActive = false
        cancelDeclaredActivityCheckTimer()
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }
    
    private func scheduleDeclaredActivityCheckTimer() {
        cancelDeclaredActivityCheckTimer()
        declaredActivityCheckTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: false) { [weak self] _ in
            self?.checkDeclaredActivity()
        }
    }
    
    private func cancelDeclaredActivityCheckTimer() {
        declaredActivityCheckTimer?.invalidate()
        declaredActivityCheckTimer = nil
    }
    
    private func checkDeclaredActivity() {
        guard lifecyclePauseStartedAt == nil,
              isDeclaredActivityBypassActive else { return }

        let decision = classifyContext(
            bundleID: currentApp ?? "",
            url: currentURL,
            title: currentTitle
        )
        
        let isFocused = decision.isFocus
        let matches = matchesDeclaredActivity()
        
        if isFocused || matches {
            if isDimming {
                isDimming = false
                delegate?.didReturnToWork()
                NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
            }
        } else {
            if !isDimming {
                isDimming = true
                if let bundleID = currentApp {
                    let event = SessionEvent(
                        type: .escalationTriggered,
                        appBundleID: lastWorkAppBundleID ?? "",
                        appName: getAppName(for: lastWorkAppBundleID ?? ""),
                        distractionAppBundleID: bundleID,
                        action: .escalated
                    )
                    sessionStore.log(event)
                    delegate?.didRequestImmediateDim()
                }
                NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
            }
        }
        
        scheduleDeclaredActivityCheckTimer()
    }
    
    private func matchesDeclaredActivity() -> Bool {
        guard let declared = declaredActivity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !declared.isEmpty else {
            return false
        }
        
        if let currentApp = currentApp {
            let appName = getAppName(for: currentApp).lowercased()
            if appName.contains(declared) || currentApp.lowercased().contains(declared) {
                return true
            }
        }
        
        let titleLower = currentTitle.lowercased()
        if titleLower.contains(declared) {
            return true
        }
        
        if let currentURL = currentURL?.absoluteString.lowercased() {
            if currentURL.contains(declared) {
                return true
            }
        }
        
        return false
    }

    internal func breakTimerExpired() {
        breakTimerExpired(
            generation: activeBreakTimerGeneration,
            sessionID: activeBreakCommitment?.sessionID,
            now: Date()
        )
    }

    private var sessionIdentity: UUID {
        // ActiveSession predates an explicit session UUID. Keep a stable
        // in-memory identity for the lifetime of this active session.
        if let identity = activeSessionIdentity {
            return identity
        }
        let identity = UUID()
        activeSessionIdentity = identity
        return identity
    }

    private var activeSessionIdentity: UUID?

    private func clearBreakState(at date: Date) {
        stopDeclaredActivityBypass()
        cancelBreakTimer()
        cancelBreakReturnGraceTimer()
        if let breakStartedAt {
            excludedBreakDuration += max(0, date.timeIntervalSince(breakStartedAt))
        }
        breakStartedAt = nil
        activeBreakCommitment = nil
        breakState = nil
        hasSeenNonFocusContextSinceBreakStarted = false
    }

    private func cancelBreakTimer() {
        breakTimer?.cancel()
        breakTimer = nil
        activeBreakTimerGeneration = nil
    }

    private func scheduleBreakTimer(duration: TimeInterval) {
        cancelBreakTimer()
        guard let commitment = activeBreakCommitment else { return }

        breakTimerGeneration += 1
        let generation = breakTimerGeneration
        activeBreakTimerGeneration = generation
        let scheduledExpiration = breakStartedAt?.addingTimeInterval(duration) ?? Date().addingTimeInterval(duration)

        if duration <= 0 {
            breakTimerExpired(
                generation: generation,
                sessionID: commitment.sessionID,
                now: scheduledExpiration
            )
            return
        }

        let sessionID = commitment.sessionID
        breakTimer = breakTimerScheduler.schedule(after: duration) { [weak self] in
            self?.breakTimerExpired(
                generation: generation,
                sessionID: sessionID,
                now: scheduledExpiration
            )
        }
    }

    private func cancelBreakReturnGraceTimer() {
        breakReturnGraceTimer?.cancel()
        breakReturnGraceTimer = nil
        activeBreakReturnGraceGeneration = nil
        breakReturnGraceSessionID = nil
        breakReturnGraceContextGeneration = nil
        breakReturnGraceContextIdentity = nil
        breakReturnGraceStartedAt = nil
    }

    private func updateBreakReturnGrace(
        for decision: ClassificationDecision,
        snapshot: ContextSnapshot,
        observedAt: Date
    ) {
        guard activeBreakCommitment != nil else { return }

        if decision.isFocus {
            guard hasSeenNonFocusContextSinceBreakStarted else { return }
            guard breakReturnGraceStartedAt == nil
                || breakReturnGraceContextIdentity != snapshot.identity
                || breakReturnGraceContextGeneration != contextGeneration else {
                return
            }

            scheduleBreakReturnGraceTimer(snapshot: snapshot, observedAt: observedAt)
        } else {
            hasSeenNonFocusContextSinceBreakStarted = true
            cancelBreakReturnGraceTimer()
        }
    }

    internal func breakReturnGraceTimerExpired(now: Date = Date()) {
        breakReturnGraceTimerExpired(
            sessionID: breakReturnGraceSessionID,
            contextIdentity: breakReturnGraceContextIdentity,
            contextGeneration: breakReturnGraceContextGeneration ?? contextGeneration,
            generation: activeBreakReturnGraceGeneration ?? breakReturnGraceGeneration,
            now: now
        )
    }

    private func scheduleBreakReturnGraceTimer(snapshot: ContextSnapshot, observedAt: Date) {
        cancelBreakReturnGraceTimer()
        guard let commitment = activeBreakCommitment else { return }

        breakReturnGraceGeneration += 1
        let generation = breakReturnGraceGeneration
        activeBreakReturnGraceGeneration = generation
        breakReturnGraceSessionID = commitment.sessionID
        breakReturnGraceContextGeneration = contextGeneration
        breakReturnGraceContextIdentity = snapshot.identity
        breakReturnGraceStartedAt = observedAt

        let remaining = max(0, breakReturnGraceThreshold - Date().timeIntervalSince(observedAt))
        guard remaining > 0 else {
            breakReturnGraceTimerExpired(
                sessionID: commitment.sessionID,
                contextIdentity: snapshot.identity,
                contextGeneration: contextGeneration,
                generation: generation,
                now: observedAt
            )
            return
        }

        let sessionID = commitment.sessionID
        let contextIdentity = snapshot.identity
        let capturedContextGeneration = contextGeneration
        breakReturnGraceTimer = breakReturnGraceTimerScheduler.schedule(after: remaining) { [weak self] in
            self?.breakReturnGraceTimerExpired(
                sessionID: sessionID,
                contextIdentity: contextIdentity,
                contextGeneration: capturedContextGeneration,
                generation: generation
            )
        }

        RuntimeTrace.event("break_return_grace_started", fields: [
            "bundleID": snapshot.bundleIdentifier,
            "seconds": String(breakReturnGraceThreshold),
            "generation": String(generation)
        ])
    }

    private func breakReturnGraceTimerExpired(
        sessionID: UUID?,
        contextIdentity: ContextIdentity?,
        contextGeneration: Int,
        generation: Int,
        now: Date = Date()
    ) {
        guard lifecyclePauseStartedAt == nil,
              activeSession != nil,
              activeBreakCommitment?.sessionID == sessionID,
              hasSeenNonFocusContextSinceBreakStarted,
              let startedAt = breakReturnGraceStartedAt,
              breakReturnGraceSessionID == sessionID,
              breakReturnGraceContextIdentity == contextIdentity,
              breakReturnGraceContextGeneration == contextGeneration,
              activeBreakReturnGraceGeneration == generation,
              now.timeIntervalSince(startedAt) >= breakReturnGraceThreshold,
              currentClassification.isFocus else {
            return
        }

        cancelBreakReturnGraceTimer()
        resumeAfterBreakReview(now: now)
    }

    private func breakTimerExpired(
        generation scheduledGeneration: Int?,
        sessionID: UUID?,
        now: Date
    ) {
        guard lifecyclePauseStartedAt == nil,
              breakState == .breakActive,
              activeSession != nil,
              let commitment = activeBreakCommitment,
              activeBreakTimerGeneration == scheduledGeneration,
              commitment.sessionID == sessionID,
              let startedAt = breakStartedAt,
              now.timeIntervalSince(startedAt) >= CommitmentPolicy.breakDuration else {
            return
        }

        cancelBreakTimer()
        breakState = .breakReview

        let input: BreakReviewInput?
        if let currentApp {
            let snapshotIdentity = ContextSnapshot(
                bundleIdentifier: currentApp,
                localizedName: getAppName(for: currentApp),
                url: currentURL,
                title: currentTitle,
                source: .application
            ).identity
            input = BreakReviewInput(
                sessionID: commitment.sessionID,
                identity: snapshotIdentity,
                contextGeneration: UInt64(contextGeneration),
                decision: currentClassification
            )
        } else {
            input = nil
        }

        let result = breakReviewChecker.evaluate(input: input, expectedIdentity: commitment.reviewIdentity)
        delegate?.didRequestBreakReview(intention: commitment.intention, result: result)

        if result.mayStartExistingCountdown, let bundleID = currentApp {
            distractionStartDate = Date()
            delegate?.didDetectDistraction(bundleID: bundleID)
            scheduleDistractionTimer(distractionBundleID: bundleID)
        }
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }
    
    /// Applies a user correction as an explicit profile rule.
    func applyCorrection(_ correction: ClassificationCorrection) {
        guard let bundleID = currentApp else { return }
        let originalDecision = currentClassification
        guard profileManager.applyCorrection(correction, bundleID: bundleID, url: currentURL) else { return }

        // ProfileManager broadcasts the profile change synchronously. Re-read
        // the current context so callers observe the correction immediately.
        currentClassification = classifyContext(bundleID: bundleID, url: currentURL, title: currentTitle)
        recordClassificationDecision(currentClassification)
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)

        let correctedLabel: ClassificationLabel = correction == .allowApp
            || correction == .allowDomain
            || correction == .markSessionProductive
            ? .productive
            : .distracting
        ClassificationFeedbackStore.shared.record(
            ClassificationFeedback(
                bundleID: bundleID,
                domain: currentURL?.host,
                originalLabel: originalDecision.label,
                correctedLabel: correctedLabel,
                correction: correction,
                source: originalDecision.source
            )
        )

        let sanitizedIdentity = ContextIdentity(
            bundleID: bundleID,
            sanitizedURL: ContextSanitizer.sanitizePersistedURL(currentURL),
            normalizedTitle: ContextSanitizer.sanitizeTitle(currentTitle)
        )
        classificationOutcomeStore.recordCorrection(
            identity: ClassificationOutcome.Identity(
                contextGeneration: contextGeneration,
                sessionID: activeSessionIdentity,
                contextIdentity: sanitizedIdentity
            ),
            correction: correction,
            correctedAt: Date(),
            completion: nil
        )
    }

    /// Locks in an active focused session.
    func anchorSession(duration: TimeInterval, category: String? = nil, goal: String? = nil) {
        let now = Date()
        let start = workSessionStart ?? now
        let resolvedProfileName = Self.cleanedSuggestedLabel(category) ?? suggestedSessionProfile().name
        let explicitGoal = Self.cleanedSuggestedLabel(goal)
        let resolvedGoal = explicitGoal ?? suggestedSessionGoal()
        let focusedAppName = resolvedSessionAppName(fallbackCategory: resolvedProfileName)
        let fromState = state

        activeSessionIdentity = UUID()
        excludedBreakDuration = 0
        let baselineSnapshot: ContextSnapshot
        if let currentContext {
            baselineSnapshot = ContextSnapshot(
                bundleIdentifier: currentContext.bundleIdentifier,
                localizedName: currentContext.localizedName,
                url: currentURL,
                title: currentContext.title,
                source: BrowserStrategyFactory.isSupportedBrowser(currentContext.bundleIdentifier)
                    ? (currentContext.bundleIdentifier == "com.apple.Safari" ? .safari : .chromium)
                    : .application,
                observedAt: now
            )
        } else {
            baselineSnapshot = ContextSnapshot(
                bundleIdentifier: currentApp ?? "",
                localizedName: focusedAppName,
                url: currentURL,
                title: currentTitle,
                source: BrowserStrategyFactory.isSupportedBrowser(currentApp ?? "")
                    ? (currentApp == "com.apple.Safari" ? .safari : .chromium)
                    : .application,
                observedAt: now
            )
        }
        activeFocusIntent = FocusIntent.make(
            goal: explicitGoal,
            baselineContext: baselineSnapshot,
            activeProfileName: profileManager.activeProfile.name,
            activeProfileCategory: resolvedProfileName
        )
        currentIntentResult = nil
        
        let session = ActiveSession(
            startDate: start,
            anchoredDuration: duration,
            appName: focusedAppName,
            category: resolvedProfileName,
            goal: resolvedGoal
        )
        self.activeSession = session
        resetDoomscrollTimer()
        RuntimeTrace.event("session_anchored", fields: [
            "duration": String(duration),
            "appBundleID": lastWorkAppBundleID ?? "",
            "hasGoal": String(explicitGoal != nil)
        ])
        cancelFocusPromptTimer()
        
        // Reset idle tracking
        self.totalIdleTime = 0.0
        self.startIdleTimer()
        
        // Log sessionStart event
        let focusDuration = now.timeIntervalSince(start)
        let event = SessionEvent(
            type: .sessionStart,
            appBundleID: lastWorkAppBundleID ?? "",
            appName: focusedAppName,
            url: nil,
            focusDurationSeconds: Int(focusDuration),
            sessionDurationSeconds: Int(duration),
            distractionAppBundleID: nil,
            distraction_domain: nil,
            action: .anchored,
            category: resolvedProfileName,
            sessionGoal: resolvedGoal
        )
        print("⚓️ [Session Started] AppName: \(focusedAppName) | Duration: \(duration)s | Goal: \(resolvedGoal ?? "None")")
        sessionStore.log(event)
        diagnosticsRecorder.recordEngineStateTransition(from: fromState, to: .anchored, reason: .sessionStarted)
        diagnosticsRecorder.recordSessionLifecycle(action: .started, duration: duration, bundleID: lastWorkAppBundleID ?? currentApp)
        
        // Schedule session end timer (accounting for retroactive time)
        let remaining = max(0, duration - now.timeIntervalSince(start))
        scheduleSessionTimer(duration: remaining)
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }
    
    /// Resets the work session start time, e.g. when taking a break.
    func dismissTrigger() {
        resetFocusTracking()
    }
    
    /// Terminates the active session and logs a sessionEnd event.
    func endSession() {
        endSession(action: .timeout, completionOutcome: .timeout)
    }
    
    /// Terminates the active session with a specific action.
    func endSession(
        action: SessionAction,
        completionOutcome: SessionCompletionOutcome? = nil,
        summary: String? = nil
    ) {
        guard let session = activeSession else { return }
        let fromState = state
        
        cancelIdleTimer()

        let now = Date()
        let duration = currentSessionFocusedTime(at: now)
        
        // Log sessionEnd event
        let event = SessionEvent(
            type: .sessionEnd,
            appBundleID: lastWorkAppBundleID ?? "",
            appName: session.appName,
            sessionDurationSeconds: Int(duration),
            action: action,
            sessionSummary: summary,
            completionOutcome: completionOutcome ?? outcome(for: action)
        )
        print("🛑 [Session Ended] AppName: \(session.appName) | Duration: \(duration)s | Action: \(action.rawValue)")
        sessionStore.log(event)
        diagnosticsRecorder.recordSessionLifecycle(action: .ended, duration: duration, bundleID: lastWorkAppBundleID ?? currentApp)
        
        // Clean up state
        activeSession = nil
        activeSessionIdentity = nil
        activeFocusIntent = nil
        currentIntentResult = nil
        clearBreakState(at: now)
        stopDeclaredActivityBypass()
        resetDoomscrollTimer()
        resetFocusTracking()
        isDimming = false
        distractionStartDate = nil
        pausedDate = nil
        
        cancelSessionTimer(reason: .sessionEnded)
        cancelDistractionTimer()
        
        // Notify delegate
        delegate?.sessionDidEnd()
        diagnosticsRecorder.recordEngineStateTransition(from: fromState, to: .idle, reason: .sessionEnded)
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
        
        // The gate is an onboarding milestone, not a modal requirement after every session.
        // Keep it deferred until the user has completed ten sessions so an unavailable
        // Accessibility permission can never interrupt ordinary focus work.
        let completedSessionCount = sessionStore.allEvents().filter { $0.type == .sessionEnd }.count
        if completedSessionCount >= 10, !AXIsProcessTrusted() {
            delegate?.didRequestPermissionGate()
        }
    }
    
    /// Returns the net focused time for the active session (subtracting idle time).
    func currentSessionFocusedTime() -> TimeInterval {
        currentSessionFocusedTime(at: Date())
    }

    internal func currentSessionFocusedTime(at date: Date) -> TimeInterval {
        guard let session = activeSession else { return 0.0 }
        let accountingDate = lifecyclePauseStartedAt.map { min(date, $0) } ?? date
        let rawDuration = accountingDate.timeIntervalSince(session.startDate)
        let activeBreakDuration = breakStartedAt.map { max(0, accountingDate.timeIntervalSince($0)) } ?? 0
        return max(0, rawDuration - totalIdleTime - excludedBreakDuration - activeBreakDuration)
    }

    private func outcome(for action: SessionAction) -> SessionCompletionOutcome {
        switch action {
        case .timeout: return .timeout
        case .escalated: return .escalated
        case .dismissed: return .dismissed
        case .anchored, .returned: return .done
        }
    }
    
    private func startIdleTimer() {
        cancelIdleTimer()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkIdleTime()
        }
    }
    
    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }
    
    private func checkIdleTime() {
        guard lifecyclePauseStartedAt == nil else { return }
        let anyInputEventType = CGEventType(rawValue: ~0)!
        let idleTime = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
        
        if idleTime >= 60.0 {
            totalIdleTime += 1.0
            
            // Postpone the session end timer
            if let session = activeSession {
                let now = Date()
                let elapsed = now.timeIntervalSince(session.startDate)
                let netElapsed = max(0, elapsed - totalIdleTime)
                let remaining = max(0, session.anchoredDuration - netElapsed)
                scheduleSessionTimer(duration: remaining)
            }
        }
    }
    
    // MARK: - Timer Helpers

    private func scheduleFocusPromptTimer() {
        cancelFocusPromptTimer()
        guard focusPromptsEnabled,
              isFocusScheduleActive,
              lifecyclePauseStartedAt == nil,
              activeSession == nil,
              !hasPromptedForCurrentFocusRun,
              let start = workSessionStart else {
            return
        }

        let remaining = max(0, focusThreshold - Date().timeIntervalSince(start))
        focusPromptTimerGeneration += 1
        let generation = focusPromptTimerGeneration
        activeFocusPromptTimerGeneration = generation
        focusPromptTimer = focusPromptTimerScheduler.schedule(after: remaining) { [weak self] in
            self?.focusPromptTimerExpired(generation: generation, now: Date())
        }
    }

    private func cancelFocusPromptTimer() {
        focusPromptTimer?.cancel()
        focusPromptTimer = nil
        activeFocusPromptTimerGeneration = nil
    }

    private func resetFocusTracking() {
        let fromState = state
        cancelFocusPromptTimer()
        workSessionStart = nil
        hasPromptedForCurrentFocusRun = false
        activeFocusIntent = nil
        currentIntentResult = nil
        if fromState != .idle {
            diagnosticsRecorder.recordEngineStateTransition(from: fromState, to: .idle, reason: .trackingReset)
        }
    }

    /// Starts a session automatically once the configured focus threshold is met.
    @discardableResult
    private func requestFocusPromptIfEligible(now: Date) -> Bool {
        guard lifecyclePauseStartedAt == nil,
              isFocusScheduleActive,
              focusPromptsEnabled,
              activeSession == nil,
              !hasPromptedForCurrentFocusRun,
              let start = workSessionStart else {
            return false
        }

        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= focusThreshold else { return false }

        hasPromptedForCurrentFocusRun = true
        RuntimeTrace.event("automatic_focus_session_started", fields: [
            "elapsed": String(now.timeIntervalSince(start)),
            "threshold": String(focusThreshold),
            "appBundleID": lastWorkAppBundleID ?? currentApp ?? "",
            "duration": String(preferencesManager.automaticSessionDuration)
        ])
        cancelFocusPromptTimer()
        startAutomaticFocusSession()
        return true
    }

    internal func focusPromptTimerExpired() {
        focusPromptTimerExpired(generation: activeFocusPromptTimerGeneration, now: Date())
    }

    private func focusPromptTimerExpired(generation scheduledGeneration: Int?, now: Date) {
        guard let scheduledGeneration,
              activeFocusPromptTimerGeneration == scheduledGeneration else {
            return
        }

        cancelFocusPromptTimer()
        guard lifecyclePauseStartedAt == nil,
              isFocusScheduleActive,
              focusPromptsEnabled,
              activeSession == nil,
              !hasPromptedForCurrentFocusRun,
              let bundleID = currentApp,
              classifyContext(bundleID: bundleID, url: currentURL, title: currentTitle).isFocus else {
            return
        }

        if !requestFocusPromptIfEligible(now: now) {
            scheduleFocusPromptTimer()
        }
    }

    private func startAutomaticFocusSession() {
        guard isFocusScheduleActive else { return }
        let duration = preferencesManager.automaticSessionDuration
        let category = profileManager.activeProfile.name
        anchorSession(duration: duration, category: category, goal: "Auto-chartered Voyage")
    }
    
    private func scheduleSessionTimer(duration: TimeInterval) {
        cancelSessionTimer(reason: .rescheduled)
        guard lifecyclePauseStartedAt == nil else { return }
        guard activeSession != nil else { return }

        sessionTimerGeneration += 1
        let generation = sessionTimerGeneration
        activeSessionTimerGeneration = generation
        let sessionID = sessionIdentity
        let expiration = Date().addingTimeInterval(duration)
        sessionTimerExpiration = expiration

        sessionTimer = sessionTimerScheduler.schedule(after: duration) { [weak self] in
            self?.sessionTimerExpired(
                generation: generation,
                sessionID: sessionID,
                expiration: expiration,
                now: expiration
            )
        }
        diagnosticsRecorder.recordTimerScheduled(kind: .sessionExpiry, delay: duration, generation: generation)
    }
    
    private func cancelSessionTimer(reason: DiagnosticTimerCancellationReason? = nil) {
        if let reason, sessionTimer != nil {
            diagnosticsRecorder.recordTimerCancelled(
                kind: .sessionExpiry,
                reason: reason,
                generation: activeSessionTimerGeneration
            )
        }
        sessionTimer?.cancel()
        sessionTimer = nil
        activeSessionTimerGeneration = nil
        sessionTimerExpiration = nil
    }
    
    internal func sessionTimerExpired() {
        sessionTimerExpired(
            generation: activeSessionTimerGeneration,
            sessionID: activeSessionIdentity,
            expiration: sessionTimerExpiration,
            now: Date()
        )
    }

    private func sessionTimerExpired(
        generation scheduledGeneration: Int?,
        sessionID: UUID?,
        expiration: Date?,
        now: Date
    ) {
        guard lifecyclePauseStartedAt == nil else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .workspacePaused, generation: scheduledGeneration)
            return
        }
        guard let session = activeSession else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .sessionEnded, generation: scheduledGeneration)
            return
        }
        guard activeSessionIdentity == sessionID else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .sessionMismatch, generation: scheduledGeneration)
            return
        }
        guard activeSessionTimerGeneration == scheduledGeneration else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .generationMismatch, generation: scheduledGeneration)
            return
        }
        guard sessionTimerExpiration == expiration else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .expirationMismatch, generation: scheduledGeneration)
            return
        }
        guard let expiration else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .expirationMismatch, generation: scheduledGeneration)
            return
        }
        guard now >= expiration else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .expiredTooEarly, generation: scheduledGeneration)
            return
        }
        guard currentSessionFocusedTime(at: now) >= session.anchoredDuration else {
            diagnosticsRecorder.recordTimerRejected(kind: .sessionExpiry, reason: .staleContext, generation: scheduledGeneration)
            return
        }

        sessionTimer = nil
        activeSessionTimerGeneration = nil
        sessionTimerExpiration = nil
        endSession(action: .timeout)
    }
    
    private func scheduleDistractionTimer(distractionBundleID: String, observedAt: Date = Date()) {
        cancelDistractionTimer()
        guard lifecyclePauseStartedAt == nil else { return }
        self.distractionBundleID = distractionBundleID
        distractionTimerGeneration += 1
        let generation = distractionTimerGeneration
        activeDistractionTimerGeneration = generation
        let threshold = distractionGraceThreshold(for: distractionBundleID)
        let remaining = max(0, threshold - Date().timeIntervalSince(observedAt))
        guard remaining > 0 else {
            distractionTimerExpired(distractionBundleID: distractionBundleID, generation: generation)
            return
        }
        distractionTimer = distractionTimerScheduler.schedule(after: remaining) { [weak self] in
            self?.distractionTimerExpired(distractionBundleID: distractionBundleID, generation: generation)
        }
    }
    
    private func cancelDistractionTimer() {
        distractionTimer?.cancel()
        distractionTimer = nil
        distractionBundleID = nil
        activeDistractionTimerGeneration = nil
    }
    
    internal func distractionTimerExpired(distractionBundleID: String) {
        distractionTimerExpired(
            distractionBundleID: distractionBundleID,
            generation: activeDistractionTimerGeneration ?? distractionTimerGeneration
        )
    }

    private func distractionTimerExpired(distractionBundleID: String, generation: Int) {
        // Timer invalidation is not enough: a callback that was already queued may
        // still arrive after the user returned to the recorded work app.
        guard lifecyclePauseStartedAt == nil,
              activeSession != nil,
              !isDimming,
              self.distractionBundleID == distractionBundleID,
              activeDistractionTimerGeneration == generation,
              currentApp != lastWorkAppBundleID else { return }
        isDimming = true
        RuntimeTrace.event("distraction_timer_expired", fields: ["bundleID": distractionBundleID])
        pausedDate = Date()
        cancelSessionTimer()
        cancelDistractionTimer()
        
        // Log escalation_triggered event
        let event = SessionEvent(
            type: .escalationTriggered,
            appBundleID: lastWorkAppBundleID ?? "",
            appName: getAppName(for: lastWorkAppBundleID ?? ""),
            distractionAppBundleID: distractionBundleID,
            action: .escalated
        )
        sessionStore.log(event)
    }

    var currentDistractionGraceRemaining: TimeInterval? {
        guard let distractionStartDate,
              let distractionBundleID else { return nil }
        let threshold = distractionGraceThreshold(for: distractionBundleID)
        return max(0, threshold - Date().timeIntervalSince(distractionStartDate))
    }

    private static let musicAppGraceThreshold: TimeInterval = 120.0

    private static let musicAppBundleIdentifiers: Set<String> = [
        "com.apple.Music",
        "com.spotify.client",
        "com.apple.podcasts"
    ]

    private func distractionGraceThreshold(for bundleID: String) -> TimeInterval {
        let normalizedBundleID = bundleID.lowercased()
        let isMusicBundle = Self.musicAppBundleIdentifiers.contains { $0.lowercased() == normalizedBundleID }
            || normalizedBundleID.contains("music")
            || normalizedBundleID.contains("spotify")
            || normalizedBundleID.contains("podcast")
        if isMusicBundle {
            return max(distractionCountdownThreshold, Self.musicAppGraceThreshold)
        }
        return distractionCountdownThreshold
    }
    
    // MARK: - Doomscroll Loop Breaker

    private func currentDoomscrollSnapshot(observedAt: Date = Date()) -> ContextSnapshot? {
        guard let bundleID = currentApp else { return nil }
        return ContextSnapshot(
            bundleIdentifier: bundleID,
            localizedName: currentContext?.localizedName ?? getAppName(for: bundleID),
            url: currentURL,
            title: currentTitle,
            source: BrowserStrategyFactory.isSupportedBrowser(bundleID)
                ? (bundleID == "com.apple.Safari" ? .safari : .chromium)
                : .application,
            observedAt: observedAt
        )
    }

    private func refreshDoomscrollTimerIfNeeded(
        observedAt: Date = Date(),
        threshold: TimeInterval? = nil,
        loopBreakerEnabled: Bool? = nil
    ) {
        guard currentClassification.isDistraction else {
            cancelDoomscrollTimer()
            return
        }
        guard !hasFiredDoomscrollAlert else { return }
        guard loopBreakerEnabled ?? preferencesManager.enableDoomscrollLoopBreaker,
              isFocusScheduleActive,
              lifecyclePauseStartedAt == nil,
              activeSession == nil,
              let snapshot = currentDoomscrollSnapshot(observedAt: observedAt) else {
            cancelDoomscrollTimer()
            return
        }

        scheduleDoomscrollTimer(
            snapshot: snapshot,
            threshold: threshold,
            loopBreakerEnabled: loopBreakerEnabled
        )
    }

    private func scheduleDoomscrollTimer(
        snapshot: ContextSnapshot,
        threshold: TimeInterval? = nil,
        loopBreakerEnabled: Bool? = nil
    ) {
        cancelDoomscrollTimer()
        let threshold = threshold ?? preferencesManager.doomscrollThreshold
        guard loopBreakerEnabled ?? preferencesManager.enableDoomscrollLoopBreaker,
              isFocusScheduleActive,
              lifecyclePauseStartedAt == nil,
              activeSession == nil else { return }

        doomscrollTimerGeneration += 1
        let generation = doomscrollTimerGeneration
        let contextGeneration = self.contextGeneration
        let contextIdentity = snapshot.identity
        doomscrollingBundleID = snapshot.bundleIdentifier
        doomscrollContextGeneration = contextGeneration
        doomscrollContextIdentity = contextIdentity
        doomscrollThresholdAtSchedule = threshold
        doomscrollStartedAt = snapshot.observedAt
        activeDoomscrollTimerGeneration = generation
        hasFiredDoomscrollAlert = false
        RuntimeTrace.event("doomscroll_timer_scheduled", fields: [
            "bundleID": snapshot.bundleIdentifier,
            "threshold": String(threshold),
            "generation": String(generation)
        ])
        doomscrollTimer = doomscrollTimerScheduler.schedule(after: threshold) { [weak self] in
            self?.doomscrollTimerExpired(
                bundleID: snapshot.bundleIdentifier,
                contextIdentity: contextIdentity,
                contextGeneration: contextGeneration,
                generation: generation,
                threshold: threshold
            )
        }
    }

    private func cancelDoomscrollTimer() {
        doomscrollTimer?.cancel()
        doomscrollTimer = nil
        activeDoomscrollTimerGeneration = nil
        doomscrollingBundleID = nil
        doomscrollContextGeneration = nil
        doomscrollContextIdentity = nil
        doomscrollThresholdAtSchedule = nil
        doomscrollStartedAt = nil
    }

    private func resetDoomscrollTimer() {
        cancelDoomscrollTimer()
        hasFiredDoomscrollAlert = false
    }

    internal func doomscrollTimerExpired(now: Date = Date()) {
        doomscrollTimerExpired(
            bundleID: doomscrollingBundleID,
            contextIdentity: doomscrollContextIdentity,
            contextGeneration: doomscrollContextGeneration ?? contextGeneration,
            generation: activeDoomscrollTimerGeneration ?? doomscrollTimerGeneration,
            threshold: doomscrollThresholdAtSchedule ?? preferencesManager.doomscrollThreshold,
            now: now
        )
    }

    private func doomscrollTimerExpired(
        bundleID: String?,
        contextIdentity: ContextIdentity?,
        contextGeneration: Int,
        generation: Int,
        threshold: TimeInterval,
        now: Date = Date()
    ) {
        guard lifecyclePauseStartedAt == nil,
              preferencesManager.enableDoomscrollLoopBreaker,
              isFocusScheduleActive,
              activeSession == nil,
              !hasFiredDoomscrollAlert,
              let bundleID,
              let contextIdentity,
              doomscrollingBundleID == bundleID,
              doomscrollContextIdentity == contextIdentity,
              doomscrollContextGeneration == contextGeneration,
              activeDoomscrollTimerGeneration == generation,
              doomscrollThresholdAtSchedule == threshold,
              let startedAt = doomscrollStartedAt,
              now.timeIntervalSince(startedAt) >= threshold,
              currentClassification.isDistraction,
              currentIdentity == contextIdentity,
              currentApp == bundleID else {
            return
        }

        hasFiredDoomscrollAlert = true
        doomscrollTimer = nil
        activeDoomscrollTimerGeneration = nil
        RuntimeTrace.event("doomscroll_timer_expired", fields: [
            "bundleID": bundleID,
            "threshold": String(threshold),
            "generation": String(generation)
        ])
        delegate?.didDetectDoomscrolling(bundleID: bundleID, threshold: threshold)
    }

    private static func cleanedSuggestedLabel(_ text: String?) -> String? {
        let cleaned = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned, !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private static func isGenericSuggestedLabel(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let genericLabels = [
            "google chrome",
            "chrome",
            "safari",
            "firefox",
            "mozilla firefox",
            "microsoft edge",
            "brave browser",
            "browser",
            "new tab",
            "untitled",
            "blank page",
            "page"
        ]

        if genericLabels.contains(where: { normalized == $0 || normalized.hasPrefix("\($0) ") }) {
            return true
        }

        return normalized.count < 3
    }

    private static func bestSuggestedProfile(
        bundleID: String?,
        url: URL?,
        title: String,
        profiles: [WorkProfile],
        fallback: WorkProfile
    ) -> WorkProfile {
        guard !profiles.isEmpty else { return fallback }

        let normalizedBundleID = bundleID?.lowercased() ?? ""
        let normalizedHost = url?.host?.lowercased() ?? ""
        let normalizedTitle = ContextSanitizer.sanitizeTitle(title).lowercased()

        let scoredProfiles = profiles.map { profile -> (profile: WorkProfile, score: Int) in
            var score = 0

            if !normalizedBundleID.isEmpty {
                if profile.allowedApps.contains(where: { $0.lowercased() == normalizedBundleID }) {
                    score += 4
                }
                if profile.distractionApps.contains(where: { $0.lowercased() == normalizedBundleID }) {
                    score -= 4
                }
            }

            if !normalizedHost.isEmpty {
                if profile.allowedDomains.contains(where: { normalizedHost == $0.lowercased() || normalizedHost.hasSuffix(".\($0.lowercased())") }) {
                    score += 3
                }
                if profile.distractionDomains.contains(where: { normalizedHost == $0.lowercased() || normalizedHost.hasSuffix(".\($0.lowercased())") }) {
                    score -= 3
                }
            }

            if !normalizedTitle.isEmpty,
               normalizedTitle.contains(profile.name.lowercased()) {
                score += 1
            }

            return (profile, score)
        }

        if let bestMatch = scoredProfiles.max(by: { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.profile.name < rhs.profile.name
            }
            return lhs.score < rhs.score
        }), bestMatch.score > 0 {
            return bestMatch.profile
        }

        return fallback
    }

    private func resolvedSessionAppName(fallbackCategory: String) -> String {
        let candidates: [String?] = [
            getAppName(for: lastWorkAppBundleID ?? currentApp ?? ""),
            currentContext?.localizedName,
            Self.cleanedSuggestedLabel(fallbackCategory),
            profileManager.activeProfile.name
        ]

        for candidate in candidates {
            guard let cleaned = Self.cleanedSuggestedLabel(candidate),
                  !cleaned.isEmpty else {
                continue
            }
            return cleaned
        }

        return "Manual Focus Session"
    }
    
    private func getAppName(for bundleID: String) -> String {
        if bundleID.isEmpty { return "" }
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = runningApp.localizedName, !name.isEmpty {
            return name
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let lastComponent = appURL.deletingPathExtension().lastPathComponent
            if !lastComponent.isEmpty {
                return lastComponent
            }
        }
        if let lastComponent = bundleID.split(separator: ".").last {
            let cleaned = String(lastComponent)
            if !cleaned.isEmpty {
                return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
            }
        }
        return bundleID
    }

    private func shouldSuppressSuggestedGoalCandidate(bundleID: String?, url: URL?, title: String) -> Bool {
        let normalizedTitle = ContextSanitizer.sanitizeTitle(title).lowercased()
        guard !normalizedTitle.isEmpty else { return false }

        let normalizedHost = url?.host?.lowercased() ?? ""
        let entertainmentHosts = [
            "youtube.com",
            "youtu.be",
            "vimeo.com",
            "twitch.tv",
            "netflix.com",
            "hulu.com",
            "tiktok.com",
            "instagram.com",
            "facebook.com",
            "x.com",
            "twitter.com"
        ]
        if entertainmentHosts.contains(where: { normalizedHost == $0 || normalizedHost.hasSuffix(".\($0)") }) {
            return true
        }

        guard let bundleID, BrowserStrategyFactory.isSupportedBrowser(bundleID) else {
            return false
        }

        let entertainmentTitleSignals = [
            "video",
            "lecture",
            "course",
            "tutorial",
            "watch",
            "stream",
            "episode",
            "movie",
            "gaming",
            "gameplay"
        ]

        return entertainmentTitleSignals.contains { normalizedTitle.contains($0) }
    }
}

enum SmartAppClassifier {
    private static let lock = NSLock()
    private static var cache: [String: Bool] = [:]

    static func isProductiveApp(bundleID: String) -> Bool {
        lock.lock()
        if let cached = cache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = computeIsProductiveApp(bundleID: bundleID)

        lock.lock()
        cache[bundleID] = result
        lock.unlock()

        return result
    }

    private static func computeIsProductiveApp(bundleID: String) -> Bool {
        let bundleLower = bundleID.lowercased()
        if bundleLower.contains("antigravity") ||
           bundleLower.contains("xcode") ||
           bundleLower.contains("vscode") ||
           bundleLower.contains("terminal") ||
           bundleLower.contains("iterm") ||
           bundleLower.contains("warp") ||
           bundleLower.contains("cursor") ||
           bundleLower.contains("windsurf") ||
           bundleLower.contains("zed") {
            return true
        }
        
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlistURL.path),
              let dict = NSDictionary(contentsOf: infoPlistURL) else {
            return false
        }
        
        let name = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let category = (dict["LSApplicationCategoryType"] as? String) ?? ""
        
        let nameLower = name.lowercased()
        let categoryLower = category.lowercased()
        
        let isProductiveCategory = categoryLower.contains("developer-tools") ||
                                   categoryLower.contains("graphics-design") ||
                                   categoryLower.contains("video") ||
                                   categoryLower.contains("productivity") ||
                                   categoryLower.contains("photography") ||
                                   categoryLower.contains("business")
                                   
        let matchesKeywords = nameLower.contains("xcode") ||
                              nameLower.contains("vscode") ||
                              nameLower.contains("cursor") ||
                              nameLower.contains("windsurf") ||
                              nameLower.contains("zed") ||
                              nameLower.contains("studio") ||
                              nameLower.contains("intellij") ||
                              nameLower.contains("rider") ||
                              nameLower.contains("webstorm") ||
                              nameLower.contains("clion") ||
                              nameLower.contains("sublime") ||
                              nameLower.contains("textmate") ||
                              nameLower.contains("terminal") ||
                              nameLower.contains("iterm") ||
                              nameLower.contains("warp") ||
                              nameLower.contains("figma") ||
                              nameLower.contains("blender") ||
                              nameLower.contains("photoshop") ||
                              nameLower.contains("illustrator") ||
                              nameLower.contains("premiere") ||
                              nameLower.contains("final cut") ||
                              nameLower.contains("davinci") ||
                              nameLower.contains("unity") ||
                              nameLower.contains("unreal") ||
                              nameLower.contains("notion") ||
                              nameLower.contains("obsidian") ||
                              nameLower.contains("bear") ||
                              nameLower.contains("craft") ||
                              nameLower.contains("drafts") ||
                              nameLower.contains("onenote") ||
                              nameLower.contains("antigravity")
                              
        return isProductiveCategory || matchesKeywords
    }
}

enum SmartWebClassifier {
    static func isCodingForumOrDoc(url: URL?, title _: String) -> Bool {
        let urlString = url?.absoluteString.lowercased() ?? ""
        
        let codingKeywords = [
            "github", "stackoverflow", "stackexchange", "medium.com", "dev.to",
            "developer", "programming", "coding", "software", "hackernews",
            "hacker news", "swift", "kotlin", "java", "python", "rust-lang",
            "documentation", "api", "tutorial", "w3schools", "mdn",
            "git", "forum", "co-pilot", "chatgpt", "claude", "gemini",
            "copilot", "google ai", "deepmind", "course", "learn", "how to",
            "setup", "install", "docker", "react", "typescript", "javascript",
            "css", "html", "database", "mongodb", "postgres", "sql", "compiler",
            "kubernetes", "flutter", "vue", "angular", "node.js", "next.js"
        ]
        
        // Titles alone are weak and may be arbitrary user text. Require a
        // URL signal before promoting a browser context to productive.
        let matchesKeyword = codingKeywords.contains { keyword in
            urlString.contains(keyword)
        }
        
        return matchesKeyword
    }
}

enum SmartImageClassifier {
    static func isProductiveVisual(profileName: String, preferences prefs: PreferencesManager = .shared) -> Bool {
        guard prefs.enableImageClassification else {
            return false
        }
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let pid = frontmostApp.processIdentifier
        let windowListInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        var targetWindowID: CGWindowID?
        
        for info in windowListInfo {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID == pid {
                if let windowID = info[kCGWindowNumber as String] as? CGWindowID {
                    targetWindowID = windowID
                    break
                }
            }
        }
        
        guard let windowID = targetWindowID,
              let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming) else {
            return false
        }
        
        var extractedScreenText = ""
        let textRequest = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            for observation in observations.prefix(20) {
                if let candidate = observation.topCandidates(1).first {
                    extractedScreenText += candidate.string + " "
                }
            }
        }
        textRequest.recognitionLevel = .fast
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try requestHandler.perform([textRequest])
        } catch {}
        
        let lowerText = extractedScreenText.lowercased()
        let codeKeywords = ["func ", "struct ", "class ", "import ", "var ", "let ", "public ", "private ", "return ", "if ", "else ", "switch ", "case ", "<html>", "<div>", "function(", "const ", "console.log", "def ", "print("]
        
        var codeHits = 0
        for keyword in codeKeywords {
            if lowerText.contains(keyword) {
                codeHits += 1
            }
        }
        
        if codeHits >= 2 {
            return true
        }
        
        var isProductive = false
        let request = VNClassifyImageRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNClassificationObservation] else {
                return
            }
            
            let productiveLabels = ["computer", "screen", "text", "terminal", "workspace", "code", "document", "chart", "diagram"]
            let distractionLabels = ["video game", "game", "movie", "television", "playing", "entertainment"]
            
            var highestConfidence: Float = 0.0
            
            for observation in observations.prefix(5) {
                let label = observation.identifier.lowercased()
                let confidence = observation.confidence
                
                let isDistraction = distractionLabels.contains(where: { label.contains($0) })
                let isProd = productiveLabels.contains(where: { label.contains($0) })
                
                if isDistraction {
                    // Distraction matches override productive matches
                    // We use >= to ensure distraction wins if confidence is tied
                    if confidence >= highestConfidence {
                        highestConfidence = confidence
                        isProductive = false
                    }
                } else if isProd {
                    if confidence > highestConfidence {
                        highestConfidence = confidence
                        isProductive = true
                    }
                }
            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            return false
        }
        
        return isProductive
    }
}

extension Notification.Name {
    static let focusEngineStateDidChange = Notification.Name("com.varun.Anchored.focusEngineStateDidChange")
    static let focusEngineContextDidChange = Notification.Name("com.varun.Anchored.focusEngineContextDidChange")
    static let focusEngineClassificationDidChange = Notification.Name("com.varun.Anchored.focusEngineClassificationDidChange")
    static let focusScheduleDidChange = Notification.Name("com.varun.Anchored.focusScheduleDidChange")
}

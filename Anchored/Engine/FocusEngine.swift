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
    private let breakReviewChecker: BreakReviewChecking
    
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

    /// The latest safe, UI-facing classification decision for the current context.
    private(set) var currentClassification: ClassificationDecision = .neutral()
    
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
    
    /// Productive time selected in onboarding before a focus-session prompt appears.
    var focusThreshold: TimeInterval {
        didSet {
            scheduleFocusPromptTimer()
        }
    }

    /// Whether the onboarding Smart Nudges preference allows proactive prompts.
    var focusPromptsEnabled = true {
        didSet {
            if focusPromptsEnabled {
                scheduleFocusPromptTimer()
            } else {
                cancelFocusPromptTimer()
            }
        }
    }
    
    /// The threshold for the distraction countdown pill (default 10 seconds).
    var distractionCountdownThreshold: TimeInterval = 10.0
    
    // Timers
    private var distractionTimer: Timer?
    private var sessionTimer: Timer?
    private var focusPromptTimer: Timer?
    private var hasPromptedForCurrentFocusRun = false
    
    // Doomscroll loop breaker
    private var doomscrollTimer: Timer?
    /// The bundle ID of the app the user started doomscrolling in.
    private(set) var doomscrollingBundleID: String?
    private(set) var hasFiredDoomscrollAlert = false
    
    // Idle tracking
    var totalIdleTime: TimeInterval = 0.0
    private var idleTimer: Timer?
    
    /// The date when the user entered a distraction app.
    private var distractionStartDate: Date?
    
    /// The date when the active focus session was paused.
    public var pausedDate: Date?

    /// The current memory-only break lifecycle, if a break is in flight.
    private(set) var breakState: CommitmentState?
    private(set) var activeBreakCommitment: BreakCommitment?
    private var breakTimer: Timer?
    private var breakStartedAt: Date?
    private var excludedBreakDuration: TimeInterval = 0

    /// Invalidates optional classifier results whenever the foreground context changes.
    private var contextGeneration = 0
    
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
        breakReviewChecker: BreakReviewChecking = ConservativeBreakReviewChecker()
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
        self.localTextClassifier = localTextClassifier ?? LocalTextClassifier()
        self.breakReviewChecker = breakReviewChecker
        
        self.activityMonitor.onContextChange = { [weak self] snapshot in
            self?.handleContextChange(bundleID: snapshot.bundleIdentifier, url: snapshot.url, title: snapshot.title, snapshot: snapshot)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleActiveProfileChange),
            name: .activeProfileDidChange,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceLifecyclePause),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceLifecyclePause),
            name: NSWorkspace.sessionDidResignActiveNotification,
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
        activityMonitor.start()
    }
    
    /// Stops monitoring application switch events.
    func stop() {
        RuntimeTrace.event("focus_engine_stop")
        activityMonitor.stop()
        cancelSessionTimer()
        cancelDistractionTimer()
        cancelFocusPromptTimer()
        cancelIdleTimer()
        cancelBreakTimer()
        cancelDoomscrollTimer()
        clearBreakState(at: Date())
    }

    @objc private func handleWorkspaceLifecyclePause() {
        guard activeBreakCommitment != nil else { return }
        resumeAfterBreakReview()
    }
    
    private func classifyContext(bundleID: String, url: URL?, title: String) -> ClassificationDecision {
        classificationResolver.resolve(
            distractionEvaluator.evidence(bundleID: bundleID, url: url, title: title),
            interactionSummary: preferencesManager.interactionSummaryEnabled
                ? interactionSummaryProvider.summary(at: Date())
                : nil
        )
    }

    private func isDistraction(bundleID: String, url: URL?, title: String) -> Bool {
        classifyContext(bundleID: bundleID, url: url, title: title).isDistraction
    }

    private func isFocusContext(bundleID: String, url: URL?, title: String) -> Bool {
        classifyContext(bundleID: bundleID, url: url, title: title).isFocus
    }

    private func triggerCloudOrVisualFallback(bundleID: String, url: URL?, title: String, generation: Int) {
        guard generation == contextGeneration,
              currentApp == bundleID,
              currentURL == url,
              currentTitle == title else { return }

        if preferencesManager.enableCloudClassification {
            RuntimeTrace.event("fallback_cloud_selected", fields: ["bundleID": bundleID, "generation": String(generation)])
            triggerAsyncCloudClassification(bundleID: bundleID, url: url, title: title, generation: generation)
        } else if preferencesManager.enableImageClassification {
            RuntimeTrace.event("fallback_visual_selected", fields: ["bundleID": bundleID, "generation": String(generation)])
            triggerAsyncVisualClassification(bundleID: bundleID, url: url, title: title, generation: generation)
        } else {
            RuntimeTrace.event("fallbacks_disabled", fields: ["bundleID": bundleID, "generation": String(generation)])
        }
    }

    private func triggerAsyncCloudClassification(bundleID: String, url: URL?, title: String, generation: Int) {
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
                guard let self,
                      generation == self.contextGeneration,
                      self.currentApp == bundleID,
                      self.currentURL == url,
                      self.currentTitle == title else {
                    RuntimeTrace.event("cloud_result_discarded_stale", fields: ["bundleID": bundleID, "generation": String(generation)])
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

                if case .success(let evidence) = result,
                   (evidence.label == .productive || evidence.label == .distracting),
                   evidence.confidence >= ClassificationPolicy.highConfidenceThreshold,
                   self.promoteNeutralContextIfCurrent(
                       bundleID: bundleID,
                       url: url,
                       title: title,
                       generation: generation,
                       promotion: ClassificationEvidence(
                           label: evidence.label,
                           source: .cloudModel,
                           confidence: evidence.confidence,
                           reason: .modelEvidence
                       )
                   ) {
                    RuntimeTrace.event("cloud_promotion_applied", fields: [
                        "bundleID": bundleID,
                        "label": evidence.label.rawValue,
                        "generation": String(generation)
                    ])
                    return
                }

                if self.preferencesManager.enableImageClassification {
                    RuntimeTrace.event("cloud_did_not_promote_using_visual_fallback", fields: ["bundleID": bundleID])
                    self.triggerAsyncVisualClassification(bundleID: bundleID, url: url, title: title, generation: generation)
                } else {
                    RuntimeTrace.event("cloud_did_not_promote_no_visual_fallback", fields: ["bundleID": bundleID])
                }
            }
        }
    }

    private func triggerAsyncVisualClassification(bundleID: String, url: URL?, title: String, generation: Int) {
        guard preferencesManager.enableImageClassification else { return }
        let profileName = profileManager.activeProfile.name
        RuntimeTrace.event("visual_classification_started", fields: ["bundleID": bundleID, "generation": String(generation)])
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let isProductive = self?.visualChecker.isProductiveVisual(profileName: profileName) == true
            DispatchQueue.main.async {
                RuntimeTrace.event("visual_classification_finished", fields: [
                    "bundleID": bundleID,
                    "productive": String(isProductive)
                ])
                guard isProductive else { return }
                let promoted = self?.promoteNeutralContextIfCurrent(
                    bundleID: bundleID,
                    url: url,
                    title: title,
                    generation: generation,
                    promotion: ClassificationEvidence(
                        label: .productive,
                        source: .visualFallback,
                        confidence: 0.85,
                        reason: .modelEvidence
                    )
                )
                RuntimeTrace.event("visual_productive_promotion_result", fields: [
                    "bundleID": bundleID,
                    "applied": String(promoted == true)
                ])
            }
        }
    }

    @discardableResult
    private func promoteNeutralContextIfCurrent(
        bundleID: String,
        url: URL?,
        title: String,
        generation: Int,
        promotion: ClassificationEvidence
    ) -> Bool {
        guard generation == contextGeneration,
              currentApp == bundleID,
              currentURL == url,
              currentTitle == title,
              classifyContext(bundleID: bundleID, url: url, title: title).isNeutral else {
            return false
        }

        let currentEvidence = distractionEvaluator.evidence(bundleID: bundleID, url: url, title: title)
        let promotedDecision = classificationResolver.resolve(currentEvidence + [promotion])
        guard promotedDecision.isFocus || promotedDecision.isDistraction else {
            return false
        }

        currentClassification = promotedDecision
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)

        if promotedDecision.isFocus {
            lastWorkAppBundleID = bundleID
            if activeSession != nil {
                let needsUIUpdate = distractionStartDate != nil && !isDimming
                resumeSessionIfNeeded()
                if needsUIUpdate {
                    delegate?.didReturnToWork()
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
        } else if promotedDecision.isDistraction {
            if activeSession != nil {
                if distractionStartDate == nil {
                    distractionStartDate = Date()
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
                    scheduleDistractionTimer(distractionBundleID: bundleID)
                }
            } else {
                requestFocusPromptIfEligible(now: Date())
                resetFocusTracking()
            }
        }
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: nil)
        return true
    }
    
    @objc private func handleActiveProfileChange() {
        guard let currentApp = currentApp else { return }
        
        let now = Date()
        let decision = classifyContext(
            bundleID: currentApp,
            url: currentURL,
            title: currentTitle
        )
        currentClassification = decision
        NotificationCenter.default.post(name: .focusEngineClassificationDidChange, object: self)
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
                }
            } else {
                // No active session
                if workSessionStart != nil {
                    requestFocusPromptIfEligible(now: now)
                }
                resetFocusTracking()
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
        
        let decision = classifyContext(bundleID: bundleID, url: url, title: title)
        currentClassification = decision
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

        if decision.isNeutral {
            let generation = contextGeneration
            if preferencesManager.enableLocalTextClassification {
                RuntimeTrace.event("neutral_local_text_selected", fields: ["bundleID": bundleID, "generation": String(generation)])
                triggerAsyncLocalTextClassification(snapshot: actualSnapshot, generation: generation)
            } else {
                RuntimeTrace.event("neutral_cloud_visual_pipeline_selected", fields: ["bundleID": bundleID, "generation": String(generation)])
                triggerCloudOrVisualFallback(bundleID: bundleID, url: url, title: title, generation: generation)
            }
        }

        // A committed break or declared activity bypass suspends normal enforcement
        if activeBreakCommitment != nil || isDeclaredActivityBypassActive {
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
                }
            } else {
                // Distraction app detected + no session → start doomscroll timer
                scheduleDoomscrollTimer(bundleID: bundleID)
                requestFocusPromptIfEligible(now: now)
                resetFocusTracking()
            }
        } else if decision.isFocus {
            // Whitelisted focus app/URL detected
            RuntimeTrace.event("focus_context_applied", fields: ["bundleID": bundleID, "activeSession": String(activeSession != nil)])
            print("📈 [Focus Context] bundleID=\(bundleID) appName=\(context.localizedName) domain=\(url?.host ?? "nil") focus=true titleLen=\(title.count)")
            lastWorkAppBundleID = bundleID
            
            if activeSession != nil {
                let needsUIUpdate = (distractionStartDate != nil && !isDimming)
                resumeSessionIfNeeded()
                if needsUIUpdate {
                    delegate?.didReturnToWork()
                }
                cancelDistractionTimer()
                distractionStartDate = nil
            } else {
                cancelDoomscrollTimer()
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
                let needsUIUpdate = (distractionStartDate != nil && !isDimming)
                resumeSessionIfNeeded()
                if needsUIUpdate {
                    delegate?.didReturnToWork()
                }
                cancelDistractionTimer()
                distractionStartDate = nil
            } else {
                // Neutral context: cancel any doomscroll tracking
                cancelDoomscrollTimer()
                // Check if the user accumulated enough focus time on the previous focus app before switching away
                requestFocusPromptIfEligible(now: now)
                resetFocusTracking()
            }
        }
    }

    private func triggerAsyncLocalTextClassification(snapshot: ContextSnapshot, generation: Int) {
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
            let result = self.localTextClassifier.classify(snapshot: sanitizedSnapshot)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.contextGeneration,
                      self.currentApp == snapshot.bundleIdentifier,
                      self.currentURL == snapshot.url,
                      self.currentTitle == snapshot.title else {
                    RuntimeTrace.event("local_text_result_discarded_stale", fields: ["bundleID": snapshot.bundleIdentifier, "generation": String(generation)])
                    return
                }

                RuntimeTrace.event("local_text_classification_finished", fields: [
                    "bundleID": snapshot.bundleIdentifier,
                    "label": result.label.rawValue,
                    "confidence": String(result.confidence),
                    "latencyMs": String(Int(result.latency * 1000))
                ])

                if (result.label == .productive || result.label == .distracting),
                   result.confidence >= ClassificationPolicy.highConfidenceThreshold,
                   self.promoteNeutralContextIfCurrent(
                       bundleID: snapshot.bundleIdentifier,
                       url: snapshot.url,
                       title: snapshot.title,
                       generation: generation,
                       promotion: ClassificationEvidence(
                           label: result.label,
                           source: .localModel,
                           confidence: result.confidence,
                           reason: .modelEvidence
                       )
                   ) {
                    return
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
            
            delegate?.didReturnToWork()
        }
    }

    /// Requests a memory-only break from the active session.
    @discardableResult
    func requestBreak(intention: String, now: Date = Date(), bypassMinimum: Bool = false) -> BreakRequestDecision {
        guard let session = activeSession else {
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
            cancelSessionTimer()
            cancelDistractionTimer()
            distractionStartDate = nil
            isDimming = false
            delegate?.didReturnToWork()
            breakTimer = Timer.scheduledTimer(withTimeInterval: CommitmentPolicy.breakDuration, repeats: false) { [weak self] _ in
                self?.breakTimerExpired()
            }
            NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
        }

        return decision
    }

    /// Resumes the active session after a break review or explicit cancellation.
    func resumeAfterBreakReview(now: Date = Date()) {
        guard activeBreakCommitment != nil else { return }
        clearBreakState(at: now)
        guard let session = activeSession else { return }
        let remaining = max(0, session.anchoredDuration - currentSessionFocusedTime(at: now))
        scheduleSessionTimer(duration: remaining)
        delegate?.didReturnToWork()
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    func resumeSessionFromUI() {
        isDimming = false
        pausedDate = nil
        cancelDistractionTimer()
        distractionStartDate = nil
        delegate?.didReturnToWork()
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: self)
    }

    func startDeclaredActivityBypass(activity: String) {
        guard activeSession != nil else { return }
        declaredActivity = activity
        isDeclaredActivityBypassActive = true
        
        isDimming = false
        cancelDistractionTimer()
        distractionStartDate = nil
        delegate?.didReturnToWork()
        
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
        guard isDeclaredActivityBypassActive else { return }
        
        let now = Date()
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
        guard let commitment = activeBreakCommitment else { return }
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
        if let breakStartedAt {
            excludedBreakDuration += max(0, date.timeIntervalSince(breakStartedAt))
        }
        breakStartedAt = nil
        activeBreakCommitment = nil
        breakState = nil
    }

    private func cancelBreakTimer() {
        breakTimer?.invalidate()
        breakTimer = nil
    }
    
    /// Applies a user correction as an explicit profile rule.
    func applyCorrection(_ correction: ClassificationCorrection) {
        guard let bundleID = currentApp else { return }
        let originalDecision = currentClassification
        guard profileManager.applyCorrection(correction, bundleID: bundleID, url: currentURL) else { return }

        // ProfileManager broadcasts the profile change synchronously. Re-read
        // the current context so callers observe the correction immediately.
        currentClassification = classifyContext(bundleID: bundleID, url: currentURL, title: currentTitle)
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
    }

    /// Locks in an active focused session.
    func anchorSession(duration: TimeInterval, category: String? = nil, goal: String? = nil) {
        let now = Date()
        let start = workSessionStart ?? now
        let focusedAppName = getAppName(for: lastWorkAppBundleID ?? "")

        activeSessionIdentity = UUID()
        excludedBreakDuration = 0
        
        let session = ActiveSession(
            startDate: start,
            anchoredDuration: duration,
            appName: focusedAppName,
            category: category,
            goal: goal
        )
        self.activeSession = session
        RuntimeTrace.event("session_anchored", fields: [
            "duration": String(duration),
            "appBundleID": lastWorkAppBundleID ?? "",
            "hasGoal": String(goal != nil)
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
            category: category,
            sessionGoal: goal
        )
        print("⚓️ [Session Started] AppName: \(focusedAppName) | Duration: \(duration)s | Goal: \(goal ?? "None")")
        sessionStore.log(event)
        
        // Schedule session end timer (accounting for retroactive time)
        let remaining = max(0, duration - now.timeIntervalSince(start))
        scheduleSessionTimer(duration: remaining)
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: nil)
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
        
        // Clean up state
        activeSession = nil
        activeSessionIdentity = nil
        clearBreakState(at: now)
        stopDeclaredActivityBypass()
        resetFocusTracking()
        isDimming = false
        distractionStartDate = nil
        pausedDate = nil
        
        cancelSessionTimer()
        cancelDistractionTimer()
        
        // Notify delegate
        delegate?.sessionDidEnd()
        
        NotificationCenter.default.post(name: .focusEngineStateDidChange, object: nil)
        
        // Present Permission Gate immediately for testing if accessibility is not yet granted
        if !AXIsProcessTrusted() {
            delegate?.didRequestPermissionGate()
        }
    }
    
    /// Returns the net focused time for the active session (subtracting idle time).
    func currentSessionFocusedTime() -> TimeInterval {
        currentSessionFocusedTime(at: Date())
    }

    private func currentSessionFocusedTime(at date: Date) -> TimeInterval {
        guard let session = activeSession else { return 0.0 }
        let rawDuration = date.timeIntervalSince(session.startDate)
        let activeBreakDuration = breakStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
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
              activeSession == nil,
              !hasPromptedForCurrentFocusRun,
              let start = workSessionStart else {
            return
        }

        let remaining = max(0, focusThreshold - Date().timeIntervalSince(start))
        focusPromptTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.focusPromptTimerExpired()
        }
    }

    private func cancelFocusPromptTimer() {
        focusPromptTimer?.invalidate()
        focusPromptTimer = nil
    }

    private func resetFocusTracking() {
        cancelFocusPromptTimer()
        workSessionStart = nil
        hasPromptedForCurrentFocusRun = false
    }

    private func requestFocusPromptIfEligible(now: Date) {
        guard focusPromptsEnabled,
              activeSession == nil,
              !hasPromptedForCurrentFocusRun,
              let start = workSessionStart else {
            return
        }

        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= focusThreshold else { return }

        hasPromptedForCurrentFocusRun = true
        RuntimeTrace.event("focus_prompt_requested", fields: [
            "elapsed": String(now.timeIntervalSince(start)),
            "threshold": String(focusThreshold),
            "appBundleID": lastWorkAppBundleID ?? currentApp ?? ""
        ])
        cancelFocusPromptTimer()
        let focusedAppName = getAppName(for: lastWorkAppBundleID ?? currentApp ?? "")
        delegate?.didRequestExitTrigger(duration: elapsed, appName: focusedAppName)
    }

    internal func focusPromptTimerExpired() {
        cancelFocusPromptTimer()
        guard let bundleID = currentApp,
              classifyContext(bundleID: bundleID, url: currentURL, title: currentTitle).isFocus else {
            return
        }

        requestFocusPromptIfEligible(now: Date())
        if !hasPromptedForCurrentFocusRun {
            scheduleFocusPromptTimer()
        }
    }
    
    private func scheduleSessionTimer(duration: TimeInterval) {
        cancelSessionTimer()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.sessionTimerExpired()
        }
    }
    
    private func cancelSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }
    
    internal func sessionTimerExpired() {
        endSession(action: .timeout)
    }
    
    private func scheduleDistractionTimer(distractionBundleID: String) {
        cancelDistractionTimer()
        distractionTimer = Timer.scheduledTimer(withTimeInterval: distractionCountdownThreshold, repeats: false) { [weak self] _ in
            self?.distractionTimerExpired(distractionBundleID: distractionBundleID)
        }
    }
    
    private func cancelDistractionTimer() {
        distractionTimer?.invalidate()
        distractionTimer = nil
    }
    
    internal func distractionTimerExpired(distractionBundleID: String) {
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
    
    // MARK: - Doomscroll Loop Breaker
    
    private func scheduleDoomscrollTimer(bundleID: String) {
        guard preferencesManager.enableDoomscrollLoopBreaker else { return }
        guard doomscrollTimer == nil else { return }
        doomscrollingBundleID = bundleID
        hasFiredDoomscrollAlert = false
        let threshold = preferencesManager.doomscrollThreshold
        RuntimeTrace.event("doomscroll_timer_scheduled", fields: ["bundleID": bundleID, "threshold": String(threshold)])
        doomscrollTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [weak self] _ in
            self?.doomscrollTimerExpired()
        }
    }
    
    private func cancelDoomscrollTimer() {
        doomscrollTimer?.invalidate()
        doomscrollTimer = nil
        doomscrollingBundleID = nil
        hasFiredDoomscrollAlert = false
    }
    
    internal func doomscrollTimerExpired() {
        guard let bundleID = doomscrollingBundleID,
              activeSession == nil else {
            cancelDoomscrollTimer()
            return
        }
        hasFiredDoomscrollAlert = true
        let threshold = preferencesManager.doomscrollThreshold
        RuntimeTrace.event("doomscroll_timer_expired", fields: ["bundleID": bundleID, "threshold": String(threshold)])
        delegate?.didDetectDoomscrolling(bundleID: bundleID, threshold: threshold)
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
}

enum SmartAppClassifier {
    static func isProductiveApp(bundleID: String) -> Bool {
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
        
        if prefs.useLocalGemma {
            var gemmaResult: Bool?
            let semaphore = DispatchSemaphore(value: 0)
            
            let appName = frontmostApp.localizedName ?? ""
            let windowTitle = windowListInfo.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID })?[kCGWindowName as String] as? String ?? ""
            
            let escapedAppName = appName.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'")
            let escapedWindowTitle = windowTitle.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'")
            let truncatedText = String(extractedScreenText.prefix(250))
            let escapedText = truncatedText.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: " ")
            
            let prompt = "<|im_start|>user\\nIs the application '\(escapedAppName)' with window title '\(escapedWindowTitle)' and screen text '\(escapedText)' productive for \(profileName)? Answer only 'yes' or 'no'.<|im_end|>\\n<|im_start|>assistant\\n"
            
            let pythonCode = """
import sys
try:
    from mlx_lm import load, generate
    try:
        model, tokenizer = load('mlx-community/Qwen2.5-0.5B-Instruct-4bit')
    except Exception:
        try:
            model, tokenizer = load('mlx-community/gemma-3-270m-8bit')
        except Exception:
            model, tokenizer = load('mlx-community/SmolVLM-256M-Instruct-4bit')
        
    response = generate(
        model,
        tokenizer,
        prompt="\(prompt)",
        verbose=False,
        max_tokens=5
    )
    print(response)
except Exception as e:
    print('error', file=sys.stderr)
"""
            let process = Process()
            process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "")]
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-c", pythonCode]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            
            do {
                try process.run()
                
                // Allow up to 1.5 seconds for local model execution since OCR took a bit
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 1.5) {
                    if process.isRunning {
                        process.terminate()
                    }
                    semaphore.signal()
                }
                
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if cleaned.contains("yes") {
                            gemmaResult = true
                        } else if cleaned.contains("no") {
                            gemmaResult = false
                        }
                    }
                }
            } catch {
                semaphore.signal()
            }
            
            _ = semaphore.wait(timeout: .now() + 1.7)
            if let result = gemmaResult {
                return result
            }
        }
        
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
}

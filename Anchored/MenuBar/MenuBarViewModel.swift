import SwiftUI
import Combine

struct ProductiveCorrectionDraft: Equatable {
    let snapshot: ContextSnapshot
    let bundleID: String
    let url: URL?
    let title: String
    var message: String
    var recommendedScope: ProductiveCorrectionScope
    var canUseWebsiteScope: Bool
    var isChecking: Bool
}

enum ProductiveCorrectionState: Equatable {
    case idle
    case active(ProductiveCorrectionDraft)
}

class MenuBarViewModel: ObservableObject {
    let focusEngine: FocusEngine
    private let sessionStore: SessionStore
    private var timer: AnyCancellable?
    
    @Published var activeSession: ActiveSession?
    @Published var currentAppBundleID: String?
    @Published var remainingTimeFormatted: String = ""
    @Published var progress: Double = 0.0
    @Published var stats: SessionStats = SessionStats(focusedTimeToday: 0, sessionCountToday: 0, streakDays: 0)
    @Published var recentSessions: [SessionEvent] = []
    @Published var currentClassification: ClassificationDecision = .neutral()
    @Published var breakState: CommitmentState?
    @Published var breakDeadline: Date?
    @Published var productiveCorrectionState: ProductiveCorrectionState = .idle
    
    init(focusEngine: FocusEngine, sessionStore: SessionStore = .shared) {
        self.focusEngine = focusEngine
        self.sessionStore = sessionStore
        
        self.refresh()
        
        // Timer fires every second to update countdown and check for state changes in FocusEngine
        self.timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTime()
            }
        
        // Observe focus engine state change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .focusEngineStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClassificationChange),
            name: .focusEngineClassificationDidChange,
            object: focusEngine
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClassificationChange),
            name: .focusEngineContextDidChange,
            object: focusEngine
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleStateChange() {
        DispatchQueue.main.async {
            self.refresh()
        }
    }

    @objc private func handleClassificationChange() {
        DispatchQueue.main.async {
            self.currentClassification = self.focusEngine.currentClassification
        }
    }
    
    private var statsGeneration: Int = 0

    func refresh() {
        self.activeSession = focusEngine.activeSession
        self.currentAppBundleID = focusEngine.currentApp
        self.breakState = focusEngine.breakState
        self.breakDeadline = focusEngine.activeBreakCommitment?.deadline
        self.currentClassification = focusEngine.currentClassification
        self.updateTime()
    }

    func updateTime() {
        if focusEngine.activeSession != self.activeSession {
            self.activeSession = focusEngine.activeSession
        }
        self.currentAppBundleID = focusEngine.currentApp

        if activeSession == nil {
            refreshSessionSnapshot { [weak self] rawStats in
                self?.applyStats(rawStats)
            }
            return
        }

        refreshSessionSnapshot { [weak self] rawStats in
            self?.applyStatsWithActiveSession(rawStats)
        }
    }

    private func refreshSessionSnapshot(applyStats: @escaping (SessionStats) -> Void) {
        let currentGen = statsGeneration &+ 1
        statsGeneration = currentGen
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let sessions = self.sessionStore.recentSessions(limit: 5)
            let rawStats = self.sessionStore.getStats()
            DispatchQueue.main.async {
                guard currentGen == self.statsGeneration else { return }
                self.recentSessions = sessions
                applyStats(rawStats)
            }
        }
    }

    private func applyStats(_ rawStats: SessionStats) {
        guard activeSession == nil else {
            applyStatsWithActiveSession(rawStats)
            return
        }
        self.stats = rawStats
        remainingTimeFormatted = "00:00"
        progress = 0.0
    }

    func beginTreatCurrentAppAsProductive() {
        guard let bundleID = currentAppBundleID else { return }
        let reviewSnapshot = ContextSnapshot(
            bundleIdentifier: bundleID,
            localizedName: focusEngine.currentContext?.localizedName ?? focusEngine.suggestedSessionProfile().name,
            url: focusEngine.currentURL,
            title: focusEngine.currentContext?.title ?? focusEngine.currentTitle,
            source: BrowserStrategyFactory.isSupportedBrowser(bundleID)
                ? (bundleID == "com.apple.Safari" ? .safari : .chromium)
                : .application,
            observedAt: Date()
        )

        let draft = ProductiveCorrectionDraft(
            snapshot: reviewSnapshot,
            bundleID: bundleID,
            url: reviewSnapshot.url,
            title: reviewSnapshot.title,
            message: "Checking the current item with OCR...",
            recommendedScope: ContextualSiteHeuristic.reviewScope(
                for: bundleID,
                url: reviewSnapshot.url,
                title: reviewSnapshot.title
            ),
            canUseWebsiteScope: BrowserStrategyFactory.isSupportedBrowser(bundleID) && reviewSnapshot.url?.host?.isEmpty == false,
            isChecking: true
        )
        productiveCorrectionState = .active(draft)

        focusEngine.reviewCurrentAppAsProductive { [weak self] review in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .active(var currentDraft) = self.productiveCorrectionState,
                      currentDraft.bundleID == bundleID,
                      currentDraft.url == draft.url,
                      currentDraft.title == draft.title else {
                    return
                }
                currentDraft.message = review.message
                currentDraft.recommendedScope = review.recommendedScope
                currentDraft.canUseWebsiteScope = review.canUseWebsiteScope
                currentDraft.isChecking = false
                self.productiveCorrectionState = .active(currentDraft)
            }
        }
    }

    func applyTreatAsProductive(scope: ProductiveCorrectionScope) {
        guard case let .active(draft) = productiveCorrectionState else { return }

        switch scope {
        case .app:
            focusEngine.applyCorrection(.allowApp, bundleID: draft.bundleID, url: draft.url, title: draft.title)
        case .website:
            focusEngine.applyCorrection(.allowDomain, bundleID: draft.bundleID, url: draft.url, title: draft.title)
        case .page:
            focusEngine.applyPageScopedProductive(snapshot: draft.snapshot)
        }
        productiveCorrectionState = .idle
        refresh()
    }

    var productiveReviewActionTitle: String {
        guard (currentAppBundleID ?? focusEngine.currentContext?.bundleIdentifier) != nil else {
            return "Review Current Item"
        }

        return ContextualSiteHeuristic.reviewActionTitle()
    }

    func cancelTreatAsProductive() {
        productiveCorrectionState = .idle
    }

    var currentDomainRuleSuggestion: String? {
        guard let snapshot = currentReviewSnapshot,
              focusEngine.shouldSuggestPermanentRule(for: snapshot) else {
            return nil
        }

        return ContextualSiteHeuristic.normalizedDomain(for: snapshot.url)
    }

    func applyDomainRuleSuggestion() {
        guard currentDomainRuleSuggestion != nil,
              let bundleID = currentAppBundleID ?? focusEngine.currentContext?.bundleIdentifier else { return }
        focusEngine.applyCorrection(
            .allowDomain,
            bundleID: bundleID,
            url: focusEngine.currentURL,
            title: focusEngine.currentContext?.title ?? focusEngine.currentTitle
        )
        refresh()
    }

    private var currentReviewSnapshot: ContextSnapshot? {
        guard let bundleID = currentAppBundleID ?? focusEngine.currentContext?.bundleIdentifier else {
            return nil
        }

        let localizedName = focusEngine.currentContext?.localizedName ?? ProfileManager.shared.activeProfile.name
        return ContextSnapshot(
            bundleIdentifier: bundleID,
            localizedName: localizedName,
            url: focusEngine.currentURL,
            title: focusEngine.currentContext?.title ?? focusEngine.currentTitle,
            source: BrowserStrategyFactory.isSupportedBrowser(bundleID)
                ? (bundleID == "com.apple.Safari" ? .safari : .chromium)
                : .application,
            observedAt: Date()
        )
    }

    private func applyStatsWithActiveSession(_ rawStats: SessionStats) {
        guard let session = activeSession else {
            self.stats = rawStats
            remainingTimeFormatted = "00:00"
            progress = 0.0
            return
        }
        let elapsed = focusEngine.currentSessionFocusedTime()
        let total = session.anchoredDuration
        let remaining = max(0, total - elapsed)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        remainingTimeFormatted = String(format: "%02d:%02d", minutes, seconds)
        progress = total > 0 ? Double(elapsed) / Double(total) : 1.0
        self.stats = SessionStats(
            focusedTimeToday: rawStats.focusedTimeToday + elapsed,
            sessionCountToday: rawStats.sessionCountToday + 1,
            streakDays: rawStats.streakDays
        )
    }
    
    func endSession() {
        focusEngine.endSession(action: .dismissed, completionOutcome: .done)
        refresh()
    }

    func endSession(summary: String?) {
        focusEngine.endSession(action: .dismissed, completionOutcome: .done, summary: summary)
        refresh()
    }

    var breakRemainingTimeFormatted: String {
        guard let deadline = breakDeadline else { return "00:00" }
        let remaining = max(0, deadline.timeIntervalSinceNow)
        return String(format: "%02d:%02d", Int(remaining) / 60, Int(remaining) % 60)
    }

    @discardableResult
    func requestBreak(intention: String) -> BreakRequestDecision {
        let result = focusEngine.requestBreak(intention: intention)
        refresh()
        return result
    }

    func resumeAfterBreakReview() {
        focusEngine.resumeAfterBreakReview()
        refresh()
    }

    func updateSummary(id: UUID, summary: String?, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? self?.sessionStore.updateSessionSummary(id: id, summary: summary)
            DispatchQueue.main.async {
                self?.refresh()
                completion?()
            }
        }
    }

    func clearAllSummaries(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? self?.sessionStore.clearAllSessionSummaries()
            DispatchQueue.main.async {
                self?.refresh()
                completion?()
            }
        }
    }
}

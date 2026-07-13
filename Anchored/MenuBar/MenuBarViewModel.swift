import SwiftUI
import Combine

class MenuBarViewModel: ObservableObject {
    let focusEngine: FocusEngine
    private let sessionStore: SessionStore
    private var timer: AnyCancellable?
    
    @Published var activeSession: ActiveSession?
    @Published var remainingTimeFormatted: String = ""
    @Published var progress: Double = 0.0
    @Published var stats: SessionStats = SessionStats(focusedTimeToday: 0, sessionCountToday: 0, streakDays: 0)
    @Published var recentSessions: [SessionEvent] = []
    @Published var currentClassification: ClassificationDecision = .neutral()
    
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
        self.currentClassification = focusEngine.currentClassification
        let currentGen = statsGeneration &+ 1
        statsGeneration = currentGen
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let sessions = self.sessionStore.recentSessions(limit: 5)
            let rawStats = self.sessionStore.getStats()
            DispatchQueue.main.async {
                guard currentGen == self.statsGeneration else { return }
                self.recentSessions = sessions
                self.applyStats(rawStats)
            }
        }
        self.updateTime()
    }
    
    func updateTime() {
        if focusEngine.activeSession != self.activeSession {
            self.activeSession = focusEngine.activeSession
            let currentGen = statsGeneration &+ 1
            statsGeneration = currentGen
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let sessions = self.sessionStore.recentSessions(limit: 5)
                let rawStats = self.sessionStore.getStats()
                DispatchQueue.main.async {
                    guard currentGen == self.statsGeneration else { return }
                    self.recentSessions = sessions
                    self.applyStatsWithActiveSession(rawStats)
                }
            }
            return
        }

        let currentGen = statsGeneration &+ 1
        statsGeneration = currentGen
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let rawStats = self.sessionStore.getStats()
            DispatchQueue.main.async {
                guard currentGen == self.statsGeneration else { return }
                self.applyStatsWithActiveSession(rawStats)
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
        focusEngine.endSession()
        refresh()
    }
}

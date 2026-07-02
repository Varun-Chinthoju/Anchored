import SwiftUI
import Combine

class MenuBarViewModel: ObservableObject {
    private let focusEngine: FocusEngine
    private let sessionStore: SessionStore
    private var timer: AnyCancellable?
    
    @Published var activeSession: ActiveSession?
    @Published var remainingTimeFormatted: String = ""
    @Published var progress: Double = 0.0
    @Published var stats: SessionStats = SessionStats(focusedTimeToday: 0, sessionCountToday: 0, streakDays: 0)
    @Published var recentSessions: [SessionEvent] = []
    
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
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleStateChange() {
        DispatchQueue.main.async {
            self.refresh()
        }
    }
    
    func refresh() {
        self.activeSession = focusEngine.activeSession
        self.stats = sessionStore.getStats()
        self.recentSessions = sessionStore.recentSessions(limit: 5)
        self.updateTime()
    }
    
    func updateTime() {
        // In case the session state changed externally in the engine, keep in sync
        if focusEngine.activeSession != self.activeSession {
            self.activeSession = focusEngine.activeSession
            self.stats = sessionStore.getStats()
            self.recentSessions = sessionStore.recentSessions(limit: 5)
        }
        
        guard let session = activeSession else {
            remainingTimeFormatted = "00:00"
            progress = 0.0
            return
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(session.startDate)
        let total = session.anchoredDuration
        let remaining = max(0, total - elapsed)
        
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        remainingTimeFormatted = String(format: "%02d:%02d", minutes, seconds)
        
        progress = total > 0 ? Double(elapsed) / Double(total) : 1.0
    }
    
    func endSession() {
        focusEngine.endSession()
        refresh()
    }
}

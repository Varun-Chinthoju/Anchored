import Foundation

class SessionStore {
    static let shared = SessionStore()
    
    private let queue = DispatchQueue(label: "com.varun.Anchored.SessionStore", qos: .utility)
    private var fileURL: URL
    private let sqliteStore: SQLiteSessionStore
    
    // Internal initializer for testing with custom path
    init(fileURL: URL? = nil) {
        let fileManager = FileManager.default
        if let customURL = fileURL {
            self.fileURL = customURL
            let sqliteURL = customURL.deletingPathExtension().appendingPathExtension("db")
            self.sqliteStore = SQLiteSessionStore(databaseURL: sqliteURL)
        } else {
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectoryURL = appSupportURL.appendingPathComponent("Anchored")
            self.fileURL = appDirectoryURL.appendingPathComponent("sessions.json")
            self.sqliteStore = SQLiteSessionStore.shared
        }
        
        // Trigger migration from JSON to SQLite
        self.sqliteStore.migrateFromJSONIfNeeded(jsonURL: self.fileURL)
    }
    
    func log(_ event: SessionEvent, completion: StorageWriteCompletion? = nil) {
        sqliteStore.log(event, completion: completion)
    }
    
    private func warnIfMainThread(caller: String = #function) {
        if Thread.isMainThread {
            print("⚠️ [MainThreadSQLite] SessionStore.\(caller) called on main thread - use async variant")
        }
    }

    func recentSessions(limit: Int) -> [SessionEvent] {
        warnIfMainThread()
        return sqliteStore.recentSessions(limit: limit)
    }

    func fetchRecentSessions(limit: Int, completion: @escaping ([SessionEvent]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [sqliteStore] in
            let sessions = sqliteStore.recentSessions(limit: limit)
            DispatchQueue.main.async { completion(sessions) }
        }
    }
    
    func getStats() -> SessionStats {
        warnIfMainThread()
        return queue.sync {
            let events = loadEventsSync()
            return Self.computeStats(from: events)
        }
    }

    func fetchStats(completion: @escaping (SessionStats) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [sqliteStore] in
            let events = sqliteStore.allEvents()
            let stats = Self.computeStats(from: events)
            DispatchQueue.main.async { completion(stats) }
        }
    }
    
    func getAppBreakdown() -> [String: TimeInterval] {
        warnIfMainThread()
        return queue.sync {
            let events = self.loadEventsSync()
            return Self.computeBreakdown(from: events)
        }
    }

    func fetchAppBreakdown(completion: @escaping ([String: TimeInterval]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [sqliteStore] in
            let events = sqliteStore.allEvents()
            let breakdown = Self.computeBreakdown(from: events)
            DispatchQueue.main.async { completion(breakdown) }
        }
    }
    
    func allEvents() -> [SessionEvent] {
        warnIfMainThread()
        return sqliteStore.allEvents()
    }

    var recordedEvents: [SessionEvent] {
        queue.sync {
            sqliteStore.recordedEvents()
        }
    }

    func fetchAllEvents(completion: @escaping ([SessionEvent]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [sqliteStore] in
            let events = sqliteStore.allEvents()
            DispatchQueue.main.async { completion(events) }
        }
    }

    func updateSessionSummary(id: UUID, summary: String?) throws {
        try sqliteStore.updateSessionSummary(id: id, summary: summary)
    }

    func clearAllSessionSummaries() throws {
        try sqliteStore.clearAllSessionSummaries()
    }
    
    // Helper to load events synchronously on the current queue
    private func loadEventsSync() -> [SessionEvent] {
        return sqliteStore.recordedEvents()
    }

    private static func computeStats(from events: [SessionEvent]) -> SessionStats {
        let sessionEndEvents = events.filter { $0.type == .sessionEnd }
        let calendar = Calendar.current
        let now = Date()
        let todayEvents = sessionEndEvents.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let focusedTimeToday = todayEvents.reduce(0.0) { $0 + TimeInterval($1.sessionDurationSeconds ?? 0) }
        let sessionCountToday = todayEvents.count
        let startOfDays = sessionEndEvents.map { calendar.startOfDay(for: $0.timestamp) }
        let sortedDates = Array(Set(startOfDays)).sorted(by: >)
        var streak = 0
        if let mostRecent = sortedDates.first {
            let todayStart = calendar.startOfDay(for: now)
            let daysDifference = calendar.dateComponents([.day], from: mostRecent, to: todayStart).day ?? 0
            if daysDifference <= 1 {
                streak = 1
                var previousDate = mostRecent
                for date in sortedDates.dropFirst() {
                    let diff = calendar.dateComponents([.day], from: date, to: previousDate).day ?? 0
                    if diff == 1 {
                        streak += 1
                        previousDate = date
                    } else if diff > 1 {
                        break
                    }
                }
            }
        }
        return SessionStats(
            focusedTimeToday: focusedTimeToday,
            sessionCountToday: sessionCountToday,
            streakDays: streak
        )
    }

    private static func computeBreakdown(from events: [SessionEvent]) -> [String: TimeInterval] {
        let sessionEndEvents = events.filter { $0.type == .sessionEnd }
        var breakdown: [String: TimeInterval] = [:]
        for event in sessionEndEvents {
            let app = event.appName.isEmpty ? "Unknown" : event.appName
            let duration = TimeInterval(event.sessionDurationSeconds ?? 0)
            breakdown[app, default: 0.0] += duration
        }
        return breakdown
    }
}

struct SessionStats: Codable {
    let focusedTimeToday: TimeInterval
    let sessionCountToday: Int
    let streakDays: Int
}

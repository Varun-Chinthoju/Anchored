import Foundation

class SessionStore {
    static let shared = SessionStore()
    
    private let queue = DispatchQueue(label: "com.varun.Anchored.SessionStore", qos: .utility)
    private var fileURL: URL
    
    // Internal initializer for testing with custom path
    init(fileURL: URL? = nil) {
        if let customURL = fileURL {
            self.fileURL = customURL
        } else {
            let fileManager = FileManager.default
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectoryURL = appSupportURL.appendingPathComponent("Anchored")
            self.fileURL = appDirectoryURL.appendingPathComponent("sessions.json")
        }
    }
    
    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    func log(_ event: SessionEvent) {
        queue.async {
            do {
                try self.ensureDirectoryExists()
                
                var events = self.loadEventsSync()
                events.append(event)
                
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                
                let data = try encoder.encode(events)
                try data.write(to: self.fileURL, options: .atomic)
            } catch {
                print("SessionStore Error: Failed to log event. \(error.localizedDescription)")
            }
        }
    }
    
    func recentSessions(limit: Int) -> [SessionEvent] {
        return queue.sync {
            let events = loadEventsSync()
            let sessionEndEvents = events.filter { $0.type == .sessionEnd }
            return Array(sessionEndEvents.suffix(limit)).reversed()
        }
    }
    
    func getStats() -> SessionStats {
        return queue.sync {
            let events = loadEventsSync()
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
    }
    
    func getAppBreakdown() -> [String: TimeInterval] {
        return queue.sync {
            let events = self.loadEventsSync()
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
    
    // Helper to load events synchronously on the current queue
    private func loadEventsSync() -> [SessionEvent] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SessionEvent].self, from: data)
        } catch {
            print("SessionStore Error: Failed to load events. \(error.localizedDescription)")
            return []
        }
    }
}

struct SessionStats: Codable {
    let focusedTimeToday: TimeInterval
    let sessionCountToday: Int
    let streakDays: Int
}

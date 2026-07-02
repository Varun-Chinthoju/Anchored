import Foundation
import GRDB
import AppKit

struct TimelineBlock: Codable, Equatable {
    enum BlockType: String, Codable {
        case focus
        case distraction
    }
    
    let type: BlockType
    let startDate: Date
    let endDate: Date
    let appName: String
    let distractionAppBundleID: String?
    let distractionDomain: String?
    
    init(
        type: BlockType,
        startDate: Date,
        endDate: Date,
        appName: String,
        distractionAppBundleID: String? = nil,
        distractionDomain: String? = nil
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.appName = appName
        self.distractionAppBundleID = distractionAppBundleID
        self.distractionDomain = distractionDomain
    }
}

struct DistractionRank: Codable, Equatable {
    let name: String
    let bundleID: String?
    let domain: String?
    let count: Int
    let totalDurationSeconds: Int
    
    init(name: String, bundleID: String?, domain: String?, count: Int, totalDurationSeconds: Int) {
        self.name = name
        self.bundleID = bundleID
        self.domain = domain
        self.count = count
        self.totalDurationSeconds = totalDurationSeconds
    }
}

extension SQLiteSessionStore {
    
    func todayTotalFocusTime(for referenceDate: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        return queue.sync {
            do {
                return try dbQueue.read { db in
                    let startOfToday = calendar.startOfDay(for: referenceDate)
                    let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
                    
                    let val = try Int.fetchOne(db, sql: """
                        SELECT SUM(sessionDurationSeconds) FROM sessions
                        WHERE type = ? AND timestamp >= ? AND timestamp < ?
                        """, arguments: [SessionEventType.sessionEnd.rawValue, startOfToday, endOfToday])
                    return TimeInterval(val ?? 0)
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to fetch today's total focus time: \(error.localizedDescription)")
                return 0
            }
        }
    }
    
    func timelineBlocks(for date: Date = Date(), calendar: Calendar = .current) -> [TimelineBlock] {
        return queue.sync {
            do {
                return try dbQueue.read { db in
                    let startOfToday = calendar.startOfDay(for: date)
                    let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
                    
                    // Fetch all events for today
                    let allEvents = try SessionEvent
                        .filter(Column("timestamp") >= startOfToday)
                        .filter(Column("timestamp") < endOfToday)
                        .order(Column("timestamp").asc, Column("rowid").asc)
                        .fetchAll(db)
                    
                    return reconstructTimeline(from: allEvents)
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to reconstruct timeline: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    func topDistractions(since startDate: Date, to endDate: Date = Date()) -> [DistractionRank] {
        return queue.sync {
            do {
                return try dbQueue.read { db in
                    // Fetch all events between startDate and endDate
                    let allEvents = try SessionEvent
                        .filter(Column("timestamp") >= startDate)
                        .filter(Column("timestamp") <= endDate)
                        .order(Column("timestamp").asc, Column("rowid").asc)
                        .fetchAll(db)
                    
                    let blocks = reconstructTimeline(from: allEvents)
                    let distractionBlocks = blocks.filter { $0.type == .distraction }
                    
                    var groupings: [String: (bundleID: String?, domain: String?, name: String, count: Int, totalDuration: TimeInterval)] = [:]
                    
                    for block in distractionBlocks {
                        let key: String
                        let name: String
                        let bundleID: String?
                        let domain: String?
                        
                        if let dom = block.distractionDomain, !dom.isEmpty {
                            key = "domain:\(dom)"
                            name = dom
                            bundleID = block.distractionAppBundleID
                            domain = dom
                        } else if let bID = block.distractionAppBundleID, !bID.isEmpty {
                            key = "app:\(bID)"
                            name = self.appName(for: bID)
                            bundleID = bID
                            domain = nil
                        } else {
                            continue
                        }
                        
                        let duration = block.endDate.timeIntervalSince(block.startDate)
                        if let existing = groupings[key] {
                            groupings[key] = (
                                bundleID: bundleID,
                                domain: domain,
                                name: name,
                                count: existing.count + 1,
                                totalDuration: existing.totalDuration + duration
                            )
                        } else {
                            groupings[key] = (
                                bundleID: bundleID,
                                domain: domain,
                                name: name,
                                count: 1,
                                totalDuration: duration
                            )
                        }
                    }
                    
                    return groupings.values.map { item in
                        DistractionRank(
                            name: item.name,
                            bundleID: item.bundleID,
                            domain: item.domain,
                            count: item.count,
                            totalDurationSeconds: Int(item.totalDuration)
                        )
                    }.sorted { $0.totalDurationSeconds > $1.totalDurationSeconds }
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to compute top distractions: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    func weeklyStreak(for referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        return queue.sync {
            do {
                return try dbQueue.read { db in
                    // Fetch all sessionEnd timestamps
                    let rows = try Row.fetchAll(db, sql: """
                        SELECT timestamp FROM sessions
                        WHERE type = ?
                        ORDER BY timestamp DESC
                        """, arguments: [SessionEventType.sessionEnd.rawValue])
                    
                    let timestamps: [Date] = rows.compactMap { row in
                        row["timestamp"]
                    }
                    
                    let startOfDays = timestamps.map { calendar.startOfDay(for: $0) }
                    let sortedDates = Array(Set(startOfDays)).sorted(by: >)
                    
                    var streak = 0
                    if let mostRecent = sortedDates.first {
                        let todayStart = calendar.startOfDay(for: referenceDate)
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
                    return streak
                }
            } catch {
                print("SQLiteSessionStore Error: Failed to calculate streak: \(error.localizedDescription)")
                return 0
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func reconstructTimeline(from events: [SessionEvent]) -> [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        var i = 0
        while i < events.count {
            let startEvent = events[i]
            if startEvent.type == .sessionStart {
                var endEvent: SessionEvent? = nil
                var j = i + 1
                var sessionEvents: [SessionEvent] = []
                while j < events.count {
                    let nextEvent = events[j]
                    if nextEvent.type == .sessionEnd {
                        endEvent = nextEvent
                        break
                    } else {
                        sessionEvents.append(nextEvent)
                        j += 1
                    }
                }
                
                let endDate = endEvent?.timestamp ?? (j < events.count ? events[j].timestamp : Date())
                
                var currentBlockStart = startEvent.timestamp
                var currentBlockType = TimelineBlock.BlockType.focus
                var currentDistractionApp: String? = nil
                var currentDistractionDomain: String? = nil
                
                for ev in sessionEvents {
                    if ev.type == .distractionDetected {
                        if currentBlockType == .focus {
                            if ev.timestamp > currentBlockStart {
                                blocks.append(TimelineBlock(
                                    type: .focus,
                                    startDate: currentBlockStart,
                                    endDate: ev.timestamp,
                                    appName: startEvent.appName
                                ))
                            }
                        } else if currentBlockType == .distraction {
                            if ev.timestamp > currentBlockStart {
                                blocks.append(TimelineBlock(
                                    type: .distraction,
                                    startDate: currentBlockStart,
                                    endDate: ev.timestamp,
                                    appName: startEvent.appName,
                                    distractionAppBundleID: currentDistractionApp,
                                    distractionDomain: currentDistractionDomain
                                ))
                            }
                        }
                        currentBlockStart = ev.timestamp
                        currentBlockType = .distraction
                        currentDistractionApp = ev.distractionAppBundleID
                        currentDistractionDomain = ev.distraction_domain
                    }
                }
                
                if endDate > currentBlockStart {
                    if currentBlockType == .focus {
                        blocks.append(TimelineBlock(
                            type: .focus,
                            startDate: currentBlockStart,
                            endDate: endDate,
                            appName: startEvent.appName
                        ))
                    } else {
                        blocks.append(TimelineBlock(
                            type: .distraction,
                            startDate: currentBlockStart,
                            endDate: endDate,
                            appName: startEvent.appName,
                            distractionAppBundleID: currentDistractionApp,
                            distractionDomain: currentDistractionDomain
                        ))
                    }
                }
                
                i = j + 1
            } else {
                i += 1
            }
        }
        return blocks
    }
    
    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        if let lastComponent = bundleID.split(separator: ".").last {
            return String(lastComponent).capitalized
        }
        return bundleID
    }
}

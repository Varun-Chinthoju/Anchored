import SwiftUI

struct DashboardView: View {
    @State private var todayFocusTime: TimeInterval = 0
    @State private var streak: Int = 0
    @State private var timelineBlocks: [TimelineBlock] = []
    @State private var topDistractions: [DistractionRank] = []
    @State private var weeklyHistory: [(date: Date, focusTime: TimeInterval)] = []
    
    @State private var hoveredBlock: TimelineBlock? = nil
    
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    // Pirate Theme colors
    private let goldColor = Color(red: 0.9, green: 0.75, blue: 0.3)
    private let parchmentWhite = Color(red: 0.95, green: 0.95, blue: 0.9)
    private let deepOceanDark = Color(red: 0.08, green: 0.06, blue: 0.05)
    private let secondaryDeepOcean = Color(red: 0.04, green: 0.03, blue: 0.02)
    
    var body: some View {
        VStack(spacing: 16) {
            // Header stats
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Captain's Log & Focus Loot")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(goldColor)
                    
                    Text("Plunder metrics and distraction sea monster analysis")
                        .font(.system(size: 12))
                        .foregroundColor(parchmentWhite.opacity(0.6))
                }
                
                Spacer()
                
                // Today's total focus time
                HStack(spacing: 12) {
                    DashboardStatCard(
                        title: "Sand in Hourglass",
                        value: formatDuration(todayFocusTime),
                        icon: "hourglass",
                        color: goldColor
                    )
                    
                    DashboardStatCard(
                        title: "Voyage Streak",
                        value: "\(streak) sun\(streak == 1 ? "" : "s")",
                        icon: "flame.fill",
                        color: .orange
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            // Timeline View (Task 15)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today's Sea Route")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(goldColor)
                    Spacer()
                    if let hovered = hoveredBlock {
                        Text(formatHoveredBlock(hovered))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(parchmentWhite.opacity(0.8))
                            .transition(.opacity)
                    } else {
                        Text("Scan the horizon (hover over segments) for details")
                            .font(.system(size: 11))
                            .foregroundColor(parchmentWhite.opacity(0.5))
                    }
                }
                .padding(.horizontal)
                
                TimelineView(blocks: timelineBlocks, hoveredBlock: $hoveredBlock)
                    .frame(height: 48)
                    .padding(.horizontal)
            }
            
            // Bottom charts (Task 16)
            HStack(spacing: 16) {
                // Left: Weekly History Chart
                VStack(alignment: .leading, spacing: 10) {
                    Text("Past Fortnight's Log")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(goldColor)
                    
                    WeeklyHistoryView(history: weeklyHistory)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(goldColor.opacity(0.15), lineWidth: 1)
                )
                
                // Right: Top Distractions List
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sirens & Sea Monsters")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(goldColor)
                    
                    TopDistractionsView(distractions: topDistractions)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(goldColor.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 600, height: 480)
        .background(
            LinearGradient(
                colors: [deepOceanDark, secondaryDeepOcean],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear(perform: loadData)
        .onReceive(timer) { _ in
            loadData()
        }
    }
    
    private func loadData() {
        let store = SQLiteSessionStore.shared
        let calendar = Calendar.current
        let now = Date()
        
        // 1. Stats
        todayFocusTime = store.todayTotalFocusTime(for: now, calendar: calendar)
        streak = store.weeklyStreak(for: now, calendar: calendar)
        
        // 2. Timeline Blocks
        timelineBlocks = store.timelineBlocks(for: now, calendar: calendar)
        
        // 3. Top Distractions (last 7 days)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        topDistractions = store.topDistractions(since: sevenDaysAgo, to: now)
        
        // 4. Weekly History
        var historyData: [(date: Date, focusTime: TimeInterval)] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let focusVal = store.todayTotalFocusTime(for: date, calendar: calendar)
                historyData.append((date: date, focusTime: focusVal))
            }
        }
        weeklyHistory = historyData.reversed()
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatHoveredBlock(_ block: TimelineBlock) -> String {
        let duration = block.endDate.timeIntervalSince(block.startDate)
        let durationStr = formatBlockDuration(duration)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startStr = formatter.string(from: block.startDate)
        let endStr = formatter.string(from: block.endDate)
        
        if block.type == .focus {
            return "Sailing smoothly on \(block.appName) | \(durationStr) (\(startStr)-\(endStr))"
        } else {
            let label = block.distractionDomain ?? block.appName
            return "Boarded by Siren \(label) | \(durationStr) (\(startStr)-\(endStr))"
        }
    }
    
    private func formatBlockDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(red: 0.95, green: 0.95, blue: 0.9).opacity(0.6))
                
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.95, green: 0.95, blue: 0.9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.25))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.9, green: 0.75, blue: 0.3).opacity(0.15), lineWidth: 1)
        )
    }
}

import SwiftUI

struct DashboardView: View {
    @State private var todayFocusTime: TimeInterval = 0
    @State private var streak: Int = 0
    @State private var timelineBlocks: [TimelineBlock] = []
    @State private var topDistractions: [DistractionRank] = []
    @State private var weeklyHistory: [(date: Date, focusTime: TimeInterval)] = []
    
    @State private var hoveredBlock: TimelineBlock? = nil
    
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 16) {
            // Header stats
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus Dashboard")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Session insights and distraction analysis")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Today's total focus time
                HStack(spacing: 12) {
                    DashboardStatCard(
                        title: "Today's Focus",
                        value: formatDuration(todayFocusTime),
                        icon: "timer",
                        color: .green
                    )
                    
                    DashboardStatCard(
                        title: "Current Streak",
                        value: "\(streak) day\(streak == 1 ? "" : "s")",
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
                    Text("Today's Timeline")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    if let hovered = hoveredBlock {
                        Text(formatHoveredBlock(hovered))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    } else {
                        Text("Hover over blocks for details")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
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
                    Text("Weekly History")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    WeeklyHistoryView(history: weeklyHistory)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                
                // Right: Top Distractions List
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Distractions")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    TopDistractionsView(distractions: topDistractions)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 600, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
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
            return "Focusing on \(block.appName) | \(durationStr) (\(startStr)-\(endStr))"
        } else {
            let label = block.distractionDomain ?? block.appName
            return "Distracted by \(label) | \(durationStr) (\(startStr)-\(endStr))"
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
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

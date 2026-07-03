import SwiftUI

struct ConstellationHeatmapView: View {
    @State private var dailyFocus: [Date: TimeInterval] = [:]
    @State private var weeks: [[Date]] = []
    
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Constellation Heatmap (Voyage Density)")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(PirateTheme.gold)
                .padding(.horizontal, 4)
            
            HStack(spacing: 8) {
                VStack(spacing: 5) {
                    ForEach(0..<7) { i in
                        Text(weekdays[i])
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(height: 12)
                    }
                }
                .padding(.top, 14)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Month markers
                    HStack(spacing: 0) {
                        ForEach(0..<weeks.count, id: \.self) { i in
                            let date = weeks[i].first ?? Date()
                            let day = Calendar.current.component(.day, from: date)
                            if day <= 7 {
                                Text(formatMonth(date))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16 * 4, alignment: .leading)
                            } else {
                                Spacer()
                                    .frame(width: 0)
                            }
                        }
                    }
                    .frame(height: 10)
                    
                    HStack(spacing: 4) {
                        ForEach(0..<weeks.count, id: \.self) { wIndex in
                            VStack(spacing: 4) {
                                ForEach(0..<7) { dIndex in
                                    let date = weeks[wIndex][dIndex]
                                    let duration = dailyFocus[Calendar.current.startOfDay(for: date)] ?? 0
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(cellColor(for: duration))
                                        .frame(width: 12, height: 12)
                                        .help("\(formatTooltipDate(date)): \(formatTooltipDuration(duration))")
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(PirateTheme.darkWood.opacity(0.4))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PirateTheme.gold.opacity(0.15), lineWidth: 1)
            )
        }
        .onAppear {
            refreshData()
        }
    }
    
    private func refreshData() {
        let calendar = Calendar.current
        let now = Date()
        
        let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let twentyWeeksAgoStart = calendar.date(byAdding: .weekOfYear, value: -19, to: currentWeekStart)!
        
        var weekList: [[Date]] = []
        for weekOffset in 0..<20 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: twentyWeeksAgoStart)!
            var dayList: [Date] = []
            for dayOffset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                dayList.append(day)
            }
            weekList.append(dayList)
        }
        self.weeks = weekList
        
        let rawData = SQLiteSessionStore.shared.focusTimePerDay(since: twentyWeeksAgoStart, to: now)
        var focusMap: [Date: TimeInterval] = [:]
        for (date, duration) in rawData {
            focusMap[calendar.startOfDay(for: date)] = duration
        }
        self.dailyFocus = focusMap
    }
    
    private func cellColor(for duration: TimeInterval) -> Color {
        if duration == 0 {
            return Color.secondary.opacity(0.08)
        } else if duration < 15 * 60 {
            return PirateTheme.gold.opacity(0.15)
        } else if duration < 60 * 60 {
            return PirateTheme.gold.opacity(0.4)
        } else if duration < 3 * 3600 {
            return PirateTheme.gold.opacity(0.7)
        } else {
            return PirateTheme.gold
        }
    }
    
    private func formatMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: date)
    }
    
    private func formatTooltipDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: date)
    }
    
    private func formatTooltipDuration(_ duration: TimeInterval) -> String {
        if duration == 0 { return "0m focused" }
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m focused"
        } else {
            return "\(m)m focused"
        }
    }
}

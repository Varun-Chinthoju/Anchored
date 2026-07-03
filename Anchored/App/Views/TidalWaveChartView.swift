import SwiftUI

struct BezierCurve: Shape {
    let data: [Double]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard data.count > 1 else { return path }
        
        let width = rect.width
        let height = rect.height
        let maxVal = max(1.0, data.max() ?? 1.0)
        
        let stepX = width / CGFloat(data.count - 1)
        
        var points: [CGPoint] = []
        for (index, val) in data.enumerated() {
            let x = CGFloat(index) * stepX
            let y = height - (CGFloat(val / maxVal) * height)
            points.append(CGPoint(x: x, y: y))
        }
        
        path.move(to: points[0])
        
        for i in 0..<points.count - 1 {
            let p1 = points[i]
            let p2 = points[i+1]
            
            let controlPoint1 = CGPoint(x: p1.x + stepX / 2, y: p1.y)
            let controlPoint2 = CGPoint(x: p2.x - stepX / 2, y: p2.y)
            
            path.addCurve(to: p2, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
        }
        
        return path
    }
}

struct BezierArea: Shape {
    let data: [Double]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard data.count > 1 else { return path }
        
        let width = rect.width
        let height = rect.height
        let maxVal = max(1.0, data.max() ?? 1.0)
        
        let stepX = width / CGFloat(data.count - 1)
        
        var points: [CGPoint] = []
        for (index, val) in data.enumerated() {
            let x = CGFloat(index) * stepX
            let y = height - (CGFloat(val / maxVal) * height)
            points.append(CGPoint(x: x, y: y))
        }
        
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: points[0])
        
        for i in 0..<points.count - 1 {
            let p1 = points[i]
            let p2 = points[i+1]
            
            let controlPoint1 = CGPoint(x: p1.x + stepX / 2, y: p1.y)
            let controlPoint2 = CGPoint(x: p2.x - stepX / 2, y: p2.y)
            
            path.addCurve(to: p2, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.close()
        
        return path
    }
}

struct TidalWaveChartView: View {
    @State private var selectedRange: ChartRange = .week
    @State private var chartData: [(Date, TimeInterval)] = []
    
    enum ChartRange: String, CaseIterable, Identifiable {
        case day = "1 Day"
        case week = "1 Week"
        case twoWeeks = "2 Weeks"
        case month = "30 Days"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Tidal Wave Activity")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(PirateTheme.gold)
                
                Spacer()
                
                Picker("Range", selection: $selectedRange) {
                    ForEach(ChartRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            .padding(.horizontal, 4)
            
            ZStack {
                if chartData.isEmpty {
                    VStack {
                        Image(systemName: "wind")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.bottom, 4)
                        Text("No logs recorded on this leg of the voyage.")
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 140)
                } else {
                    let values = chartData.map { $0.1 }
                    let dates = chartData.map { $0.0 }
                    
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack {
                                BezierArea(data: values)
                                    .fill(
                                        LinearGradient(
                                            colors: [PirateTheme.gold.opacity(0.2), PirateTheme.deepBlue.opacity(0.01)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                
                                BezierCurve(data: values)
                                    .stroke(
                                        LinearGradient(
                                            colors: [PirateTheme.gold, PirateTheme.darkGold],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 2.5
                                    )
                                    .shadow(color: PirateTheme.gold.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                        .frame(height: 100)
                        
                        HStack {
                            if selectedRange == .day {
                                Text(formatHour(dates.first)).font(.system(size: 9)).foregroundColor(.secondary)
                                Spacer()
                                Text(formatHour(dates[dates.count / 2])).font(.system(size: 9)).foregroundColor(.secondary)
                                Spacer()
                                Text(formatHour(dates.last)).font(.system(size: 9)).foregroundColor(.secondary)
                            } else {
                                Text(formatDate(dates.first)).font(.system(size: 9)).foregroundColor(.secondary)
                                Spacer()
                                Text(formatDate(dates[dates.count / 2])).font(.system(size: 9)).foregroundColor(.secondary)
                                Spacer()
                                Text(formatDate(dates.last)).font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
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
        .onChange(of: selectedRange) { _ in
            refreshData()
        }
    }
    
    private func refreshData() {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedRange {
        case .day:
            chartData = SQLiteSessionStore.shared.focusTimePerHourForLast24Hours(relativeTo: now)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
            chartData = SQLiteSessionStore.shared.focusTimePerDay(since: start, to: now)
        case .twoWeeks:
            let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now))!
            chartData = SQLiteSessionStore.shared.focusTimePerDay(since: start, to: now)
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
            chartData = SQLiteSessionStore.shared.focusTimePerDay(since: start, to: now)
        }
    }
    
    private func formatHour(_ date: Date?) -> String {
        guard let d = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: d).lowercased()
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let d = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: d)
    }
}

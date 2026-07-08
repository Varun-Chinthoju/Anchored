import SwiftUI

struct ConstellationHeatmapView: View {
    @State private var loadState: Loadable<[DashboardTimeBucket]> = .idle
    @State private var weeks: [[Date]] = []
    @State private var requestGeneration: Int = 0

    private let querying: DashboardQuerying
    @ObservedObject private var prefs = PreferencesManager.shared
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 3
    private let columnSpacing: CGFloat = 4
    private let rowLabelWidth: CGFloat = 14

    init(querying: DashboardQuerying = SQLiteSessionStore.shared) {
        self.querying = querying
    }

    private var dailyFocus: [Date: TimeInterval] {
        guard case .loaded(let buckets) = loadState else {
            return [:]
        }

        let calendar = Calendar.current
        return Dictionary(uniqueKeysWithValues: buckets.map {
            (calendar.startOfDay(for: $0.date), $0.duration)
        })
    }

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeBorder: Color {
        prefs.selectedThemePalette.borderColor
    }

    private var themeTextSecondary: Color {
        prefs.selectedThemePalette.textSecondaryColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Constellation Heatmap (Voyage Density)")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(themeAccent)
                .padding(.horizontal, 4)

            ZStack {
                switch loadState {
                case .idle:
                    loadingStateView(title: "Reading the constellations.", subtitle: "Preparing the voyage map...")
                case .loading:
                    loadingStateView(title: "Charting the constellations...", subtitle: "Fetching voyage density...")
                case .failed(let message):
                    failureStateView(message: message)
                case .empty:
                    emptyStateView()
                case .loaded:
                    heatmapGridView()
                }
            }
            .padding(16)
            .background(themeSurface.opacity(0.78))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeBorder, lineWidth: 1)
            )
        }
        .onAppear {
            refreshData()
        }
        .accentColor(themeAccent)
        .tint(themeAccent)
    }

    private func heatmapGridView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: columnSpacing) {
                Text("")
                    .frame(width: rowLabelWidth)

                ForEach(0..<weeks.count, id: \.self) { index in
                    let date = weeks[index].first ?? Date()
                    Text(shouldShowMonthLabel(at: index) ? formatMonth(date) : " ")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(themeTextSecondary)
                        .frame(width: cellSize, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.leading, 1)

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdayLabel(for: index))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(themeTextSecondary)
                            .frame(width: rowLabelWidth, height: cellSize, alignment: .trailing)
                    }
                }
                .padding(.top, 1)

                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(0..<weeks.count, id: \.self) { wIndex in
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { dIndex in
                                let date = weeks[wIndex][dIndex]
                                let duration = dailyFocus[Calendar.current.startOfDay(for: date)] ?? 0

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cellColor(for: duration))
                                    .frame(width: cellSize, height: cellSize)
                                    .help("\(formatTooltipDate(date)): \(formatTooltipDuration(duration))")
                            }
                        }
                    }
                }
            }
        }
    }

    private func refreshData() {
        let generation = requestGeneration &+ 1
        requestGeneration = generation
        loadState = .loading
        weeks = buildWeeks()

        let calendar = Calendar.current
        let now = Date()
        let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let twentyWeeksAgoStart = calendar.date(byAdding: .weekOfYear, value: -19, to: currentWeekStart)!

        querying.fetchFocusTimePerDay(since: twentyWeeksAgoStart, to: now, calendar: calendar) { result in
            apply(result: result, generation: generation)
        }
    }

    private func apply(result: Result<[DashboardTimeBucket], DashboardQueryError>, generation: Int) {
        guard generation == requestGeneration else {
            return
        }

        switch result {
        case .success(let buckets):
            if buckets.isEmpty {
                loadState = .empty
            } else {
                loadState = .loaded(buckets)
            }
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
        }
    }

    private func buildWeeks() -> [[Date]] {
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
        return weekList
    }

    private func loadingStateView(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(themeAccent)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(themeTextSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(height: 140)
    }

    private func emptyStateView() -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundColor(themeAccent.opacity(0.8))

            VStack(spacing: 4) {
                Text("No stars charted yet.")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundColor(.primary)

                Text("Set sail to light up the constellation.")
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(themeTextSecondary)
            }
            .multilineTextAlignment(.center)

            Button("Retry") {
                refreshData()
            }
            .buttonStyle(.bordered)
            .tint(themeAccent)
        }
        .frame(height: 140)
    }

    private func failureStateView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(themeAccent.opacity(0.85))

            VStack(spacing: 4) {
                Text("The constellation chart failed to load.")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundColor(.primary)

                Text(message)
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(themeTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Retry") {
                refreshData()
            }
            .buttonStyle(.borderedProminent)
            .tint(themeAccent)
        }
        .frame(height: 140)
    }

    private func cellColor(for duration: TimeInterval) -> Color {
        if duration == 0 {
            return Color.secondary.opacity(0.08)
        } else if duration < 15 * 60 {
            return themeAccent.opacity(0.15)
        } else if duration < 60 * 60 {
            return themeAccent.opacity(0.4)
        } else if duration < 3 * 3600 {
            return themeAccent.opacity(0.7)
        } else {
            return themeAccent
        }
    }

    private func formatMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: date)
    }

    private func shouldShowMonthLabel(at weekIndex: Int) -> Bool {
        guard weekIndex == 0 else {
            let calendar = Calendar.current
            let currentMonth = calendar.component(.month, from: weeks[weekIndex].first ?? Date())
            let previousMonth = calendar.component(.month, from: weeks[weekIndex - 1].first ?? Date())
            return currentMonth != previousMonth
        }
        return true
    }

    private func weekdayLabel(for index: Int) -> String {
        weekdays[index]
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

#if DEBUG
fileprivate final class ConstellationPreviewQuerying: DashboardQuerying {
    func fetchFocusTimePerHourForLast24Hours(
        relativeTo referenceDate: Date,
        calendar: Calendar,
        completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(.success([]))
        }
    }

    func fetchFocusTimePerDay(
        since startDate: Date,
        to endDate: Date,
        calendar: Calendar,
        completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(.success(Self.previewBuckets()))
        }
    }

    func fetchAppDomainFocusDistribution(
        since startDate: Date,
        to endDate: Date,
        completion: @escaping (Result<[DashboardAppDistribution], DashboardQueryError>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(.success([]))
        }
    }

    private static func previewBuckets() -> [DashboardTimeBucket] {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let twentyWeeksAgoStart = calendar.date(byAdding: .weekOfYear, value: -19, to: currentWeekStart)!

        var buckets: [DashboardTimeBucket] = []
        for dayOffset in 0..<140 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: twentyWeeksAgoStart)!
            let phase = Double(dayOffset % 14)
            let value = (sin(phase * 0.35) + 1.0) * 2700.0
            buckets.append(DashboardTimeBucket(date: date, duration: value))
        }
        return buckets
    }
}
#endif

#if DEBUG
struct ConstellationHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        ConstellationHeatmapView(querying: ConstellationPreviewQuerying())
            .padding()
            .background(Color.black.opacity(0.9))
            .previewDisplayName("Constellation Heatmap View")
    }
}
#endif

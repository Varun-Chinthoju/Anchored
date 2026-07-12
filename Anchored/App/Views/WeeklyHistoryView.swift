import SwiftUI

struct WeeklyHistoryView: View {
    @State private var loadState: Loadable<[DashboardTimeBucket]> = .idle
    @State private var requestGeneration: Int = 0
    private let querying: DashboardQuerying
    private let range: ClosedRange<Date>?
    @ObservedObject private var prefs = PreferencesManager.shared

    init(
        range: ClosedRange<Date>? = nil,
        querying: DashboardQuerying = SQLiteSessionStore.shared
    ) {
        self.range = range
        self.querying = querying
    }

    init(
        state: Loadable<[DashboardTimeBucket]>,
        querying: DashboardQuerying = SQLiteSessionStore.shared
    ) {
        self.querying = querying
        self.range = nil
        _loadState = State(initialValue: state)
    }

    private var history: [(date: Date, focusTime: TimeInterval)] {
        guard case .loaded(let buckets) = loadState else { return [] }
        return buckets.map { (date: $0.date, focusTime: $0.duration) }
    }

    private var buckets: [DashboardTimeBucket] {
        guard case .loaded(let b) = loadState else { return [] }
        return b
    }

    private var themeAccent: Color { prefs.selectedThemePalette.accentColor }
    private var themeSurface: Color { prefs.selectedThemePalette.surfaceColor }
    private var themeSurfaceRaised: Color { prefs.selectedThemePalette.surfaceRaisedColor }
    private var themeBorder: Color { prefs.selectedThemePalette.borderColor }
    private var themeTextSecondary: Color { prefs.selectedThemePalette.textSecondaryColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Focus History")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(themeAccent)
                .padding(.horizontal, 4)

            ZStack {
                switch loadState {
                case .idle:
                    loadingStateView(title: "Reading history.", subtitle: "Preparing focus timeline...")
                case .loading:
                    loadingStateView(title: "Loading history...", subtitle: "Fetching past 7 days...")
                case .failed(let message):
                    failureStateView(message: message)
                case .empty:
                    emptyStateView()
                case .loaded:
                    chartContent
                }
            }
            .frame(height: 160)
            .padding(12)
            .background(themeSurface.opacity(0.78))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeBorder, lineWidth: 1))
        }
        .onAppear { refreshData() }
        .accentColor(themeAccent)
        .tint(themeAccent)
    }

    private var chartMaxTime: Double {
        max(60.0, history.map { $0.focusTime }.max() ?? 0.0)
    }

    @ViewBuilder
    private var chartContent: some View {
        if history.isEmpty {
            emptyStateView()
        } else {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(0..<history.count, id: \.self) { index in
                    let item = history[index]
                    VStack(spacing: 8) {
                        let heightPercent = CGFloat(item.focusTime / chartMaxTime)
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [themeAccent.opacity(0.85), themeSurfaceRaised.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                                    .frame(height: max(4.0, heightPercent * geometry.size.height))
                                    .overlay(
                                        VStack {
                                            if item.focusTime > 0 {
                                                Text(formatShortDuration(item.focusTime))
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(themeTextSecondary)
                                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                                    .background(themeSurface.opacity(0.85)).cornerRadius(3).offset(y: -14)
                                            }
                                        }, alignment: .top
                                    )
                            }
                        }
                        Text(dayOfWeek(item.date)).font(.system(size: 10, weight: .medium)).foregroundColor(themeTextSecondary)
                    }
                }
            }
            .frame(height: 160)
            .padding(.vertical, 8)
        }
    }

    private func refreshData() {
        let generation = requestGeneration &+ 1
        requestGeneration = generation
        loadState = .loading

        let calendar = Calendar.current
        let now = Date()
        let start: Date
        let end: Date
        if let range = range {
            start = range.lowerBound
            end = range.upperBound
        } else {
            end = now
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        }

        querying.fetchFocusTimePerDay(since: start, to: end, calendar: calendar) { result in
            apply(result: result, generation: generation)
        }
    }

    private func apply(result: Result<[DashboardTimeBucket], DashboardQueryError>, generation: Int) {
        guard generation == requestGeneration else { return }
        switch result {
        case .success(let buckets):
            loadState = buckets.isEmpty ? .empty : .loaded(buckets)
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
        }
    }

    private func loadingStateView(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().progressViewStyle(.circular).tint(themeAccent)
            VStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .bold, design: .serif)).foregroundColor(.primary)
                Text(subtitle).font(.system(size: 10, design: .serif)).foregroundColor(themeTextSecondary)
            }.multilineTextAlignment(.center)
        }
    }

    private func emptyStateView() -> some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar").font(.system(size: 24)).foregroundColor(themeAccent.opacity(0.8))
            VStack(spacing: 4) {
                Text("No data available").font(.system(size: 12, weight: .bold, design: .serif)).foregroundColor(.primary)
                Text("Complete sessions to populate weekly history.").font(.system(size: 10, design: .serif)).foregroundColor(themeTextSecondary)
            }.multilineTextAlignment(.center)
            Button("Retry") { refreshData() }.buttonStyle(.bordered).tint(themeAccent)
        }
    }

    private func failureStateView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 24)).foregroundColor(themeAccent.opacity(0.85))
            VStack(spacing: 4) {
                Text("History failed to load.").font(.system(size: 12, weight: .bold, design: .serif)).foregroundColor(.primary)
                Text(message).font(.system(size: 10, design: .serif)).foregroundColor(themeTextSecondary).multilineTextAlignment(.center)
            }
            Button("Retry") { refreshData() }.buttonStyle(.borderedProminent).tint(themeAccent)
        }
    }

    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1))
    }

    private func formatShortDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

#if DEBUG
fileprivate final class WeeklyHistoryPreviewQuerying: DashboardQuerying {
    func fetchFocusTimePerHourForLast24Hours(relativeTo referenceDate: Date, calendar: Calendar, completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
    func fetchFocusTimePerDay(since startDate: Date, to endDate: Date, calendar: Calendar, completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async {
            let cal = calendar
            var buckets: [DashboardTimeBucket] = []
            for i in 0..<7 {
                let date = cal.date(byAdding: .day, value: -i, to: endDate)!
                buckets.insert(DashboardTimeBucket(date: date, duration: Double.random(in: 0...7200)), at: 0)
            }
            completion(.success(buckets))
        }
    }
    func fetchAppDomainFocusDistribution(since startDate: Date, to endDate: Date, completion: @escaping (Result<[DashboardAppDistribution], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
}
struct WeeklyHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        WeeklyHistoryView(querying: WeeklyHistoryPreviewQuerying())
            .padding().background(Color.black.opacity(0.9))
    }
}
#endif

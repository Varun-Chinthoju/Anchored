import SwiftUI
import AppKit

enum DashboardChrome {
    static let main = Color(hex: 0x2A2522)
    static let tile = Color(hex: 0x403A35)
    static let sidebarTop = main
    static let sidebarBottom = Color(hex: 0x211E1C)
    static let cardTop = tile
    static let cardBottom = Color(hex: 0x34302C)
    static let control = main
    static let chartTop = tile
    static let chartBottom = Color(hex: 0x302C29)
}

enum DashboardRange: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case quarter = "3M"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .day:
            return 1
        case .week:
            return 7
        case .month:
            return 30
        case .quarter:
            return 90
        }
    }

    var title: String {
        switch self {
        case .day:
            return "Past 24 hours"
        case .week:
            return "Past 7 days"
        case .month:
            return "This month"
        case .quarter:
            return "Past 90 days"
        }
    }

    var trendAxisCaption: String {
        switch self {
        case .day:
            return "Focus time by hour"
        case .week:
            return "Focus time by day"
        case .month:
            return "Focus time by day"
        case .quarter:
            return "Focus time by day"
        }
    }

    var trendAxisLabels: [String] {
        switch self {
        case .day:
            return ["0", "6", "12", "18", "24"]
        case .week:
            return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        case .month:
            return ["Week 1", "Week 2", "Week 3", "Week 4"]
        case .quarter:
            return ["Month 1", "Month 2", "Month 3"]
        }
    }
}

enum DashboardNavItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case logs = "Analytics"
    case charts = "Focus Charts"
    case crew = "Crew & Goals"
    case routes = "Routes"
    case settings = "Tide Settings"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2.fill"
        case .logs:
            return "chart.bar.fill"
        case .charts:
            return "chart.xyaxis.line"
        case .crew:
            return "flag.checkered"
        case .routes:
            return "map.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

final class DashboardDataModel: ObservableObject {
    @Published var trendBuckets: [DashboardTimeBucket] = []
    @Published var topDistractions: [DistractionRank] = []
    @Published var trendState: Loadable<[DashboardTimeBucket]> = .idle
    @Published var distractionsState: Loadable<[DistractionRank]> = .idle
    @Published var timelineState: Loadable<[TimelineBlock]> = .idle
    @Published var weeklyState: Loadable<[DashboardTimeBucket]> = .idle
    @Published var rangeSummary: DashboardRangeSummary = DashboardRangeSummary(
        sessionCount: 0,
        totalFocusDuration: 0,
        longestSessionDuration: 0
    )
    @Published var allTimeSummary: DashboardRangeSummary = DashboardRangeSummary(
        sessionCount: 0,
        totalFocusDuration: 0,
        longestSessionDuration: 0
    )

    private let querying: DashboardQuerying
    private var generation: Int = 0

    init(querying: DashboardQuerying = SQLiteSessionStore.shared, store: SQLiteSessionStore = .shared) {
        self.querying = querying
        _ = store
    }

    func refresh(range: DashboardRange) {
        generation = generation &+ 1
        let currentGeneration = generation
        let calendar = Calendar.current
        let now = Date()
        trendState = .loading
        distractionsState = .loading
        timelineState = .loading
        weeklyState = .loading

        querying.fetchEarliestSessionDate { [weak self] result in
            guard let self = self, currentGeneration == self.generation else { return }
            let earliest: Date?
            switch result {
            case .success(let date):
                earliest = date
            case .failure:
                earliest = nil
            }

            let startDate = Self.startDate(
                for: range,
                referenceDate: now,
                calendar: calendar,
                earliestSessionDate: earliest
            )

            self.querying.fetchRangeSummary(since: startDate, to: now) { [weak self] res in
                guard let self = self, currentGeneration == self.generation else { return }
                switch res {
                case .success(let summary):
                    self.rangeSummary = summary
                case .failure:
                    self.rangeSummary = DashboardRangeSummary(sessionCount: 0, totalFocusDuration: 0, longestSessionDuration: 0)
                }
            }

            self.querying.fetchRangeSummary(since: Date.distantPast, to: now) { [weak self] res in
                guard let self = self, currentGeneration == self.generation else { return }
                switch res {
                case .success(let summary):
                    self.allTimeSummary = summary
                case .failure:
                    break
                }
            }

            self.querying.fetchTopDistractions(since: startDate, to: now) { [weak self] res in
                guard let self = self, currentGeneration == self.generation else { return }
                switch res {
                case .success(let ranks):
                    let top = Array(ranks.prefix(5))
                    self.topDistractions = top
                    self.distractionsState = top.isEmpty ? .empty : .loaded(top)
                case .failure(let error):
                    self.topDistractions = []
                    self.distractionsState = .failed(error.localizedDescription)
                }
            }

            if range == .day {
                self.querying.fetchFocusTimePerHourForLast24Hours(relativeTo: now, calendar: calendar) { [weak self] result in
                    self?.apply(result: result, generation: currentGeneration)
                }
            } else {
                self.querying.fetchFocusTimePerDay(since: startDate, to: now, calendar: calendar) { [weak self] result in
                    self?.apply(result: result, generation: currentGeneration)
                }
            }

            self.querying.fetchTimelineBlocks(for: now, calendar: calendar) { [weak self] result in
                guard let self = self, currentGeneration == self.generation else { return }
                switch result {
                case .success(let blocks):
                    self.timelineState = blocks.isEmpty ? .empty : .loaded(blocks)
                case .failure(let error):
                    self.timelineState = .failed(error.localizedDescription)
                }
            }

            let weeklyStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
            self.querying.fetchFocusTimePerDay(since: weeklyStart, to: now, calendar: calendar) { [weak self] result in
                guard let self = self, currentGeneration == self.generation else { return }
                switch result {
                case .success(let buckets):
                    self.weeklyState = buckets.isEmpty ? .empty : .loaded(buckets)
                case .failure(let error):
                    self.weeklyState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func apply(result: Result<[DashboardTimeBucket], DashboardQueryError>, generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, generation == self.generation else { return }
            switch result {
            case .success(let buckets):
                self.trendBuckets = buckets
                self.trendState = buckets.isEmpty ? .empty : .loaded(buckets)
            case .failure(let error):
                self.trendBuckets = []
                self.trendState = .failed(error.localizedDescription)
            }
        }
    }

    private static func startDate(
        for range: DashboardRange,
        referenceDate: Date,
        calendar: Calendar,
        earliestSessionDate: Date?
    ) -> Date {
        switch range {
        case .day:
            return calendar.date(byAdding: .hour, value: -24, to: referenceDate) ?? referenceDate
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        case .month:
            let monthStart = calendar.dateInterval(of: .month, for: referenceDate)?.start ?? calendar.startOfDay(for: referenceDate)
            guard let earliestSessionDate else {
                return monthStart
            }
            return max(monthStart, earliestSessionDate)
        case .quarter:
            return calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        }
    }
}

struct DashboardView: View {
    @StateObject private var menuBarViewModel: MenuBarViewModel
    @StateObject private var dataModel = DashboardDataModel()
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var selectedRange: DashboardRange = .week
    @State private var selectedSidebarItem: DashboardNavItem = .dashboard

    private let showsSidebar: Bool
    private let onOpenSettings: (() -> Void)?

    init(
        focusEngine: FocusEngine,
        showsSidebar: Bool = true,
        onOpenSettings: (() -> Void)? = nil
    ) {
        _menuBarViewModel = StateObject(wrappedValue: MenuBarViewModel(focusEngine: focusEngine))
        self.showsSidebar = showsSidebar
        self.onOpenSettings = onOpenSettings
    }

    private var palette: ThemePalette {
        prefs.selectedThemePalette
    }

    private var focusScore: Int {
        menuBarViewModel.stats.sessionCountToday
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsSidebar {
                sidebar
                Divider()
                    .overlay(palette.separatorColor.opacity(0.8))
            }
            mainContent
        }
        .padding(showsSidebar ? 12 : 16)
        .background(dashboardBackground)
        .onAppear {
            menuBarViewModel.refresh()
            dataModel.refresh(range: selectedRange)
        }
        .onChange(of: selectedRange) { newValue in
            dataModel.refresh(range: newValue)
        }
        .accentColor(palette.accentColor)
        .tint(palette.accentColor)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            ControlRoomSectionHeader(
                eyebrow: "Focus",
                title: "Anchored",
                subtitle: "Review your momentum and correct course without leaving this panel.",
                accent: palette.accentColor
            )

            VStack(spacing: 8) {
                ForEach(DashboardNavItem.allCases) { item in
                    DashboardSidebarRow(
                        item: item,
                        isSelected: item == selectedSidebarItem,
                        palette: palette
                    )
                    .onTapGesture {
                        selectedSidebarItem = item
                    }
                }
            }

            Spacer(minLength: 16)

            TodayActivityCard(
                sessionCount: focusScore,
                focusDuration: menuBarViewModel.stats.focusedTimeToday,
                streakDays: menuBarViewModel.stats.streakDays,
                palette: palette
            )

            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Open Settings")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .foregroundColor(palette.textPrimaryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(palette.surfaceColor.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.borderColor.opacity(0.7), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 252)
        .background(
            LinearGradient(
                colors: [
                    DashboardChrome.sidebarTop,
                    DashboardChrome.sidebarBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.borderColor.opacity(0.8), lineWidth: 1)
        )
        .cornerRadius(18)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                HStack(alignment: .top, spacing: 14) {
                    TrendPanel(
                        range: selectedRange,
                        buckets: dataModel.trendBuckets,
                        trendState: dataModel.trendState,
                        palette: palette
                    )
                    .frame(maxWidth: .infinity)

                    TopDistractionsPanel(
                        distractions: dataModel.topDistractions,
                        distractionsState: dataModel.distractionsState,
                        rangeTitle: selectedRange.title,
                        palette: palette
                    )
                    .frame(width: 290)
                }

                HStack(alignment: .top, spacing: 14) {
                    SummaryMetricCard(
                        title: "Focus Sessions",
                        value: "\(dataModel.rangeSummary.sessionCount)",
                        subtitle: selectedRange.title,
                        icon: "checkmark.circle.fill",
                        chartValues: dataModel.trendBuckets.map(\.duration),
                        palette: palette
                    )
                    .frame(maxWidth: .infinity)

                    SummaryMetricCard(
                        title: "Deep Work",
                        value: formattedDuration(dataModel.rangeSummary.totalFocusDuration),
                        subtitle: "Average \(formattedDuration(dataModel.rangeSummary.averageSessionDuration))",
                        icon: "timer",
                        chartValues: dataModel.trendBuckets.map(\.duration),
                        palette: palette
                    )
                    .frame(maxWidth: .infinity)

                    LatestSessionCard(
                        session: menuBarViewModel.recentSessions.first,
                        palette: palette
                    )
                    .frame(maxWidth: .infinity)
                }

                AllTimeSummaryCard(
                    summary: dataModel.allTimeSummary,
                    palette: palette
                )

                ControlRoomFooterStrip(palette: palette, activeSession: menuBarViewModel.activeSession)
            }
            .padding(.vertical, 2)
            .padding(.trailing, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.leading, 16)
        .padding(.trailing, 4)
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            ControlRoomSectionHeader(
                eyebrow: "Analytics",
                title: "Focus history in one place",
                subtitle: "Trends, sessions, and distractions stay in the same working surface.",
                accent: palette.accentColor
            )

            Spacer()

            DashboardRangePicker(selection: $selectedRange, palette: palette)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var dashboardBackground: some View {
        ControlRoomShellBackground(palette: palette)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }
}

private struct DashboardSidebarRow: View {
    let item: DashboardNavItem
    let isSelected: Bool
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18)
            Text(item.rawValue)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
        }
        .foregroundColor(isSelected ? palette.textPrimaryColor : palette.textSecondaryColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundFill)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? palette.accentColor.opacity(0.35) : palette.borderColor.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var backgroundFill: some View {
        Group {
            if isSelected {
                LinearGradient(
                    colors: [palette.accentColor.opacity(0.92), palette.accentShadowColor.opacity(0.92)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                palette.surfaceSubtleColor.opacity(0.48)
            }
        }
    }
}

private struct TodayActivityCard: View {
    let sessionCount: Int
    let focusDuration: TimeInterval
    let streakDays: Int
    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(palette.accentColor.opacity(0.8))
                    .frame(width: 20, height: 4)
                Text("Today")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundColor(palette.textSecondaryColor)
            }

            Text(formatDuration(focusDuration))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimaryColor)
            Text("\(sessionCount) completed session\(sessionCount == 1 ? "" : "s")")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
            Label("\(streakDays) day streak", systemImage: "flame.fill")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(palette.accentColor)
        }
        .padding(16)
        .background(DashboardChrome.cardBottom.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.borderColor.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(minutes)m"
    }
}

private struct DashboardRangePicker: View {
    @Binding var selection: DashboardRange
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardRange.allCases) { range in
                Button(action: {
                    selection = range
                }) {
                    Text(range.rawValue)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(selection == range ? Color.black.opacity(0.82) : palette.textSecondaryColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(buttonBackground(for: range))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selection == range ? palette.accentShadowColor.opacity(0.35) : palette.borderColor.opacity(0.45), lineWidth: 1)
                        )
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DashboardChrome.control.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.borderColor.opacity(0.55), lineWidth: 1)
        )
        .cornerRadius(14)
    }

    private func buttonBackground(for range: DashboardRange) -> some View {
        Group {
            if selection == range {
                LinearGradient(
                    colors: [palette.accentColor, palette.accentShadowColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.clear
            }
        }
    }
}

private struct TrendPanel: View {
    let range: DashboardRange
    let buckets: [DashboardTimeBucket]
    let trendState: Loadable<[DashboardTimeBucket]>
    let palette: ThemePalette

    var body: some View {
        ControlRoomCard(title: "Tide Over Time", subtitle: range.title, palette: palette) {
            chartArea
                .frame(height: 180)
        }
    }

    private var chartArea: some View {
        Group {
            switch trendState {
            case .idle, .loading:
                loadingState
            case .empty:
                emptyState
            case .failed(let message):
                failureState(message)
            case .loaded:
                TrendSparkline(
                    buckets: buckets,
                    palette: palette,
                    axisLabels: axisLabels
                )
            }
        }
    }

    private var axisLabels: [String] {
        range.trendAxisLabels
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(palette.accentColor)
            Text("Charting the tide...")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wave.3.forward")
                .font(.system(size: 24))
                .foregroundColor(palette.accentColor.opacity(0.85))
            Text("No focus history yet.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimaryColor)
            Text("Complete a focus session to populate this chart.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(palette.bronzeColor)
            Text("The tide is rough.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimaryColor)
            Text(message)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrendSparkline: View {
    let buckets: [DashboardTimeBucket]
    let palette: ThemePalette
    let axisLabels: [String]

    private var values: [Double] {
        buckets.map(\.duration)
    }

    private func formatShortDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let maxValue = max(1.0, values.max() ?? 1.0)
            
            let horizontalPadding: CGFloat = 16
            let verticalPadding: CGFloat = 16
            let yAxisWidth: CGFloat = 55
            let chartWidth = width - yAxisWidth
            let drawableHeight = height - (2 * verticalPadding)

            let points = normalizedPoints(
                in: CGSize(width: chartWidth, height: height),
                maxValue: maxValue,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [DashboardChrome.chartTop, DashboardChrome.chartBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                GridLines(
                    palette: palette,
                    chartWidth: chartWidth,
                    verticalPadding: verticalPadding,
                    drawableHeight: drawableHeight
                )

                if !points.isEmpty {
                    TrendAreaShape(points: points, verticalPadding: verticalPadding)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.accentColor.opacity(0.28),
                                    palette.accentColor.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    TrendLineShape(points: points)
                        .stroke(
                            LinearGradient(
                                colors: [palette.accentColor, palette.accentShadowColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: palette.accentColor.opacity(0.25), radius: 6, x: 0, y: 2)
                }

                // Y-axis labels on the right side
                GeometryReader { labelsGeo in
                    let h = labelsGeo.size.height
                    let drawableH = h - (2 * verticalPadding)
                    let levels: [(Double, String)] = [
                        (1.0, formatShortDuration(maxValue)),
                        (0.75, formatShortDuration(maxValue * 0.75)),
                        (0.5, formatShortDuration(maxValue * 0.5)),
                        (0.25, formatShortDuration(maxValue * 0.25)),
                        (0.0, "0m")
                    ]

                    ForEach(levels, id: \.1) { level, labelText in
                        let y = verticalPadding + drawableH * (1.0 - level)
                        Text(labelText)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.textSecondaryColor)
                            .frame(width: yAxisWidth - 6, alignment: .leading)
                            .position(x: chartWidth + yAxisWidth / 2, y: y)
                    }
                }

                VStack {
                    Spacer()
                    GeometryReader { labelsGeo in
                        let h = labelsGeo.size.height
                        let drawableWidth = chartWidth - (2 * horizontalPadding)
                        let step = drawableWidth / CGFloat(max(1, axisLabels.count - 1))
                        
                        ForEach(Array(axisLabels.enumerated()), id: \.offset) { index, label in
                            Text(label)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(palette.textSecondaryColor)
                                .position(x: horizontalPadding + CGFloat(index) * step, y: h / 2)
                        }
                    }
                    .frame(height: 20)
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func normalizedPoints(
        in size: CGSize,
        maxValue: Double,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) -> [CGPoint] {
        let w = size.width - (2 * horizontalPadding)
        let h = size.height - (2 * verticalPadding)
        
        guard values.count > 1 else {
            guard let value = values.first else { return [] }
            let y = verticalPadding + h - (CGFloat(value / maxValue) * h)
            return [CGPoint(x: horizontalPadding, y: y), CGPoint(x: size.width - horizontalPadding, y: y)]
        }

        let step = w / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let x = horizontalPadding + CGFloat(index) * step
            let y = verticalPadding + h - (CGFloat(value / maxValue) * h)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct GridLines: View {
    let palette: ThemePalette
    let chartWidth: CGFloat
    let verticalPadding: CGFloat
    let drawableHeight: CGFloat

    var body: some View {
        Path { path in
            let y25 = verticalPadding + drawableHeight * 0.25
            path.move(to: CGPoint(x: 0, y: y25))
            path.addLine(to: CGPoint(x: chartWidth, y: y25))

            let y50 = verticalPadding + drawableHeight * 0.5
            path.move(to: CGPoint(x: 0, y: y50))
            path.addLine(to: CGPoint(x: chartWidth, y: y50))

            let y75 = verticalPadding + drawableHeight * 0.75
            path.move(to: CGPoint(x: 0, y: y75))
            path.addLine(to: CGPoint(x: chartWidth, y: y75))
        }
        .stroke(
            palette.borderColor.opacity(0.35),
            style: StrokeStyle(lineWidth: 1, dash: [4, 6])
        )
    }
}

private struct TrendLineShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        guard points.count > 1 else {
            return path
        }

        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midX = (current.x + next.x) / 2
            path.addCurve(
                to: next,
                control1: CGPoint(x: midX, y: current.y),
                control2: CGPoint(x: midX, y: next.y)
            )
        }

        return path
    }
}

private struct TrendAreaShape: Shape {
    let points: [CGPoint]
    let verticalPadding: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        let bottomY = rect.maxY - verticalPadding
        path.move(to: CGPoint(x: first.x, y: bottomY))
        path.addLine(to: first)

        guard points.count > 1 else {
            path.addLine(to: CGPoint(x: last.x, y: bottomY))
            path.closeSubpath()
            return path
        }

        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midX = (current.x + next.x) / 2
            path.addCurve(
                to: next,
                control1: CGPoint(x: midX, y: current.y),
                control2: CGPoint(x: midX, y: next.y)
            )
        }

        path.addLine(to: CGPoint(x: last.x, y: bottomY))
        path.closeSubpath()
        return path
    }
}

private struct TopDistractionsPanel: View {
    let distractions: [DistractionRank]
    let distractionsState: Loadable<[DistractionRank]>
    let rangeTitle: String
    let palette: ThemePalette

    var body: some View {
        ControlRoomCard(title: "Top Distractions", subtitle: rangeTitle, palette: palette) {
            Group {
                switch distractionsState {
                case .idle, .loading:
                    loadingState
                case .empty:
                    emptyState
                case .failed(let message):
                    failureState(message)
                case .loaded:
                    loadedState
                }
            }
        }
    }

    private var loadedState: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(distractions.indices, id: \.self) { index in
                let distraction = distractions[index]
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        DistractionBadge(rank: index + 1, palette: palette)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(distraction.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(palette.textPrimaryColor)
                                .lineLimit(1)
                            Text(distraction.domain ?? distraction.bundleID ?? "Unknown source")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundColor(palette.textSecondaryColor)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(formatDuration(TimeInterval(distraction.totalDurationSeconds)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.textPrimaryColor)
                    }

                    if index < distractions.count - 1 {
                        Divider()
                            .overlay(palette.separatorColor.opacity(0.85))
                            .padding(.leading, 38)
                            .padding(.top, 10)
                    }
                }
            }

            if distractions.isEmpty {
                emptyState
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(palette.accentColor)
            Text("Scanning distractions...")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func failureState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unable to load distractions.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimaryColor)
            Text(message)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing noisy yet.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimaryColor)
            Text("When distraction blocks appear, they will show up here.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(max(minutes, 1))m"
    }
}

private struct DistractionBadge: View {
    let rank: Int
    let palette: ThemePalette

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.accentColor.opacity(0.95), palette.accentShadowColor.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.82))
        }
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let chartValues: [Double]
    let palette: ThemePalette

    var body: some View {
        ControlRoomCard(title: title, subtitle: subtitle, palette: palette) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimaryColor)
                    MiniBarChart(values: chartValues, palette: palette)
                        .frame(height: 42)
                }
                Spacer(minLength: 10)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(palette.accentColor)
                    .frame(width: 36, height: 36)
                    .background(palette.surfaceSubtleColor.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

}

private struct MiniBarChart: View {
    let values: [Double]
    let palette: ThemePalette

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(1.0, values.max() ?? 1.0)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(values.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [palette.accentColor.opacity(0.95), palette.accentShadowColor.opacity(0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth(in: geo.size.width), height: max(6, geo.size.height * CGFloat(values[index] / maxValue)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 8 }
        let totalSpacing = CGFloat(max(values.count - 1, 0)) * 6
        return max(6, (width - totalSpacing) / CGFloat(values.count))
    }
}

private struct LatestSessionCard: View {
    let session: SessionEvent?
    let palette: ThemePalette

    var body: some View {
        ControlRoomCard(title: "Latest Session", subtitle: session.map { formatDate($0.timestamp) } ?? "No completed sessions", palette: palette) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session?.appName ?? "No data yet")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimaryColor)
                        .lineLimit(1)
                    Text(session.map { formatDuration(TimeInterval($0.sessionDurationSeconds ?? 0)) } ?? "Complete a focus session to populate this card.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(palette.textSecondaryColor)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(palette.accentColor)
                    .frame(width: 36, height: 36)
                    .background(palette.surfaceSubtleColor.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(minutes)m"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct AllTimeSummaryCard: View {
    let summary: DashboardRangeSummary
    let palette: ThemePalette

    var body: some View {
        ControlRoomCard(title: "All Time", subtitle: "Since your first session", palette: palette) {
            HStack(alignment: .top, spacing: 12) {
                statBlock(
                    label: "Sessions",
                    value: "\(summary.sessionCount)"
                )

                statBlock(
                    label: "Total Focus",
                    value: formatDuration(summary.totalFocusDuration)
                )

                statBlock(
                    label: "Longest Run",
                    value: formatDuration(summary.longestSessionDuration)
                )

                statBlock(
                    label: "Average",
                    value: formatDuration(summary.averageSessionDuration)
                )
            }
        }
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textSecondaryColor)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DashboardChrome.cardBottom.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }
}

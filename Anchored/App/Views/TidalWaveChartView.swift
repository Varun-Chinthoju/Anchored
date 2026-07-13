import SwiftUI
import AppKit

struct BezierCurve: Shape {
    let data: [Double]
    var scale: CGFloat
    
    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !data.isEmpty else { return path }
        
        let width = rect.width
        let height = rect.height
        let maxVal = max(1.0, data.max() ?? 1.0)
        
        if data.count == 1 {
            let val = data[0]
            let yNormalized = height - (CGFloat(val / maxVal) * height)
            let y = height - (height - yNormalized) * scale
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            return path
        }
        
        let stepX = width / CGFloat(data.count - 1)
        
        var points: [CGPoint] = []
        for (index, val) in data.enumerated() {
            let x = CGFloat(index) * stepX
            let yNormalized = height - (CGFloat(val / maxVal) * height)
            let y = height - (height - yNormalized) * scale
            points.append(CGPoint(x: x, y: y))
        }
        
        path.move(to: points[0])
        
        let tension: CGFloat = 0.3
        for i in 0..<points.count - 1 {
            let p1 = points[i]
            let p2 = points[i+1]
            
            let pPrev = i > 0 ? points[i-1] : p1
            let pNext = i < points.count - 2 ? points[i+2] : p2
            
            let controlPoint1 = CGPoint(
                x: p1.x + (p2.x - pPrev.x) * tension,
                y: min(height, max(0, p1.y + (p2.y - pPrev.y) * tension))
            )
            let controlPoint2 = CGPoint(
                x: p2.x - (pNext.x - p1.x) * tension,
                y: min(height, max(0, p2.y - (pNext.y - p1.y) * tension))
            )
            
            path.addCurve(to: p2, control1: controlPoint1, control2: controlPoint2)
        }
        
        return path
    }
}

struct BezierArea: Shape {
    let data: [Double]
    var scale: CGFloat
    
    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !data.isEmpty else { return path }
        
        let width = rect.width
        let height = rect.height
        let maxVal = max(1.0, data.max() ?? 1.0)
        
        if data.count == 1 {
            let val = data[0]
            let yNormalized = height - (CGFloat(val / maxVal) * height)
            let y = height - (height - yNormalized) * scale
            path.move(to: CGPoint(x: 0, y: height))
            path.addLine(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
            return path
        }
        
        let stepX = width / CGFloat(data.count - 1)
        
        var points: [CGPoint] = []
        for (index, val) in data.enumerated() {
            let x = CGFloat(index) * stepX
            let yNormalized = height - (CGFloat(val / maxVal) * height)
            let y = height - (height - yNormalized) * scale
            points.append(CGPoint(x: x, y: y))
        }
        
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: points[0])
        
        let tension: CGFloat = 0.3
        for i in 0..<points.count - 1 {
            let p1 = points[i]
            let p2 = points[i+1]
            
            let pPrev = i > 0 ? points[i-1] : p1
            let pNext = i < points.count - 2 ? points[i+2] : p2
            
            let controlPoint1 = CGPoint(
                x: p1.x + (p2.x - pPrev.x) * tension,
                y: min(height, max(0, p1.y + (p2.y - pPrev.y) * tension))
            )
            let controlPoint2 = CGPoint(
                x: p2.x - (pNext.x - p1.x) * tension,
                y: min(height, max(0, p2.y - (pNext.y - p1.y) * tension))
            )
            
            path.addCurve(to: p2, control1: controlPoint1, control2: controlPoint2)
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        
        return path
    }
}

struct TidalWaveChartView: View {
    @State private var selectedRange: ChartRange = .week
    @State private var loadState: Loadable<[DashboardTimeBucket]> = .idle
    @State private var hoverIndex: Int? = nil
    @State private var animateProgress: CGFloat = 0.0
    @State private var requestGeneration: Int = 0

    private let querying: DashboardQuerying
    @ObservedObject private var prefs = PreferencesManager.shared

    enum ChartRange: String, CaseIterable, Identifiable {
        case day = "1 Day"
        case week = "1 Week"
        case twoWeeks = "2 Weeks"
        case month = "30 Days"

        var id: String { rawValue }
    }

    init(querying: DashboardQuerying = SQLiteSessionStore.shared) {
        self.querying = querying
    }

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeAccentSecondary: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeSurfaceStrong: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeBorder: Color {
        prefs.selectedThemePalette.borderColor
    }

    private var themeTextSecondary: Color {
        prefs.selectedThemePalette.textSecondaryColor
    }

    private func readableForeground(for color: Color) -> Color {
        let resolved = color.nsColor.usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.66 ? .black : .white
    }

    private var chartData: [DashboardTimeBucket] {
        if case .loaded(let buckets) = loadState {
            return buckets
        }
        return []
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tidal Wave Activity")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundColor(themeAccent)

                    if let hoverIndex = hoverIndex, hoverIndex < chartData.count {
                        let dataPoint = chartData[hoverIndex]
                        Text("\(formatTooltipDuration(dataPoint.duration)) focused on \(formatHoverDate(dataPoint.date))")
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(themeTextSecondary)
                    } else {
                        switch loadState {
                        case .idle:
                            Text("Prepare the tide chart.")
                                .font(.system(size: 11, design: .serif))
                                .foregroundColor(themeTextSecondary)
                        case .loading:
                            Text("Charting the tides...")
                                .font(.system(size: 11, design: .serif))
                                .foregroundColor(themeTextSecondary)
                        case .loaded, .empty:
                            Text("Hover to explore your voyage logs")
                                .font(.system(size: 11, design: .serif))
                                .foregroundColor(themeTextSecondary)
                        case .failed(let message):
                            Text(message)
                                .font(.system(size: 11, design: .serif))
                                .foregroundColor(themeTextSecondary)
                        }
                    }
                }

                Spacer()

                PirateSegmentedPicker(selection: $selectedRange)
                    .frame(width: 260)
            }
            .padding(.horizontal, 4)

            ZStack {
                switch loadState {
                case .idle:
                    loadingStateView(title: "Preparing the tides.", subtitle: "Loading the latest voyage logs...")
                case .loading:
                    loadingStateView(title: "Charting the tides...", subtitle: "Fetching the latest voyage logs...")
                case .failed(let message):
                    failureStateView(message: message)
                case .empty:
                    emptyStateView()
                case .loaded(let buckets):
                    chartStateView(for: buckets)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                themeSurface.opacity(0.7),
                                themeSurfaceStrong.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeBorder, lineWidth: 1)
            )
        }
        .onAppear {
            refreshData()
        }
        .onChange(of: selectedRange) { _ in
            refreshData()
        }
        .accentColor(themeAccent)
        .tint(themeAccent)
    }

    private func chartStateView(for buckets: [DashboardTimeBucket]) -> some View {
        let dates = buckets.map { $0.date }
        let values = buckets.map { $0.duration }

        return VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height * 0.33))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.33))

                        path.move(to: CGPoint(x: 0, y: geo.size.height * 0.66))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.66))
                    }
                    .stroke(
                        themeBorder.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                    )

                    BezierArea(data: values, scale: animateProgress)
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeAccent.opacity(0.25),
                                    themeSurfaceStrong.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    BezierCurve(data: values, scale: animateProgress)
                        .stroke(
                            LinearGradient(
                                colors: [themeAccent, themeAccentSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2.5
                        )
                        .shadow(color: themeAccent.opacity(0.3), radius: 4, x: 0, y: 2)

                    if let hoverIndex = hoverIndex, hoverIndex < values.count {
                        let stepX = geo.size.width / (values.count > 1 ? CGFloat(values.count - 1) : 1)
                        let x = CGFloat(hoverIndex) * stepX

                        let maxVal = max(1.0, values.max() ?? 1.0)
                        let yNormalized = geo.size.height - (CGFloat(values[hoverIndex] / maxVal) * geo.size.height)
                        let y = geo.size.height - (geo.size.height - yNormalized) * animateProgress

                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(
                            LinearGradient(
                                colors: [themeAccent.opacity(0.4), themeAccent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                        )

                        Circle()
                            .fill(readableForeground(for: themeAccent))
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                            .shadow(color: themeAccent, radius: 4)
                            .overlay(
                                Circle()
                                    .stroke(themeAccent, lineWidth: 2)
                                    .frame(width: 14, height: 14)
                                    .position(x: x, y: y)
                            )
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        withAnimation(.easeOut(duration: 0.1)) {
                            updateHoverIndex(at: location, size: geo.size, bucketCount: buckets.count)
                        }
                    case .ended:
                        withAnimation(.easeOut(duration: 0.2)) {
                            hoverIndex = nil
                        }
                    }
                }
            }
            .frame(height: 100)

            HStack {
                if dates.count > 2 {
                    if selectedRange == .day {
                Text(formatHour(dates.first))
                    .font(.system(size: 9, design: .serif))
                    .foregroundColor(themeTextSecondary)
                Spacer()
                Text(formatHour(dates[dates.count / 2]))
                    .font(.system(size: 9, design: .serif))
                    .foregroundColor(themeTextSecondary)
                Spacer()
                Text(formatHour(dates.last))
                    .font(.system(size: 9, design: .serif))
                    .foregroundColor(themeTextSecondary)
            } else {
                Text(formatDate(dates.first))
                    .font(.system(size: 9, design: .serif))
                    .foregroundColor(themeTextSecondary)
                Spacer()
                Text(formatDate(dates[dates.count / 2]))
                    .font(.system(size: 9, design: .serif))
                    .foregroundColor(themeTextSecondary)
                Spacer()
                Text(formatDate(dates.last))
                    .font(.system(size: 9, design: .serif))
                    .foregroundColor(themeTextSecondary)
            }
        } else if let first = dates.first {
            Spacer()
            Text(selectedRange == .day ? formatHour(first) : formatDate(first))
                .font(.system(size: 9, design: .serif))
                .foregroundColor(themeTextSecondary)
            Spacer()
        }
            }
            .padding(.horizontal, 4)
        }
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [themeAccent.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "compass.drawing")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [themeAccent, themeAccentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: themeAccentSecondary.opacity(0.5), radius: 6, x: 0, y: 3)
            }

            VStack(spacing: 4) {
                Text("Calm Seas on this leg of the voyage.")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundColor(.primary)

                Text("No logs recorded. Set sail by starting a focus session!")
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(height: 140)
        .transition(.opacity)
    }

    private func failureStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(themeAccent)

            VStack(spacing: 4) {
                Text("The tide chart ran aground.")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundColor(.primary)

                Text(message)
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(.secondary)
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

    private func updateHoverIndex(at location: CGPoint, size: CGSize, bucketCount: Int) {
        guard bucketCount > 0 else {
            hoverIndex = nil
            return
        }
        if bucketCount == 1 {
            hoverIndex = 0
            return
        }
        let stepX = size.width / CGFloat(bucketCount - 1)
        let rawIndex = Int((location.x / stepX).rounded())
        let index = max(0, min(bucketCount - 1, rawIndex))
        hoverIndex = index
    }

    private func refreshData() {
        let generation = requestGeneration &+ 1
        requestGeneration = generation
        hoverIndex = nil
        animateProgress = 0.0
        loadState = .loading

        let calendar = Calendar.current
        let now = Date()

        switch selectedRange {
        case .day:
            querying.fetchFocusTimePerHourForLast24Hours(relativeTo: now, calendar: calendar) { result in
                self.apply(result: result, generation: generation)
            }
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
            querying.fetchFocusTimePerDay(since: start, to: now, calendar: calendar) { result in
                self.apply(result: result, generation: generation)
            }
        case .twoWeeks:
            let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now))!
            querying.fetchFocusTimePerDay(since: start, to: now, calendar: calendar) { result in
                self.apply(result: result, generation: generation)
            }
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
            querying.fetchFocusTimePerDay(since: start, to: now, calendar: calendar) { result in
                self.apply(result: result, generation: generation)
            }
        }
    }

    private func apply(
        result: Result<[DashboardTimeBucket], DashboardQueryError>,
        generation: Int
    ) {
        guard generation == requestGeneration else {
            return
        }

        switch result {
        case .success(let buckets):
            if buckets.isEmpty {
                loadState = .empty
                return
            }
            loadState = .loaded(buckets)
            withAnimation(.easeOut(duration: 0.8)) {
                animateProgress = 1.0
            }
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
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

    private func formatHoverDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if selectedRange == .day {
            formatter.dateFormat = "h:00 a, MMM d"
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private func formatTooltipDuration(_ duration: TimeInterval) -> String {
        if duration == 0 { return "0m" }
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 {
            if m > 0 {
                return "\(h)h \(m)m"
            } else {
                return "\(h)h"
            }
        } else {
            return "\(m)m"
        }
    }

    #if DEBUG
    fileprivate final class TidalWavePreviewQuerying: DashboardQuerying {
        func fetchFocusTimePerHourForLast24Hours(
            relativeTo referenceDate: Date,
            calendar: Calendar,
            completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
        ) {
            DispatchQueue.main.async {
                completion(.success(Self.previewBuckets(for: .day, referenceDate: referenceDate, calendar: calendar)))
            }
        }

        func fetchFocusTimePerDay(
            since startDate: Date,
            to endDate: Date,
            calendar: Calendar,
            completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void
        ) {
            let range: ChartRange
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: endDate)).day ?? 0
            switch days {
            case 6:
                range = .week
            case 13:
                range = .twoWeeks
            default:
                range = .month
            }
            DispatchQueue.main.async {
                completion(.success(Self.previewBuckets(for: range, referenceDate: endDate, calendar: calendar)))
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

        private static func previewBuckets(for range: ChartRange, referenceDate: Date, calendar: Calendar) -> [DashboardTimeBucket] {
            var buckets: [DashboardTimeBucket] = []
            switch range {
            case .day:
                for hour in 0..<24 {
                    let date = calendar.date(byAdding: .hour, value: -hour, to: referenceDate)!
                    let value = (sin(Double(hour) * 0.5) + 1.0) * 1800.0
                    buckets.insert(DashboardTimeBucket(date: date, duration: value), at: 0)
                }
            case .week:
                for day in 0..<7 {
                    let date = calendar.date(byAdding: .day, value: -day, to: referenceDate)!
                    let value = Double([1800, 3600, 7200, 0, 5400, 9000, 4500][day])
                    buckets.insert(DashboardTimeBucket(date: date, duration: value), at: 0)
                }
            case .twoWeeks:
                for day in 0..<14 {
                    let date = calendar.date(byAdding: .day, value: -day, to: referenceDate)!
                    let value = Double([1800, 3600, 7200, 0, 5400, 9000, 4500, 1200, 3000, 8000, 4000, 0, 6000, 7500][day % 7])
                    buckets.insert(DashboardTimeBucket(date: date, duration: value), at: 0)
                }
            case .month:
                for day in 0..<30 {
                    let date = calendar.date(byAdding: .day, value: -day, to: referenceDate)!
                    let value = (sin(Double(day) * 0.4) + 1.0) * 3600.0
                    buckets.insert(DashboardTimeBucket(date: date, duration: value), at: 0)
                }
            }
            return buckets
        }
    }
    #endif
}

struct PirateSegmentButton: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    @ObservedObject private var prefs = PreferencesManager.shared

    private var themeAccent: Color {
        prefs.selectedTheme.primary.colors.first ?? Color.accentColor
    }

    private func readableForeground(for color: Color) -> Color {
        let resolved = color.nsColor.usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.66 ? .black : .white
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .serif))
            .foregroundColor(isSelected ? readableForeground(for: themeAccent) : (isHovered ? themeAccent : .secondary))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? themeAccent : (isHovered ? themeAccent.opacity(0.1) : Color.clear))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                action()
            }
    }
}

struct PirateSegmentedPicker: View {
    @Binding var selection: TidalWaveChartView.ChartRange
    @ObservedObject private var prefs = PreferencesManager.shared

    private var themeAccent: Color {
        prefs.selectedTheme.primary.colors.first ?? Color.accentColor
    }

    private var themeSurface: Color {
        prefs.selectedTheme.secondary.colors.first ?? Color.black
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(TidalWaveChartView.ChartRange.allCases) { range in
                PirateSegmentButton(
                    text: range.rawValue,
                    isSelected: selection == range,
                    action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selection = range
                        }
                    }
                )
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(themeSurface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(themeAccent.opacity(0.25), lineWidth: 1)
        )
    }
}

struct TidalWaveChartView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Group {
                #if DEBUG
                TidalWaveChartView(querying: TidalWaveChartView.TidalWavePreviewQuerying())
                #else
                TidalWaveChartView()
                #endif
            }
            .padding()
            .frame(width: 450)
            .background(Color.black.opacity(0.9))
        }
        .previewDisplayName("Tidal Wave Chart View")
    }
}

import SwiftUI

struct DomainNode: Identifiable {
    let id = UUID()
    let domain: String
    let duration: TimeInterval
}

struct AppNode: Identifiable {
    let id = UUID()
    let bundleID: String
    let name: String
    let duration: TimeInterval
    let domains: [DomainNode]
}

struct NodeView: View {
    let title: String
    let subtitle: String
    let x: CGFloat
    let y: CGFloat
    let isHub: Bool
    var isDomain: Bool = false
    @ObservedObject private var prefs = PreferencesManager.shared

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeAccentSecondary: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeTextSecondary: Color {
        prefs.selectedThemePalette.textSecondaryColor
    }

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(isHub ? themeAccent : (isDomain ? themeAccentSecondary.opacity(0.8) : themeAccent.opacity(0.8)))
                .frame(width: isHub ? 14 : 10, height: isHub ? 14 : 10)
                .overlay(
                    Circle()
                        .stroke(themeAccent.opacity(0.4), lineWidth: 1.5)
                        .scaleEffect(isHub ? 1.3 : 1.15)
                )
                .shadow(color: themeAccent.opacity(0.4), radius: 3)

            Text(title)
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 90)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(themeTextSecondary)
                .lineLimit(1)
        }
        .position(x: x, y: y)
    }
}

struct FleetTreeSpreadmapView: View {
    @State private var loadState: Loadable<[DashboardAppDistribution]> = .idle
    @State private var requestGeneration: Int = 0

    private let querying: DashboardQuerying
    @ObservedObject private var prefs = PreferencesManager.shared

    private var themeAccent: Color {
        prefs.selectedThemePalette.accentColor
    }

    private var themeAccentSecondary: Color {
        prefs.selectedThemePalette.surfaceRaisedColor
    }

    private var themeSurface: Color {
        prefs.selectedThemePalette.surfaceColor
    }

    private var themeBorder: Color {
        prefs.selectedThemePalette.borderColor
    }

    init(querying: DashboardQuerying = SQLiteSessionStore.shared) {
        self.querying = querying
    }

    private var apps: [AppNode] {
        guard case .loaded(let distributions) = loadState else {
            return []
        }

        return distributions.prefix(4).map { distribution in
            let domains = distribution.domains.prefix(3).map {
                DomainNode(domain: $0.domain, duration: $0.duration)
            }
            return AppNode(
                bundleID: distribution.bundleID,
                name: distribution.appName,
                duration: distribution.duration,
                domains: domains
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fleet Tree (Voyage Spread)")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(themeAccent)
                .padding(.horizontal, 4)

            ZStack {
                switch loadState {
                case .idle:
                    loadingStateView(title: "Charting the fleet.", subtitle: "Preparing the voyage spread...")
                case .loading:
                    loadingStateView(title: "Reading the fleet.", subtitle: "Fetching app and domain spread...")
                case .failed(let message):
                    failureStateView(message: message)
                case .empty:
                    emptyStateView()
                case .loaded(let distributions):
                    if distributions.isEmpty {
                        emptyStateView()
                    } else {
                        geometryContentView
                    }
                }
            }
            .frame(height: 240)
            .padding(16)
            .background(themeSurface.opacity(0.78))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeBorder, lineWidth: 1)
            )
        }
        .onAppear {
            loadDistribution()
        }
        .accentColor(themeAccent)
        .tint(themeAccent)
    }

    private var geometryContentView: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            if apps.isEmpty {
                emptyStateView()
                    .frame(width: width, height: height)
            } else {
                let centerX: CGFloat = 60
                let centerY: CGFloat = height / 2

                let appX: CGFloat = width * 0.42
                let domainX: CGFloat = width * 0.78

                let appSpacing = height / CGFloat(apps.count + 1)

                ZStack {
                    Path { path in
                        for (aIndex, app) in apps.enumerated() {
                            let appY = appSpacing * CGFloat(aIndex + 1)

                            path.move(to: CGPoint(x: centerX, y: centerY))
                            path.addCurve(
                                to: CGPoint(x: appX, y: appY),
                                control1: CGPoint(x: (centerX + appX) / 2, y: centerY),
                                control2: CGPoint(x: (centerX + appX) / 2, y: appY)
                            )

                            let isBrowser = app.bundleID.contains("safari") || app.bundleID.contains("chrome") || app.bundleID.contains("firefox") || app.bundleID.contains("arc") || app.bundleID.contains("brave") || app.bundleID.contains("opera")

                            if isBrowser && !app.domains.isEmpty {
                                let domSpacing = height / CGFloat(app.domains.count + 1)
                                for (dIndex, _) in app.domains.enumerated() {
                                    let domY = domSpacing * CGFloat(dIndex + 1)
                                    path.move(to: CGPoint(x: appX, y: appY))
                                    path.addCurve(
                                        to: CGPoint(x: domainX, y: domY),
                                        control1: CGPoint(x: (appX + domainX) / 2, y: appY),
                                        control2: CGPoint(x: (appX + domainX) / 2, y: domY)
                                    )
                                }
                            }
                    }
                }
                    .stroke(themeAccent.opacity(0.18), lineWidth: 1.5)

                    NodeView(title: "Voyage Hub", subtitle: "Core", x: centerX, y: centerY, isHub: true)

                    ForEach(0..<apps.count, id: \.self) { aIndex in
                        let app = apps[aIndex]
                        let appY = appSpacing * CGFloat(aIndex + 1)

                        NodeView(
                            title: app.name,
                            subtitle: formatDuration(app.duration),
                            x: appX,
                            y: appY,
                            isHub: false
                        )

                        let isBrowser = app.bundleID.contains("safari") || app.bundleID.contains("chrome") || app.bundleID.contains("firefox") || app.bundleID.contains("arc") || app.bundleID.contains("brave") || app.bundleID.contains("opera")

                        if isBrowser && !app.domains.isEmpty {
                            let domSpacing = height / CGFloat(app.domains.count + 1)
                            ForEach(0..<app.domains.count, id: \.self) { dIndex in
                                let dom = app.domains[dIndex]
                                let domY = domSpacing * CGFloat(dIndex + 1)

                                NodeView(
                                    title: dom.domain,
                                    subtitle: formatDuration(dom.duration),
                                    x: domainX,
                                    y: domY,
                                    isHub: false,
                                    isDomain: true
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadDistribution() {
        let generation = requestGeneration &+ 1
        requestGeneration = generation
        loadState = .loading

        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!

        querying.fetchAppDomainFocusDistribution(since: start, to: now) { result in
            apply(result: result, generation: generation)
        }
    }

    private func apply(result: Result<[DashboardAppDistribution], DashboardQueryError>, generation: Int) {
        guard generation == requestGeneration else {
            return
        }

        switch result {
        case .success(let distributions):
            if distributions.isEmpty {
                loadState = .empty
            } else {
                loadState = .loaded(distributions)
            }
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
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
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    private func emptyStateView() -> some View {
        VStack {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
                .padding(.bottom, 4)
            Text("No active fleet registered on this voyage.")
                .font(.system(size: 11, design: .serif))
                .foregroundColor(.secondary)
            Button("Retry") {
                loadDistribution()
            }
            .buttonStyle(.bordered)
            .tint(themeAccent)
            .padding(.top, 8)
        }
    }

    private func failureStateView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(themeAccent.opacity(0.85))

            VStack(spacing: 4) {
                Text("The fleet spread could not be plotted.")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundColor(.primary)

                Text(message)
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Retry") {
                loadDistribution()
            }
            .buttonStyle(.borderedProminent)
            .tint(themeAccent)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m)m"
        }
    }
}

#if DEBUG
fileprivate final class FleetTreePreviewQuerying: DashboardQuerying {
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
            completion(.success([]))
        }
    }

    func fetchAppDomainFocusDistribution(
        since startDate: Date,
        to endDate: Date,
        completion: @escaping (Result<[DashboardAppDistribution], DashboardQueryError>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(.success(Self.previewDistributions()))
        }
    }

    private static func previewDistributions() -> [DashboardAppDistribution] {
        [
            DashboardAppDistribution(
                bundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                duration: 10_800,
                domains: []
            ),
            DashboardAppDistribution(
                bundleID: "com.apple.Safari",
                appName: "Safari",
                duration: 8_400,
                domains: [
                    DashboardDomainDistribution(domain: "example.com", duration: 4_200),
                    DashboardDomainDistribution(domain: "openai.com", duration: 2_100),
                    DashboardDomainDistribution(domain: "news.ycombinator.com", duration: 2_100)
                ]
            ),
            DashboardAppDistribution(
                bundleID: "com.brave.Browser",
                appName: "Brave Browser",
                duration: 4_800,
                domains: [
                    DashboardDomainDistribution(domain: "github.com", duration: 3_000),
                    DashboardDomainDistribution(domain: "swift.org", duration: 1_800)
                ]
            )
        ]
    }
}
#endif

#if DEBUG
struct FleetTreeSpreadmapView_Previews: PreviewProvider {
    static var previews: some View {
        FleetTreeSpreadmapView(querying: FleetTreePreviewQuerying())
            .padding()
            .background(Color.black.opacity(0.9))
            .previewDisplayName("Fleet Tree Spreadmap View")
    }
}
#endif

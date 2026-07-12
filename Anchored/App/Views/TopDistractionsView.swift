import SwiftUI
import AppKit

struct TopDistractionsView: View {
    @State private var loadState: Loadable<[DistractionRank]> = .idle
    @State private var requestGeneration: Int = 0

    private let querying: DashboardQuerying
    private let since: Date?
    private let until: Date?
    @ObservedObject private var prefs = PreferencesManager.shared

    init(
        since: Date? = nil,
        to until: Date? = nil,
        querying: DashboardQuerying = SQLiteSessionStore.shared
    ) {
        self.querying = querying
        self.since = since
        self.until = until
    }

    init(
        state: Loadable<[DistractionRank]>,
        querying: DashboardQuerying = SQLiteSessionStore.shared
    ) {
        self.querying = querying
        self.since = nil
        self.until = nil
        _loadState = State(initialValue: state)
    }

    private var themeAccent: Color { prefs.selectedThemePalette.accentColor }
    private var themeAccentSecondary: Color { prefs.selectedThemePalette.surfaceRaisedColor }
    private var themeSurface: Color { prefs.selectedThemePalette.surfaceColor }
    private var themeBorder: Color { prefs.selectedThemePalette.borderColor }
    private var themeTextSecondary: Color { prefs.selectedThemePalette.textSecondaryColor }

    private func readableForeground(for color: Color) -> Color {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.66 ? .black : .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Distractions")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(themeAccent)
                .padding(.horizontal, 4)

            ZStack {
                switch loadState {
                case .idle:
                    loadingStateView(title: "Scanning distractions.", subtitle: "Preparing distraction map...")
                case .loading:
                    loadingStateView(title: "Scanning distractions...", subtitle: "Aggregating interruptions...")
                case .failed(let message):
                    failureStateView(message: message)
                case .empty:
                    emptyStateView()
                case .loaded(let ranks):
                    if ranks.isEmpty { emptyStateView() } else { loadedView(ranks: ranks) }
                }
            }
            .frame(minHeight: 160)
            .padding(12)
            .background(themeSurface.opacity(0.78))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeBorder, lineWidth: 1))
        }
        .onAppear { refreshData() }
        .accentColor(themeAccent)
        .tint(themeAccent)
    }

    private func loadedView(ranks: [DistractionRank]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(0..<min(5, ranks.count), id: \.self) { index in
                    let rank = ranks[index]
                    HStack(spacing: 12) {
                        let isDomain = rank.domain != nil
                        let initial = String(rank.name.prefix(1)).uppercased()
                        Text(initial)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(readableForeground(for: isDomain ? themeAccent : themeAccentSecondary))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(isDomain ? themeAccent.opacity(0.55) : themeAccentSecondary.opacity(0.65)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rank.name).font(.system(size: 12, weight: .bold)).foregroundColor(.primary).lineLimit(1)
                            Text(isDomain ? "Website" : "Application").font(.system(size: 10)).foregroundColor(themeTextSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDuration(TimeInterval(rank.totalDurationSeconds))).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
                            Text("\(rank.count) interrupt\(rank.count == 1 ? "" : "s")").font(.system(size: 9)).foregroundColor(themeTextSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(themeSurface.opacity(0.65))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(themeBorder, lineWidth: 1))
                    .cornerRadius(8)
                }
            }
        }
        .frame(height: 160)
    }

    private func refreshData() {
        let generation = requestGeneration &+ 1
        requestGeneration = generation
        loadState = .loading
        let calendar = Calendar.current
        let now = until ?? Date()
        let start: Date
        if let since = since {
            start = since
        } else {
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        }
        querying.fetchTopDistractions(since: start, to: now) { result in
            apply(result: result, generation: generation)
        }
    }

    private func apply(result: Result<[DistractionRank], DashboardQueryError>, generation: Int) {
        guard generation == requestGeneration else { return }
        switch result {
        case .success(let ranks):
            loadState = ranks.isEmpty ? .empty : .loaded(Array(ranks.prefix(5)))
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
        }.frame(height: 160)
    }

    private func emptyStateView() -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 24)).foregroundColor(themeAccent.opacity(0.8))
            VStack(spacing: 4) {
                Text("No distractions recorded").font(.system(size: 12, weight: .bold, design: .serif)).foregroundColor(.primary)
                Text("When distraction blocks appear, they will show up here.").font(.system(size: 10, design: .serif)).foregroundColor(themeTextSecondary)
            }.multilineTextAlignment(.center)
            Button("Retry") { refreshData() }.buttonStyle(.bordered).tint(themeAccent)
        }.frame(height: 160)
    }

    private func failureStateView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 24)).foregroundColor(themeAccent.opacity(0.85))
            VStack(spacing: 4) {
                Text("Unable to load distractions.").font(.system(size: 12, weight: .bold, design: .serif)).foregroundColor(.primary)
                Text(message).font(.system(size: 10, design: .serif)).foregroundColor(themeTextSecondary).multilineTextAlignment(.center)
            }
            Button("Retry") { refreshData() }.buttonStyle(.borderedProminent).tint(themeAccent)
        }.frame(height: 160)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

#if DEBUG
fileprivate final class TopDistractionsPreviewQuerying: DashboardQuerying {
    func fetchFocusTimePerHourForLast24Hours(relativeTo referenceDate: Date, calendar: Calendar, completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
    func fetchFocusTimePerDay(since startDate: Date, to endDate: Date, calendar: Calendar, completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
    func fetchAppDomainFocusDistribution(since startDate: Date, to endDate: Date, completion: @escaping (Result<[DashboardAppDistribution], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
    func fetchTopDistractions(since startDate: Date, to endDate: Date, completion: @escaping (Result<[DistractionRank], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async {
            completion(.success([
                DistractionRank(name: "twitter.com", bundleID: "com.apple.Safari", domain: "twitter.com", count: 12, totalDurationSeconds: 420),
                DistractionRank(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", domain: nil, count: 8, totalDurationSeconds: 300)
            ]))
        }
    }
}
struct TopDistractionsView_Previews: PreviewProvider {
    static var previews: some View {
        TopDistractionsView(querying: TopDistractionsPreviewQuerying())
            .padding().background(Color.black.opacity(0.9))
    }
}
#endif

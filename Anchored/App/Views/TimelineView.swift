import SwiftUI

struct TimelineView: View {
    @State private var loadState: Loadable<[TimelineBlock]> = .idle
    @State private var requestGeneration: Int = 0
    @State private var hoveredBlock: TimelineBlock? = nil

    private let querying: DashboardQuerying
    private let date: Date
    @ObservedObject private var prefs = PreferencesManager.shared

    init(
        date: Date = Date(),
        querying: DashboardQuerying = SQLiteSessionStore.shared
    ) {
        self.date = date
        self.querying = querying
    }

    init(
        state: Loadable<[TimelineBlock]>,
        date: Date = Date(),
        querying: DashboardQuerying = SQLiteSessionStore.shared
    ) {
        self.date = date
        self.querying = querying
        _loadState = State(initialValue: state)
    }

    private var themeAccent: Color { prefs.selectedThemePalette.accentColor }
    private var themeSurface: Color { prefs.selectedThemePalette.surfaceColor }
    private var themeBorder: Color { prefs.selectedThemePalette.borderColor }
    private var themeTextSecondary: Color { prefs.selectedThemePalette.textSecondaryColor }

    private var blocks: [TimelineBlock] {
        guard case .loaded(let b) = loadState else { return [] }
        return b
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Timeline")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(themeAccent)
                .padding(.horizontal, 4)

            ZStack {
                switch loadState {
                case .idle:
                    loadingStateView(title: "Reading timeline.", subtitle: "Preparing today's voyage...")
                case .loading:
                    loadingStateView(title: "Loading timeline...", subtitle: "Reconstructing focus blocks...")
                case .failed(let message):
                    failureStateView(message: message)
                case .empty:
                    emptyStateView()
                case .loaded(let loadedBlocks):
                    if loadedBlocks.isEmpty {
                        emptyStateView()
                    } else {
                        timelineGeometryContent(blocks: loadedBlocks)
                    }
                }
            }
            .frame(height: 64)
            .padding(12)
            .background(themeSurface.opacity(0.78))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeBorder, lineWidth: 1))
        }
        .onAppear { refreshData() }
        .accentColor(themeAccent)
        .tint(themeAccent)
    }

    private func timelineGeometryContent(blocks: [TimelineBlock]) -> some View {
        GeometryReader { geometry in
            let earliest = blocks.first?.startDate ?? date
            let latest = blocks.last?.endDate ?? date
            let totalDuration = max(1.0, latest.timeIntervalSince(earliest))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))

                ForEach(0..<blocks.count, id: \.self) { index in
                    let block = blocks[index]
                    let startOffset = block.startDate.timeIntervalSince(earliest)
                    let blockDuration = block.endDate.timeIntervalSince(block.startDate)

                    let relativeStart = startOffset / totalDuration
                    let relativeWidth = blockDuration / totalDuration

                    let width = max(3.0, CGFloat(relativeWidth) * geometry.size.width)
                    let xOffset = CGFloat(relativeStart) * geometry.size.width
                    let isHovered = hoveredBlock == block

                    let gradientColor = block.type == .focus ?
                        LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom) :
                        LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(gradientColor)
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                        .shadow(color: isHovered ? (block.type == .focus ? Color.green : Color.red).opacity(0.5) : Color.clear, radius: 4)
                        .frame(width: width, height: geometry.size.height - 12)
                        .offset(x: xOffset, y: 6)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isHovering { hoveredBlock = block }
                                else if hoveredBlock == block { hoveredBlock = nil }
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05), lineWidth: 1))
        }
    }

    private func refreshData() {
        let generation = requestGeneration &+ 1
        requestGeneration = generation
        loadState = .loading
        let calendar = Calendar.current
        querying.fetchTimelineBlocks(for: date, calendar: calendar) { result in
            apply(result: result, generation: generation)
        }
    }

    private func apply(result: Result<[TimelineBlock], DashboardQueryError>, generation: Int) {
        guard generation == requestGeneration else { return }
        switch result {
        case .success(let blocks):
            loadState = blocks.isEmpty ? .empty : .loaded(blocks)
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
        }
    }

    private func loadingStateView(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            ProgressView().progressViewStyle(.circular).tint(themeAccent)
            VStack(spacing: 2) {
                Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(subtitle).font(.system(size: 9, design: .rounded)).foregroundColor(themeTextSecondary)
            }.multilineTextAlignment(.center)
        }
    }

    private func emptyStateView() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.02))
            .overlay(
                VStack(spacing: 6) {
                    Text("No session activity tracked today").font(.system(size: 11)).foregroundColor(.secondary)
                    Button("Retry") { refreshData() }.buttonStyle(.bordered).tint(themeAccent).controlSize(.small)
                }
            )
    }

    private func failureStateView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16)).foregroundColor(themeAccent.opacity(0.85))
            Text("Timeline failed to load.").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.primary)
            Text(message).font(.system(size: 9, design: .rounded)).foregroundColor(themeTextSecondary).multilineTextAlignment(.center)
            Button("Retry") { refreshData() }.buttonStyle(.borderedProminent).tint(themeAccent).controlSize(.small)
        }
    }
}

#if DEBUG
fileprivate final class TimelinePreviewQuerying: DashboardQuerying {
    func fetchFocusTimePerHourForLast24Hours(relativeTo referenceDate: Date, calendar: Calendar, completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
    func fetchFocusTimePerDay(since startDate: Date, to endDate: Date, calendar: Calendar, completion: @escaping (Result<[DashboardTimeBucket], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
    func fetchAppDomainFocusDistribution(since startDate: Date, to endDate: Date, completion: @escaping (Result<[DashboardAppDistribution], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async { completion(.success([])) }
    }
    func fetchTimelineBlocks(for date: Date, calendar: Calendar, completion: @escaping (Result<[TimelineBlock], DashboardQueryError>) -> Void) {
        DispatchQueue.main.async {
            let now = date
            let earlier = calendar.date(byAdding: .hour, value: -2, to: now)!
            let mid = calendar.date(byAdding: .hour, value: -1, to: now)!
            completion(.success([
                TimelineBlock(type: .focus, startDate: earlier, endDate: mid, appName: "Xcode"),
                TimelineBlock(type: .distraction, startDate: mid, endDate: now, appName: "Xcode", distractionAppBundleID: "com.apple.Safari", distractionDomain: "twitter.com")
            ]))
        }
    }
}
struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView(querying: TimelinePreviewQuerying())
            .padding().frame(height: 120).background(Color.black.opacity(0.9))
    }
}
#endif

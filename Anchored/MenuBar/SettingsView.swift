import SwiftUI
import AppKit

// MARK: - Section Enum

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case focusApps = "Focus Apps"
    case distractions = "Distractions"
    case stats = "Stats"
    case analytics = "Analytics"
    case about = "About"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general:      return "gearshape.fill"
        case .focusApps:    return "target"
        case .distractions: return "shield.fill"
        case .stats:        return "flame.fill"
        case .analytics:    return "chart.bar.xaxis"
        case .about:        return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:      return .gray
        case .focusApps:    return .blue
        case .distractions: return .red
        case .stats:        return .orange
        case .analytics:    return .purple
        case .about:        return .gray
        }
    }
}

// MARK: - Top-level Settings View

enum SidebarItem: Hashable {
    case profile(UUID)
    case general
    case focusApps
    case stats
    case analytics
    case about
}

struct ProfileRowView: View {
    let profile: WorkProfile
    let isActive: Bool
    let onDelete: () -> Void
    let onMakeActive: () -> Void
    let canDelete: Bool

    private var iconName: String {
        let lower = profile.name.lowercased()
        if lower.contains("code") || lower.contains("coding") || lower.contains("dev") {
            return "curlybraces"
        } else if lower.contains("write") || lower.contains("writing") || lower.contains("edit") {
            return "doc.text.fill"
        } else if lower.contains("video") || lower.contains("movie") || lower.contains("film") {
            return "play.rectangle.fill"
        } else {
            return "briefcase.fill"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(isActive ? .green : .secondary)
            Text(profile.name)
                .font(.system(size: 13))
            Spacer()
            if isActive {
                Text("Active")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .contextMenu {
            Button("Make Active") {
                onMakeActive()
            }
            if canDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Profile", systemImage: "trash")
                }
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var selectedItem: SidebarItem
    @State private var searchQuery = ""
    @State private var showAddAlert = false
    @State private var newProfileName = ""

    init(initialSection: SettingsSection = .general) {
        let initialItem: SidebarItem
        switch initialSection {
        case .general:
            initialItem = .general
        case .focusApps:
            initialItem = .focusApps
        case .distractions:
            initialItem = .profile(ProfileManager.shared.activeProfile.id)
        case .stats:
            initialItem = .stats
        case .analytics:
            initialItem = .analytics
        case .about:
            initialItem = .about
        }
        _selectedItem = State(initialValue: initialItem)
    }

    var filteredProfiles: [WorkProfile] {
        let all = profileManager.profiles
        guard !searchQuery.isEmpty else { return all }
        let q = searchQuery.lowercased()
        return all.filter { $0.name.lowercased().contains(q) }
    }

    var filteredSections: [SettingsSection] {
        let sections: [SettingsSection] = [.general, .focusApps, .stats, .analytics, .about]
        guard !searchQuery.isEmpty else { return sections }
        let q = searchQuery.lowercased()
        return sections.filter { $0.rawValue.lowercased().contains(q) }
    }

    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(7)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                List(selection: $selectedItem) {
                    Section {
                        ForEach(filteredProfiles) { profile in
                            ProfileRowView(
                                profile: profile,
                                isActive: profile.id == profileManager.activeProfile.id,
                                onDelete: { deleteProfile(profile) },
                                onMakeActive: { makeProfileActive(profile) },
                                canDelete: profileManager.profiles.count > 1
                            )
                            .tag(SidebarItem.profile(profile.id))
                        }
                        
                        Button {
                            newProfileName = ""
                            showAddAlert = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.accentColor)
                                    .clipShape(Circle())
                                
                                Text("Add Profile")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    } header: {
                        Text("Work Profiles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }

                    Section("System Settings") {
                        ForEach(filteredSections) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(sidebarItem(for: section))
                                .labelStyle(ColoredLabelStyle(color: section.iconColor))
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .alert("New Profile", isPresented: $showAddAlert) {
                TextField("Profile Name", text: $newProfileName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let newProfile = WorkProfile(name: trimmed)
                        profileManager.addProfile(newProfile)
                        selectedItem = .profile(newProfile.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 350)
        } detail: {
            // DETAIL PANE
            Group {
                switch selectedItem {
                case .profile(let id):
                    if let profile = profileManager.profiles.first(where: { $0.id == id }) {
                        ProfileAppsSettingsPane(profileManager: profileManager, profile: profile)
                    } else {
                        Text("Select or create a work profile.")
                            .foregroundColor(.secondary)
                    }
                case .general:
                    GeneralSettingsPane()
                case .focusApps:
                    FocusAppsSettingsPane()
                case .stats:
                    StatsSettingsPane()
                case .analytics:
                    AnalyticsSettingsPane()
                case .about:
                    AboutSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 990, height: 630)
        .onChange(of: selectedItem) { newItem in
            if case .profile(let id) = newItem,
               let profile = profileManager.profiles.first(where: { $0.id == id }) {
                profileManager.switchProfile(to: profile.name)
            }
        }
        .onReceive(profileManager.$activeProfile) { newActiveProfile in
            // Switch sidebar selection if active profile changes externally (like from status bar)
            if case .profile = selectedItem {
                selectedItem = .profile(newActiveProfile.id)
            }
        }
    }

    private func deleteProfile(_ profile: WorkProfile) {
        if let index = profileManager.profiles.firstIndex(where: { $0.id == profile.id }) {
            profileManager.deleteProfile(at: index)
            if case .profile(let selectedId) = selectedItem, selectedId == profile.id {
                selectedItem = .profile(profileManager.activeProfile.id)
            }
        }
    }

    private func makeProfileActive(_ profile: WorkProfile) {
        profileManager.switchProfile(to: profile.name)
    }

    private func sidebarItem(for section: SettingsSection) -> SidebarItem {
        switch section {
        case .general:      return .general
        case .focusApps:    return .focusApps
        case .distractions: return .profile(profileManager.activeProfile.id)
        case .stats:        return .stats
        case .analytics:    return .analytics
        case .about:        return .about
        }
    }
}

// MARK: - Label Style

struct ColoredLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(width: 22, height: 22)
                configuration.icon
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            configuration.title
                .font(.system(size: 13))
        }
    }
}

// MARK: - Shared Pane Layout

struct SettingsPane<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.bottom, 2)
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// Grouped container matching macOS System Settings style
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

// A single row inside a SettingsGroup with optional divider below
struct SettingsRow<Content: View>: View {
    let label: String
    let description: String?
    let showDivider: Bool
    @ViewBuilder let control: () -> Content

    init(label: String, description: String? = nil, showDivider: Bool = true, @ViewBuilder control: @escaping () -> Content) {
        self.label = label
        self.description = description
        self.showDivider = showDivider
        self.control = control
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13))
                    if let desc = description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                control()
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsPane: View {
    @StateObject private var prefs = PreferencesManager.shared

    private let thresholds: [(Double, String)] = [
        (300.0, "5 min"), (600.0, "10 min"), (900.0, "15 min"), (1800.0, "30 min")
    ]
    private let countdowns = [5, 10, 15, 20]

    var body: some View {
        SettingsPane(title: "General") {
            // Focus Behavior
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus Behavior")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(label: "Focus Threshold", description: "How long you must work before triggering an anchor prompt.") {
                        Picker("", selection: $prefs.focusThreshold) {
                            ForEach(thresholds, id: \.0) { value, label in
                                Text(label).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }

                    SettingsRow(label: "Distraction Warning Countdown", description: "Seconds on a distraction app before screen dimming starts.", showDivider: false) {
                        Picker("", selection: $prefs.countdownDuration) {
                            ForEach(countdowns, id: \.self) { value in
                                Text("\(value)s").tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                }
            }

            // System
            VStack(alignment: .leading, spacing: 6) {
                Text("System")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(label: "Launch at Login", description: "Automatically start Anchored when you log in.", showDivider: false) {
                        Toggle("", isOn: $prefs.launchAtLogin)
                    }
                }
            }
        }
    }
}

// MARK: - Focus Apps Settings

struct FocusAppsSettingsPane: View {
    @State private var manager = FocusListManager.shared
    @State private var focusApps: [String] = []
    @State private var suggestions: [(bundleID: String, name: String)] = []

    var body: some View {
        SettingsPane(title: "Focus Apps") {
            Text("Only these apps will accumulate focus time. Switching to unlisted apps won't trigger session logic.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Active apps
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: selectCustomFocusApp) {
                        Label("Add App...", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.leading, 2)

                if focusApps.isEmpty {
                    emptyState("No focus apps added yet.")
                } else {
                    SettingsGroup {
                        ForEach(focusApps.indices, id: \.self) { i in
                            let bundleID = focusApps[i]
                            HStack {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                Text(appName(for: bundleID))
                                    .font(.system(size: 13))
                                Spacer()
                                Text(bundleID)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Button {
                                    manager.remove(bundleID)
                                    refresh()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < focusApps.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            // Suggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggestions (Installed)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 2)

                    SettingsGroup {
                        ForEach(suggestions.indices, id: \.self) { i in
                            let s = suggestions[i]
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                Text(s.name)
                                    .font(.system(size: 13))
                                Spacer()
                                Button("Add") {
                                    manager.add(s.bundleID)
                                    refresh()
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < suggestions.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        focusApps = manager.allFocusApps.sorted { appName(for: $0) < appName(for: $1) }
        suggestions = manager.installedSuggestions
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private func selectCustomFocusApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            let id = Bundle(url: url)?.bundleIdentifier
                ?? (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String)
            if let id { manager.add(id); refresh() }
        }
    }
}

// MARK: - Distractions Settings

// MARK: - Profile Apps Settings

struct ProfileAppsSettingsPane: View {
    @ObservedObject var profileManager: ProfileManager
    let profile: WorkProfile

    @State private var suggestions: [(bundleID: String, name: String)] = []

    private var sortedDistractionApps: [String] {
        profile.distractionApps.sorted { appName(for: $0) < appName(for: $1) }
    }

    private var filteredSuggestions: [(bundleID: String, name: String)] {
        suggestions.filter { !profile.distractionApps.contains($0.bundleID) }
    }

    var body: some View {
        SettingsPane(title: "\(profile.name) Profile") {
            // Rename Profile Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Profile Name")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("Profile Name", text: Binding(
                    get: { profile.name },
                    set: { newName in
                        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        var updated = profile
                        updated.name = newName
                        profileManager.updateProfile(updated)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(maxWidth: 300)
            }

            Text("These apps will trigger the dimming overlay when opened during a focus session in this profile.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Blocked Apps
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Blocked Apps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: addCustomDistraction) {
                        Label("Add App...", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.leading, 2)

                if profile.distractionApps.isEmpty {
                    emptyState("No distraction apps added yet.")
                } else {
                    SettingsGroup {
                        let sortedApps = sortedDistractionApps
                        ForEach(sortedApps.indices, id: \.self) { i in
                            let bundleID = sortedApps[i]
                            HStack {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                                Text(appName(for: bundleID))
                                    .font(.system(size: 13))
                                Spacer()
                                Text(bundleID)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Button {
                                    var updated = profile
                                    updated.distractionApps.removeAll { $0 == bundleID }
                                    profileManager.updateProfile(updated)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < sortedApps.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            // Suggestions
            let listSuggestions = filteredSuggestions
            if !listSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggestions (Installed on your Mac)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 2)

                    SettingsGroup {
                        ForEach(listSuggestions.indices, id: \.self) { i in
                            let s = listSuggestions[i]
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                Text(s.name)
                                    .font(.system(size: 13))
                                Spacer()
                                Button("Add") {
                                    var updated = profile
                                    if !updated.distractionApps.contains(s.bundleID) {
                                        updated.distractionApps.append(s.bundleID)
                                        profileManager.updateProfile(updated)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < listSuggestions.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 8)

            DomainEditorView(profileManager: profileManager, profile: profile)
        }
        .onAppear {
            refreshSuggestions()
        }
        .onChange(of: profile.distractionApps) { _ in
            refreshSuggestions()
        }
    }

    private func refreshSuggestions() {
        suggestions = DistractionListManager.shared.installedSuggestions
    }

    private func appName(for bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .deletingPathExtension().lastPathComponent ?? bundleID
    }

    private func addCustomDistraction() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            let id = Bundle(url: url)?.bundleIdentifier
                ?? (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String)
            if let id {
                var updated = profile
                if !updated.distractionApps.contains(id) {
                    updated.distractionApps.append(id)
                    profileManager.updateProfile(updated)
                }
            }
        }
    }
}

// MARK: - Stats Settings

struct StatsSettingsPane: View {
    @StateObject private var vm = MenuBarViewModel(focusEngine: FocusEngine(
        activityMonitor: AppSwitchMonitor(),
        distractionListManager: DistractionListManager.shared
    ))
    private let dailyTarget = 7200.0

    private var progress: Double {
        min(1.0, vm.stats.focusedTimeToday / dailyTarget)
    }

    var body: some View {
        SettingsPane(title: "Stats") {
            // Summary cards
            HStack(spacing: 12) {
                statCard("Today's Focus", value: formatDuration(vm.stats.focusedTimeToday), icon: "hourglass", color: .blue)
                statCard("Sessions", value: "\(vm.stats.sessionCountToday)", icon: "checkmark.circle", color: .green)
                statCard("Streak", value: "\(vm.stats.streakDays)d", icon: "flame.fill", color: .orange)
            }

            // Progress ring
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily Goal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)

                let currentProgress = progress

                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                            .frame(width: 80, height: 80)
                        Circle()
                            .trim(from: 0, to: CGFloat(currentProgress))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 80, height: 80)
                        Text("\(Int(currentProgress * 100))%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Goal: 2 hours of focused work")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(Int(vm.stats.focusedTimeToday / 60)) of 120 minutes logged today")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
            }
        }
        .onAppear { vm.refresh() }
    }

    private func statCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func formatDuration(_ s: Double) -> String {
        let m = Int(s) / 60
        return m < 1 ? "\(Int(s))s" : "\(m)m"
    }
}

// MARK: - Analytics Settings

struct AppBreakdownRow: View {
    let app: String
    let duration: TimeInterval
    let total: TimeInterval

    var body: some View {
        let frac = total > 0 ? duration / total : 0
        VStack(spacing: 6) {
            HStack {
                Text(app).font(.system(size: 13))
                Spacer()
                Text("\(Int(duration / 60))m · \(Int(frac * 100))%")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 5)
                    Capsule().fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(frac), height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct AnalyticsSettingsPane: View {
    @State private var appBreakdown: [(String, TimeInterval)] = []
    @StateObject private var vm = MenuBarViewModel(focusEngine: FocusEngine(
        activityMonitor: AppSwitchMonitor(),
        distractionListManager: DistractionListManager.shared
    ))

    private var totalDuration: TimeInterval {
        appBreakdown.map(\.1).reduce(0, +)
    }

    var body: some View {
        SettingsPane(title: "Analytics") {
            // App breakdown
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus Time by Application")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)

                if appBreakdown.isEmpty {
                    emptyState("No analytics recorded yet.")
                } else {
                    let total = totalDuration
                    VStack(spacing: 0) {
                        ForEach(appBreakdown.indices, id: \.self) { i in
                            let (app, duration) = appBreakdown[i]
                            AppBreakdownRow(app: app, duration: duration, total: total)
                            if i < appBreakdown.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
                }
            }

            // Session history
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's Sessions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)

                if vm.recentSessions.isEmpty {
                    emptyState("No sessions logged today.")
                } else {
                    SettingsGroup {
                        ForEach(vm.recentSessions.indices, id: \.self) { i in
                            let s = vm.recentSessions[i]
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                                Text(s.appName).font(.system(size: 13))
                                Spacer()
                                Text(formatTime(s.timestamp))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(formatDuration(Double(s.sessionDurationSeconds ?? 0)))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < vm.recentSessions.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            vm.refresh()
            appBreakdown = SessionStore.shared.getAppBreakdown().sorted { $0.1 > $1.1 }
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let m = Int(s) / 60
        return m < 1 ? "\(Int(s))s" : "\(m)m"
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: d)
    }
}

// MARK: - About Settings

struct AboutSettingsPane: View {
    var body: some View {
        SettingsPane(title: "About") {
            HStack(spacing: 20) {
                Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Anchored")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Version 1.0.0 (Build 1)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Zero-setup momentum preservation for macOS.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))

            SettingsGroup {
                SettingsRow(label: "Check for Updates", showDivider: true) {
                    Button("Check Now") {}
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                }
                SettingsRow(label: "Privacy Policy", showDivider: false) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Text("© 2026 Anchored. All rights reserved.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Helpers

private func emptyState(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
}




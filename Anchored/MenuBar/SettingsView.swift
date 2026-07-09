import SwiftUI
import AppKit

private enum SettingsTheme {
    static var palette: ThemePalette {
        PreferencesManager.shared.selectedThemePalette
    }

    static var accent: Color { palette.accentColor }
    static var accentShadow: Color { palette.accentShadowColor }
    static var parchment: Color { palette.parchmentColor }
    static var darkWood: Color { palette.darkWoodColor }
    static var canvas: Color { palette.canvasColor }
    static var surface: Color { palette.surfaceColor }
    static var surfaceRaised: Color { palette.surfaceRaisedColor }
    static var border: Color { palette.borderColor }
    static var meterTrack: Color { palette.meterTrackColor }
    static var textPrimary: Color { palette.textPrimaryColor }
    static var textSecondary: Color { palette.textSecondaryColor }
    static var bronze: Color { palette.bronzeColor }
}

// MARK: - Section Enum

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case distractions = "Distraction List"
    case captainsLog = "Captain's Log"
    case about = "About"

    var id: String { rawValue }

    func displayName(isPirateMode: Bool) -> String {
        switch self {
        case .general:
            return isPirateMode ? "Rigging" : "General"
        case .distractions:
            return isPirateMode ? "Siren List" : "Distraction List"
        case .captainsLog:
            return "Captain's Log"
        case .about:
            return isPirateMode ? "Crew Info" : "About"
        }
    }

    var iconName: String {
        switch self {
        case .general:      return "helm"
        case .distractions: return "shield.fill"
        case .captainsLog:  return "book.closed.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:      return SettingsTheme.accent
        case .distractions: return SettingsTheme.bronze
        case .captainsLog:  return SettingsTheme.accentShadow
        case .about:        return SettingsTheme.accent.opacity(0.85)
        }
    }
}

// MARK: - Top-level Settings View

enum SidebarItem: Hashable {
    case profile(UUID)
    case general
    case captainsLog
    case about
}

struct ProfileRowView: View {
    let profile: WorkProfile
    let isActive: Bool
    let isPirateMode: Bool
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
        let themeAccent = SettingsTheme.accent
        let split = profile.name.splitEmojiAndText()
        HStack {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(isActive ? themeAccent : SettingsTheme.textSecondary)
                .frame(width: 16, alignment: .center)
            if let emoji = split.emoji {
                HStack(alignment: .center, spacing: 4) {
                    Text(emoji)
                        .font(.system(size: 14))
                    Text(split.text)
                        .font(.system(size: 13))
                }
            } else {
                Text(profile.name)
                    .font(.system(size: 13))
                    .foregroundColor(SettingsTheme.textPrimary)
            }
            Spacer()
            if isActive {
                Text(settingsCopy("Active", pirate: "Afloat", isPirateMode: isPirateMode))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(themeAccent.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .contextMenu {
            Button(settingsCopy("Make Active", pirate: "Hoist Active", isPirateMode: isPirateMode)) {
                onMakeActive()
            }
            if canDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(settingsCopy("Delete Profile", pirate: "Scuttle Profile", isPirateMode: isPirateMode), systemImage: "trash")
                }
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var langManager = LanguageManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var selectedItem: SidebarItem
    @State private var searchQuery = ""
    @State private var showAddAlert = false
    @State private var newProfileName = ""
    private let focusEngine: FocusEngine

    init(focusEngine: FocusEngine, initialSection: SettingsSection = .general) {
        self.focusEngine = focusEngine
        let initialItem: SidebarItem
        switch initialSection {
        case .general:
            initialItem = .general
        case .distractions:
            initialItem = .profile(ProfileManager.shared.activeProfile.id)
        case .captainsLog:
            initialItem = .captainsLog
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
        let sections: [SettingsSection] = [.general, .captainsLog, .about]
        guard !searchQuery.isEmpty else { return sections }
        let q = searchQuery.lowercased()
        return sections.filter { $0.rawValue.lowercased().contains(q) }
    }

    var body: some View {
        let isPirateMode = langManager.isPirateMode
        let themeAccent = SettingsTheme.accent
        let themeSurface = SettingsTheme.surface
        let themeSurfaceRaised = SettingsTheme.surfaceRaised
        let themeTextSecondary = SettingsTheme.textSecondary
        NavigationSplitView {
            // SIDEBAR
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(themeTextSecondary)
                        .font(.system(size: 12))
                    TextField(settingsCopy("Search", pirate: "Search the charts", isPirateMode: isPirateMode), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(themeTextSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(themeSurfaceRaised.opacity(0.72))
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
                                isPirateMode: isPirateMode,
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
                                    .foregroundColor(SettingsTheme.darkWood)
                                    .padding(4)
                                    .background(SettingsTheme.accent)
                                    .clipShape(Circle())
                                
                                Text("Add Profile")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SettingsTheme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    } header: {
                        Text("Profiles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(themeTextSecondary)
                    }

                    Section(settingsCopy("Settings", pirate: "Rigging Settings", isPirateMode: isPirateMode)) {
                        ForEach(filteredSections) { section in
                            Label(section.displayName(isPirateMode: isPirateMode), systemImage: section.iconName)
                                .tag(sidebarItem(for: section))
                                .labelStyle(ColoredLabelStyle(color: section.iconColor))
                        }
                    }
                }
                .listStyle(.sidebar)
                .accentColor(themeAccent)
                .tint(themeAccent)
                .scrollContentBackground(.hidden)
                .background(
                    LinearGradient(
                        colors: [
                            ControlRoomTheme.shellTop,
                            ControlRoomTheme.shellBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .alert("New Profile", isPresented: $showAddAlert) {
                TextField("Profile Name", text: $newProfileName)
                Button(settingsCopy("Cancel", pirate: "Abandon", isPirateMode: isPirateMode), role: .cancel) { }
                Button(settingsCopy("Create", pirate: "Commission", isPirateMode: isPirateMode)) {
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
                        ProfileAppsSettingsPane(isPirateMode: isPirateMode, profileManager: profileManager, profile: profile)
                    } else {
                        Text("Select or create a work profile.")
                            .foregroundColor(themeTextSecondary)
                    }
                case .general:
                    GeneralSettingsPane(isPirateMode: isPirateMode)
                case .captainsLog:
                    CaptainsLogSettingsPane(focusEngine: focusEngine)
                case .about:
                    AboutSettingsPane(isPirateMode: isPirateMode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 990, height: 630)
        .accentColor(themeAccent)
        .tint(themeAccent)
        .background(ControlRoomShellBackground(palette: SettingsTheme.palette))
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
        case .distractions: return .profile(profileManager.activeProfile.id)
        case .captainsLog:  return .captainsLog
        case .about:        return .about
        }
    }
}

// MARK: - Label Style

struct ColoredLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        let iconForeground = readableForeground(for: color)
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(width: 22, height: 22)
                configuration.icon
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconForeground)
            }
            configuration.title
                .font(.system(size: 13))
        }
    }

    private func readableForeground(for color: Color) -> Color {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.62 ? .black : .white
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
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundColor(SettingsTheme.accent)
                    .padding(.bottom, 2)
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(ControlRoomShellBackground(palette: SettingsTheme.palette))
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            LinearGradient(
                colors: [
                    ControlRoomTheme.cardTop,
                    ControlRoomTheme.cardBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsTheme.border, lineWidth: 1))
    }
}

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
                        .foregroundColor(SettingsTheme.textPrimary)
                    if let desc = description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)
                    }
                }
                Spacer()
                control()
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if showDivider {
                Divider().padding(.leading, 16).overlay(SettingsTheme.border.opacity(0.55))
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsPane: View {
    let isPirateMode: Bool
    @StateObject private var prefs = PreferencesManager.shared
    @ObservedObject private var langManager = LanguageManager.shared

    private let thresholds: [(Double, String)] = [
        (300.0, "5 min"), (600.0, "10 min"), (900.0, "15 min"), (1800.0, "30 min")
    ]
    private let countdowns = [5, 10, 15, 20]

    private func formatDuration(_ seconds: Double) -> String {
        let totalSecs = Int(seconds)
        if totalSecs < 60 {
            return "\(totalSecs)s"
        }
        
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        
        if mins >= 60 {
            let hrs = mins / 60
            let remMins = mins % 60
            if remMins == 0 && secs == 0 {
                return "\(hrs) hr"
            } else if remMins == 0 {
                return "\(hrs)h \(secs)s"
            } else if secs == 0 {
                return "\(hrs)h \(remMins)m"
            } else {
                return "\(hrs)h \(remMins)m \(secs)s"
            }
        }
        
        if secs == 0 {
            return "\(mins) min"
        } else {
            return "\(mins)m \(secs)s"
        }
    }

    var body: some View {
        SettingsPane(title: settingsCopy("General", pirate: "Rigging", isPirateMode: isPirateMode)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Focus Behavior", pirate: "Voyage Behavior", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Focus Threshold", pirate: "Voyage Threshold", isPirateMode: isPirateMode),
                        description: settingsCopy("How long you must focus before the session starts.", pirate: "How long ye must sail before dropping anchor.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { prefs.focusThreshold },
                                set: { newValue in
                                    let rounded = (newValue / 5.0).rounded() * 5.0
                                    prefs.focusThreshold = max(5, min(3600, rounded))
                                }
                            ), in: 5...3600)
                                .frame(width: 250)
                            Text(formatDuration(prefs.focusThreshold))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 100, alignment: .trailing)
                        }
                    }

                    SettingsRow(
                        label: settingsCopy("Distraction Warning Countdown", pirate: "Siren Warning Countdown", isPirateMode: isPirateMode),
                        description: settingsCopy("Seconds allowed on a distraction app before the screen dims.", pirate: "Seconds on a distraction app before the fog dims yer screen.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { Double(prefs.countdownDuration) },
                                set: { newValue in
                                    let rounded = Int((newValue / 5.0).rounded() * 5.0)
                                    prefs.countdownDuration = max(5, min(3600, rounded))
                                }
                            ), in: 5...3600)
                                .frame(width: 250)
                            Text(formatDuration(Double(prefs.countdownDuration)))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 100, alignment: .trailing)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Language & Mode", pirate: "Tongue & Navigation", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Ship Language", pirate: "Ship's Tongue", isPirateMode: isPirateMode),
                        description: settingsCopy("The language used throughout the app.", pirate: "The tongue spoken across yer ship.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Picker("", selection: $langManager.currentLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }

                    SettingsRow(
                        label: settingsCopy("Tone", pirate: "Voyage Path", isPirateMode: isPirateMode),
                        description: settingsCopy("Choose pirate speech or standard mode.", pirate: "Choose the fun pirate route or the boring side.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        Picker("", selection: $langManager.isPirateMode) {
                            Text(settingsCopy("Pirate Route 🏴‍☠️", pirate: "Fun Route 🏴‍☠️", isPirateMode: isPirateMode)).tag(true)
                            Text(settingsCopy("Standard Mode 💼", pirate: "Boring Side 💼", isPirateMode: isPirateMode)).tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Launch at Login", pirate: "Launch on Ship Start", isPirateMode: isPirateMode),
                        description: settingsCopy("Automatically launch Anchored when you log in.", pirate: "Automatically start Anchored when ye boot yer Mac.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.launchAtLogin)
                    }

                    SettingsRow(
                        label: settingsCopy("Focus Alerts", pirate: "Anchor Bells", isPirateMode: isPirateMode),
                        description: settingsCopy("Show an alert when a focus session auto-starts.", pirate: "Show a warning when a focus session auto-starts.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.enableSmartNudges)
                    }

                    SettingsRow(
                        label: settingsCopy("AI Visual Productivity Check", pirate: "AI Spyglass (Visual Check)", isPirateMode: isPirateMode),
                        description: settingsCopy("Use local image classification to prevent false alarms. 100% private.", pirate: "Check screens locally to protect your voyage. 100% private.", isPirateMode: isPirateMode),
                        showDivider: prefs.enableImageClassification
                    ) {
                        Toggle("", isOn: $prefs.enableImageClassification)
                    }

                    if prefs.enableImageClassification {
                        SettingsRow(
                            label: settingsCopy("Use SmolVLM 256M (Local VLM)", pirate: "Call SmolVLM 256M (Local VLM)", isPirateMode: isPirateMode),
                            description: settingsCopy("Queries a local SmolVLM 4-bit vision model (only 145 MB).", pirate: "Steer visual checks to local SmolVLM 4-bit model.", isPirateMode: isPirateMode),
                            showDivider: prefs.useLocalGemma
                        ) {
                            Toggle("", isOn: $prefs.useLocalGemma)
                        }

                        if prefs.useLocalGemma {
                            HStack {
                                Spacer()
                                Button(action: {
                                    prefs.downloadGemmaModel()
                                }) {
                                    Text(makeSettingsStatus(prefs.gemmaDownloadStatus, isPirateMode: isPirateMode))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(SettingsTheme.surface)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(SettingsTheme.accent)
                                        .cornerRadius(5)
                                }
                                .buttonStyle(.plain)
                                .disabled(prefs.gemmaDownloadStatus == "Downloading..." || prefs.gemmaDownloadStatus == "Installing mlx-lm..." || prefs.gemmaDownloadStatus == "Downloaded")
                                
                                if prefs.gemmaDownloadStatus == "Downloading..." || prefs.gemmaDownloadStatus == "Installing mlx-lm..." {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 14, height: 14)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Profile Apps Settings

private struct ProfileConfigurationSummary: View {
    let allowedCount: Int
    let distractionCount: Int
    let domainCount: Int

    var body: some View {
        HStack(spacing: 10) {
            summaryItem(title: "Allowed Apps", value: allowedCount, icon: "checkmark.seal.fill", color: SettingsTheme.accent)
            summaryItem(title: "Blocked Apps", value: distractionCount, icon: "shield.slash.fill", color: SettingsTheme.bronze)
            summaryItem(title: "Domain Rules", value: domainCount, icon: "globe", color: SettingsTheme.accentShadow)
        }
    }

    private func summaryItem(title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(SettingsTheme.textPrimary)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SettingsTheme.textSecondary)
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(SettingsTheme.surface.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SettingsTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ProfileAppsSettingsPane: View {
    let isPirateMode: Bool
    @ObservedObject var profileManager: ProfileManager
    let profile: WorkProfile

    @State private var allowedSuggestions: [(bundleID: String, name: String)] = []
    @State private var suggestions: [(bundleID: String, name: String)] = []

    private var sortedAllowedApps: [String] {
        profile.allowedApps.sorted { appName(for: $0) < appName(for: $1) }
    }

    private var sortedDistractionApps: [String] {
        profile.distractionApps.sorted { appName(for: $0) < appName(for: $1) }
    }

    private var filteredAllowedSuggestions: [(bundleID: String, name: String)] {
        allowedSuggestions.filter { !profile.allowedApps.contains($0.bundleID) }
    }

    private var filteredSuggestions: [(bundleID: String, name: String)] {
        suggestions.filter { !profile.distractionApps.contains($0.bundleID) }
    }

    var body: some View {
        SettingsPane(title: "\(profile.name) Profile") {
            ProfileConfigurationSummary(
                allowedCount: profile.allowedApps.count,
                distractionCount: profile.distractionApps.count,
                domainCount: profile.allowedDomains.count + profile.distractionDomains.count
            )

            // Rename Profile Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Profile Name")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)

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

            Text("Choose the productive apps and distracting apps or websites for this profile. Explicit app and domain lists remain the source of truth for enforcement.")
                .font(.system(size: 12))
                .foregroundColor(SettingsTheme.textSecondary)

            // Allowed Apps
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Allowed Apps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SettingsTheme.textSecondary)
                    Spacer()
                    Button(action: addCustomAllowedApp) {
                        Label("Add App...", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.leading, 2)

                if profile.allowedApps.isEmpty {
                    emptyState("No allowed apps added yet.")
                } else {
                    SettingsGroup {
                        let sortedApps = sortedAllowedApps
                        ForEach(sortedApps.indices, id: \.self) { i in
                            let bundleID = sortedApps[i]
                            HStack {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(SettingsTheme.accent)
                                Text(appName(for: bundleID))
                                    .font(.system(size: 13))
                                Spacer()
                                Text(bundleID)
                                    .font(.system(size: 11))
                                    .foregroundColor(SettingsTheme.textSecondary)
                                Button {
                                    var updated = profile
                                    updated.allowedApps.removeAll { $0 == bundleID }
                                    profileManager.updateProfile(updated)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(SettingsTheme.accent.opacity(0.85))
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
            let allowedListSuggestions = filteredAllowedSuggestions
            if !allowedListSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested Apps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SettingsTheme.textSecondary)
                        .padding(.leading, 2)

                    SettingsGroup {
                        ForEach(allowedListSuggestions.indices, id: \.self) { i in
                            let s = allowedListSuggestions[i]
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(SettingsTheme.accent)
                                Text(s.name)
                                    .font(.system(size: 13))
                                Spacer()
                                Button("Add") {
                                    var updated = profile
                                    if !updated.allowedApps.contains(s.bundleID) {
                                        updated.allowedApps.append(s.bundleID)
                                        profileManager.updateProfile(updated)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                                .foregroundColor(SettingsTheme.accent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            if i < allowedListSuggestions.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            // Blocked Apps
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Distraction Apps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SettingsTheme.textSecondary)
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
                                    .foregroundColor(SettingsTheme.bronze)
                                Text(appName(for: bundleID))
                                    .font(.system(size: 13))
                                Spacer()
                                Text(bundleID)
                                    .font(.system(size: 11))
                                    .foregroundColor(SettingsTheme.textSecondary)
                                Button {
                                    var updated = profile
                                    updated.distractionApps.removeAll { $0 == bundleID }
                                    profileManager.updateProfile(updated)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(SettingsTheme.bronze.opacity(0.85))
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
        .onChange(of: profile.allowedApps) { _ in
            refreshSuggestions()
        }
    }

    private func refreshSuggestions() {
        allowedSuggestions = InstalledAppSuggestionProvider.shared.installedSuggestions
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

    private func addCustomAllowedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            let id = Bundle(url: url)?.bundleIdentifier
                ?? (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String)
            if let id {
                var updated = profile
                if !updated.allowedApps.contains(id) {
                    updated.allowedApps.append(id)
                    profileManager.updateProfile(updated)
                }
            }
        }
    }
}

// MARK: - Stats Settings

struct StatsSettingsPane: View {
    let isPirateMode: Bool
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
                statCard(
                    settingsCopy("Focus Time", pirate: "Sand Gathered", isPirateMode: isPirateMode),
                    value: formatDuration(vm.stats.focusedTimeToday),
                    icon: "timer",
                    color: SettingsTheme.accent
                )
                statCard(
                    settingsCopy("Sessions", pirate: "Voyages", isPirateMode: isPirateMode),
                    value: "\(vm.stats.sessionCountToday)",
                    icon: "checkmark.circle",
                    color: SettingsTheme.accentShadow
                )
                statCard(
                    settingsCopy("Streak", pirate: "Sea Streak", isPirateMode: isPirateMode),
                    value: "\(vm.stats.streakDays)d",
                    icon: "flame.fill",
                    color: SettingsTheme.bronze
                )
            }

            // Progress ring
            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Today's Goal", pirate: "Voyage Target", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                let currentProgress = progress

                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(SettingsTheme.meterTrack, lineWidth: 10)
                            .frame(width: 80, height: 80)
                        Circle()
                            .trim(from: 0, to: CGFloat(currentProgress))
                            .stroke(SettingsTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 80, height: 80)
                        Text("\(Int(currentProgress * 100))%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(settingsCopy("Target: 2 hours of focused work", pirate: "Target: 2 hours of smooth sailing", isPirateMode: isPirateMode))
                            .font(.system(size: 13, weight: .semibold))
                        Text(settingsCopy("\(Int(vm.stats.focusedTimeToday / 60)) of 120 minutes logged today", pirate: "\(Int(vm.stats.focusedTimeToday / 60)) of 120 minutes logged this sun", isPirateMode: isPirateMode))
                            .font(.system(size: 12))
                            .foregroundColor(SettingsTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(SettingsTheme.surface.opacity(0.78))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(SettingsTheme.border, lineWidth: 1))
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
                    .foregroundColor(SettingsTheme.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(SettingsTheme.surface.opacity(0.78))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SettingsTheme.border, lineWidth: 1))
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
                    .foregroundColor(SettingsTheme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettingsTheme.meterTrack).frame(height: 5)
                    Capsule().fill(SettingsTheme.accent)
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
    let isPirateMode: Bool
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
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // 1. Tidal Wave Chart (Bezier Curve)
                    TidalWaveChartView()
                    
                    // 2. Fleet Tree (Spreadmap)
                    FleetTreeSpreadmapView()
                    
                    // 3. Constellation Heatmap (Voyage Density)
                    ConstellationHeatmapView()
                    
                    // 4. Sailing Time by Port
                    VStack(alignment: .leading, spacing: 8) {
                        Text(settingsCopy("Time by App", pirate: "Sailing Time by Port", isPirateMode: isPirateMode))
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundColor(SettingsTheme.accent)
                            .padding(.leading, 4)

                        if appBreakdown.isEmpty {
                            emptyState(settingsCopy("No logs recorded yet.", pirate: "No logs recorded yet.", isPirateMode: isPirateMode))
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
                            .background(SettingsTheme.surface.opacity(0.78))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsTheme.border, lineWidth: 1))
                        }
                    }

                    // 5. Today's Voyages
                    VStack(alignment: .leading, spacing: 8) {
                        Text(settingsCopy("Today's Sessions", pirate: "Today's Voyages", isPirateMode: isPirateMode))
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundColor(SettingsTheme.accent)
                            .padding(.leading, 4)

                        if vm.recentSessions.isEmpty {
                            emptyState(settingsCopy("No sessions logged today.", pirate: "No voyages logged this sun.", isPirateMode: isPirateMode))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(vm.recentSessions.indices, id: \.self) { i in
                                    let s = vm.recentSessions[i]
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(SettingsTheme.accent)
                                            .font(.system(size: 12))
                                        Text(s.appName)
                                            .font(.system(size: 12, weight: .bold, design: .serif))
                                            .foregroundColor(SettingsTheme.textPrimary)
                                        Spacer()
                                        Text(formatTime(s.timestamp))
                                            .font(.system(size: 11))
                                            .foregroundColor(SettingsTheme.textSecondary)
                                        Text(formatDuration(Double(s.sessionDurationSeconds ?? 0)))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(SettingsTheme.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    if i < vm.recentSessions.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(SettingsTheme.surface.opacity(0.78))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsTheme.border, lineWidth: 1))
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 24)
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

// MARK: - Captain's Log

struct CaptainsLogSettingsPane: View {
    let focusEngine: FocusEngine

    var body: some View {
        DashboardView(
            focusEngine: focusEngine,
            showsSidebar: false,
            onOpenSettings: nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - About Settings

struct AboutSettingsPane: View {
    let isPirateMode: Bool
    var body: some View {
        SettingsPane(title: settingsCopy("About", pirate: "Crew Info", isPirateMode: isPirateMode)) {
            HStack(spacing: 20) {
                Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Anchored")
                        .font(.system(size: 16, weight: .semibold))
                    Text(settingsCopy("Version 1.0.0 (Build 1)", pirate: "Version 1.0.0 (Build 1)", isPirateMode: isPirateMode))
                        .font(.system(size: 12))
                        .foregroundColor(SettingsTheme.textSecondary)
                    Text(settingsCopy("Zero-setup focus tracking for macOS, built for your workflow.", pirate: "Zero-setup focus momentum preservation for macOS, fit for the high seas.", isPirateMode: isPirateMode))
                        .font(.system(size: 12))
                        .foregroundColor(SettingsTheme.textSecondary)
                }
                Spacer()
            }
            .padding(16)
            .background(SettingsTheme.surface.opacity(0.78))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(SettingsTheme.border, lineWidth: 1))

            SettingsGroup {
                SettingsRow(label: settingsCopy("Check for Updates", pirate: "Scan for Upgrades", isPirateMode: isPirateMode), showDivider: true) {
                    Button(settingsCopy("Check Now", pirate: "Scan Now", isPirateMode: isPirateMode)) {}
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                }
                SettingsRow(label: settingsCopy("Privacy", pirate: "Pirate Code (Privacy)", isPirateMode: isPirateMode), showDivider: false) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.accent)
                }
            }

            Text("© 2026 Anchored. All rights reserved.")
                .font(.system(size: 11))
                .foregroundColor(SettingsTheme.textSecondary)
        }
    }
}

// MARK: - Helpers

private func emptyState(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12))
        .foregroundColor(SettingsTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(SettingsTheme.surface.opacity(0.78))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SettingsTheme.border, lineWidth: 1))
}

private func settingsCopy(_ standard: String, pirate: String, isPirateMode: Bool) -> String {
    isPirateMode ? pirate : standard
}

private func makeSettingsStatus(_ status: String, isPirateMode: Bool) -> String {
    if isPirateMode {
        switch status {
        case "Not Downloaded": return "Get SmolVLM (MLX)"
        case "Installing mlx-lm...": return "Boarding mlx-lm..."
        case "Downloading...": return "Hauling SmolVLM..."
        case "Downloaded": return "SmolVLM Aboard ✅"
        default: return status
        }
    } else {
        switch status {
        case "Not Downloaded": return "Download SmolVLM (MLX)"
        case "Installing mlx-lm...": return "Installing mlx-lm..."
        case "Downloading...": return "Downloading SmolVLM..."
        case "Downloaded": return "SmolVLM Downloaded ✅"
        default: return status
        }
    }
}

import SwiftUI
import AppKit
import ApplicationServices

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
    static var sidebarSelectionFill: LinearGradient {
        LinearGradient(
            colors: [
                bronze.opacity(0.20),
                accent.opacity(0.16)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    static var sidebarSelectionBorder: Color { bronze.opacity(0.42) }
    static var sidebarSelectionIconBackground: Color { accent.opacity(0.24) }
    static var sidebarSelectionBadgeBackground: Color { bronze.opacity(0.18) }
}

// MARK: - Section Enum

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case intelligence = "Productivity Intelligence"
    case privacy = "Privacy & Data"
    case distractions = "Distraction List"
    case captainsLog = "Analytics"
    case about = "About"

    var id: String { rawValue }

    func displayName(isPirateMode: Bool) -> String {
        switch self {
        case .general:
            return isPirateMode ? "Rigging" : "General"
        case .intelligence:
            return isPirateMode ? "Rigging Intelligence" : "Productivity Intelligence"
        case .privacy:
            return isPirateMode ? "Privacy & Data" : "Privacy & Data"
        case .distractions:
            return isPirateMode ? "Siren List" : "Distraction List"
        case .captainsLog:
            return "Analytics"
        case .about:
            return isPirateMode ? "Crew Info" : "About"
        }
    }

    var iconName: String {
        switch self {
        case .general:      return "helm"
        case .intelligence: return "sparkles"
        case .privacy:      return "lock.shield.fill"
        case .distractions: return "shield.fill"
        case .captainsLog:  return "chart.bar.fill"
        case .about:        return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:      return SettingsTheme.accent
        case .intelligence: return SettingsTheme.accentShadow
        case .privacy:      return SettingsTheme.accentShadow
        case .distractions: return SettingsTheme.bronze
        case .captainsLog:  return SettingsTheme.bronze
        case .about:        return SettingsTheme.accent.opacity(0.85)
        }
    }
}

// MARK: - Top-level Settings View

enum SidebarItem: Hashable {
    case profile(UUID)
    case general
    case intelligence
    case privacy
    case captainsLog
    case about
}

struct ProfileRowView: View {
    let profile: WorkProfile
    let isActive: Bool
    let isSelected: Bool
    let isPirateMode: Bool
    let onDelete: () -> Void
    let onMakeActive: () -> Void
    let canDelete: Bool

    private var iconName: String {
        let lower = profile.name.lowercased()
        if lower.contains("code") || lower.contains("coding") || lower.contains("dev") {
            return "curlybraces.square.fill"
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
        let themeBronze = SettingsTheme.bronze
        let split = profile.name.splitEmojiAndText()
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? SettingsTheme.sidebarSelectionIconBackground : themeAccent.opacity(0.96))
                    .frame(width: 22, height: 22)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? SettingsTheme.textPrimary : readableForeground(for: themeAccent))
            }

            if let emoji = split.emoji {
                HStack(alignment: .center, spacing: 4) {
                    Text(emoji)
                        .font(.system(size: 14))
                    Text(split.text)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(SettingsTheme.textPrimary)
                }
            } else {
                Text(profile.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(SettingsTheme.textPrimary)
            }

            Spacer()
            if isActive {
                Text(settingsCopy("Current profile", pirate: "Current profile", isPirateMode: isPirateMode))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(themeBronze)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(SettingsTheme.sidebarSelectionBadgeBackground)
                    .cornerRadius(4)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(SettingsTheme.sidebarSelectionFill)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(SettingsTheme.sidebarSelectionBorder, lineWidth: 1)
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

    private func readableForeground(for color: Color) -> Color {
        let resolved = color.nsColor.usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.62 ? .black : .white
    }
}

struct SettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var langManager = LanguageManager.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var selectedItem: SidebarItem
    @State private var searchQuery = ""
    @State private var searchScrollTarget: SettingsScrollTarget?
    @State private var showAddAlert = false
    @State private var newProfileName = ""
    private let focusEngine: FocusEngine
    private let onCheckForUpdates: (() -> Void)?

    init(
        focusEngine: FocusEngine,
        initialSection: SettingsSection = .general,
        onCheckForUpdates: (() -> Void)? = nil
    ) {
        self.focusEngine = focusEngine
        self.onCheckForUpdates = onCheckForUpdates
        let initialItem: SidebarItem
        switch initialSection {
        case .general:
            initialItem = .general
        case .intelligence:
            initialItem = .intelligence
        case .privacy:
            initialItem = .privacy
        case .distractions:
            initialItem = .profile(ProfileManager.shared.activeProfile.id)
        case .captainsLog:
            initialItem = .captainsLog
        case .about:
            initialItem = .about
        }
        _selectedItem = State(initialValue: initialItem)
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    private var searchSections: [SettingsSearchSection] {
        SettingsSearchIndex.sections(
            query: normalizedSearchQuery,
            isPirateMode: langManager.isPirateMode,
            activeProfileName: profileManager.activeProfile.name
        )
    }

    private var searchResultsView: some View {
        SettingsSearchResultsView(
            query: normalizedSearchQuery,
            sections: searchSections,
            onSelect: selectSearchResult
        )
    }

    private func settingsSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(minWidth: 860, idealWidth: 940, minHeight: 570, idealHeight: 630)
            .accentColor(SettingsTheme.accent)
            .tint(SettingsTheme.accent)
    }

    var body: some View {
        settingsSurface {
            regularSettingsView
        }
    }

    private var regularSettingsView: some View {
        let isPirateMode = langManager.isPirateMode
        return NavigationSplitView {
            settingsSidebar(isPirateMode: isPirateMode)
        } detail: {
            if isSearching {
                searchResultsView
            } else {
                selectedSettingsPane(isPirateMode: isPirateMode)
            }
        }
        .searchable(
            text: $searchQuery,
            placement: .sidebar,
            prompt: settingsCopy("Search Settings", pirate: "Search the charts", isPirateMode: isPirateMode)
        )
        .onChange(of: selectedItem) { newItem in
            if case .profile(let id) = newItem,
               let profile = profileManager.profiles.first(where: { $0.id == id }) {
                profileManager.switchProfile(to: profile.name)
            }
        }
        .onReceive(profileManager.$activeProfile) { newActiveProfile in
            if case .profile = selectedItem {
                selectedItem = .profile(newActiveProfile.id)
            }
        }
        .onChange(of: normalizedSearchQuery) { query in
            if !query.isEmpty {
                searchScrollTarget = nil
            }
        }
    }

    @ViewBuilder
    private func settingsSidebar(isPirateMode: Bool) -> some View {
        let sections: [SettingsSection] = [.general, .intelligence, .privacy, .captainsLog, .about]

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    sidebarSectionHeader("Profiles")

                    VStack(spacing: 6) {
                        ForEach(profileManager.profiles) { profile in
                            let item = SidebarItem.profile(profile.id)
                            Button {
                                selectedItem = item
                            } label: {
                                ProfileRowView(
                                    profile: profile,
                                    isActive: profile.id == profileManager.activeProfile.id,
                                    isSelected: selectedItem == item,
                                    isPirateMode: isPirateMode,
                                    onDelete: { deleteProfile(profile) },
                                    onMakeActive: { makeProfileActive(profile) },
                                    canDelete: profileManager.profiles.count > 1
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            newProfileName = ""
                            showAddAlert = true
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(SettingsTheme.accent.opacity(0.16))
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(SettingsTheme.bronze)
                                }
                                Text("Add Profile")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(SettingsTheme.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sidebarSectionHeader(settingsCopy("Settings", pirate: "Rigging Settings", isPirateMode: isPirateMode))

                    VStack(spacing: 6) {
                        ForEach(sections, id: \.self) { section in
                            let item = sidebarItem(for: section)
                            Button {
                                selectedItem = item
                            } label: {
                                SidebarSettingsRow(
                                    title: section.displayName(isPirateMode: isPirateMode),
                                    systemImage: section.iconName,
                                    color: section.iconColor,
                                    isSelected: selectedItem == item
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(
            LinearGradient(
                colors: [
                    SettingsTheme.canvas.opacity(0.94),
                    SettingsTheme.surface.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 325)
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
    }

    @ViewBuilder
    private func selectedSettingsPane(isPirateMode: Bool) -> some View {
        let themeTextSecondary = SettingsTheme.textSecondary

        Group {
            switch selectedItem {
            case .profile(let id):
                if let profile = profileManager.profiles.first(where: { $0.id == id }) {
                    ProfileAppsSettingsPane(
                        isPirateMode: isPirateMode,
                        profileManager: profileManager,
                        profile: profile,
                        scrollTarget: $searchScrollTarget
                    )
                } else {
                    Text("Select or create a work profile.")
                        .foregroundColor(themeTextSecondary)
                }
            case .general:
                GeneralSettingsPane(
                    isPirateMode: isPirateMode,
                    scrollTarget: $searchScrollTarget
                )
            case .intelligence:
                ProductivityIntelligenceSettingsPane(
                    isPirateMode: isPirateMode,
                    scrollTarget: $searchScrollTarget
                )
            case .privacy:
                PrivacySettingsPane(
                    isPirateMode: isPirateMode,
                    scrollTarget: $searchScrollTarget
                )
            case .captainsLog:
                CaptainsLogSettingsPane(focusEngine: focusEngine)
            case .about:
                AboutSettingsPane(
                    isPirateMode: isPirateMode,
                    onCheckForUpdates: onCheckForUpdates,
                    scrollTarget: $searchScrollTarget
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func selectSearchResult(_ result: SettingsSearchResult) {
        selectedItem = result.route.sidebarItem
        searchScrollTarget = result.route.scrollTarget
        searchQuery = ""
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
        case .intelligence: return .intelligence
        case .privacy:      return .privacy
        case .distractions: return .profile(profileManager.activeProfile.id)
        case .captainsLog:  return .captainsLog
        case .about:        return .about
        }
    }

    @ViewBuilder
    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundColor(SettingsTheme.textSecondary)
            .padding(.leading, 2)
    }

}

private struct SidebarSettingsRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? SettingsTheme.sidebarSelectionIconBackground : color)
                    .frame(width: 22, height: 22)
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? SettingsTheme.textPrimary : readableForeground(for: color))
            }

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundColor(SettingsTheme.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(SettingsTheme.sidebarSelectionFill)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(SettingsTheme.sidebarSelectionBorder, lineWidth: 1)
            }
        }
    }

    private func readableForeground(for color: Color) -> Color {
        let resolved = color.nsColor.usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.62 ? .black : .white
    }
}

// MARK: - Label Style

struct ColoredLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        let iconForeground = readableForeground(for: color)
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    .frame(width: 22, height: 22)
                configuration.icon
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconForeground)
            }
            configuration.title
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }

    private func readableForeground(for color: Color) -> Color {
        let resolved = color.nsColor.usingColorSpace(.deviceRGB) ?? NSColor.white
        let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent + 0.0722 * resolved.blueComponent
        return luminance > 0.62 ? .black : .white
    }
}

// MARK: - Shared Pane Layout

struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    let contextLabel: String?
    @Binding var scrollTarget: SettingsScrollTarget?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String = "Tweak preferences, privacy, and profile behavior from one place.",
        contextLabel: String? = nil,
        scrollTarget: Binding<SettingsScrollTarget?> = .constant(nil),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.contextLabel = contextLabel
        self._scrollTarget = scrollTarget
        self.content = content
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(title)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)

                            if let contextLabel {
                                Text(contextLabel)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .tracking(0.9)
                                    .foregroundColor(SettingsTheme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(SettingsTheme.surfaceRaised.opacity(0.78))
                                    .overlay(
                                        Capsule()
                                            .stroke(SettingsTheme.border.opacity(0.7), lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }

                            Spacer(minLength: 0)
                        }

                        Text(subtitle)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content()
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollToPendingTarget(using: proxy)
            }
            .onChange(of: scrollTarget) { _ in
                scrollToPendingTarget(using: proxy)
            }
            .background(ControlRoomShellBackground(palette: SettingsTheme.palette))
        }
    }

    private func scrollToPendingTarget(using proxy: ScrollViewProxy) {
        guard let target = scrollTarget else { return }
        proxy.scrollTo(target, anchor: .top)
        DispatchQueue.main.async {
            if scrollTarget == target {
                scrollTarget = nil
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            ControlRoomTheme.cardBottom.opacity(0.84)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SettingsTheme.border.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(SettingsTheme.textPrimary)
                    if let desc = description {
                        Text(desc)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(SettingsTheme.textSecondary)
                    }
                }
                Spacer()
                control()
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if showDivider {
                Divider()
                    .padding(.leading, 16)
                    .overlay(SettingsTheme.border.opacity(0.45))
            }
        }
    }
}

struct CloudModelGuidePopover: View {
    let isPirateMode: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsCopy("Add a custom model", pirate: "Add a custom model", isPirateMode: isPirateMode))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(SettingsTheme.textPrimary)
                    Text(settingsCopy("Point Anchored at a local server or a hosted cloud model by setting provider, model name, and endpoint.", pirate: "Point Anchored at a local server or a hosted cloud model by setting provider, model name, and endpoint.", isPirateMode: isPirateMode))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(SettingsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                guideSection(
                    title: settingsCopy("1. Pick a provider", pirate: "1. Pick a provider", isPirateMode: isPirateMode),
                    lines: [
                        settingsCopy("Ollama is for local models exposed at `http://localhost:11434/api/chat`.", pirate: "Ollama is for local models exposed at `http://localhost:11434/api/chat`.", isPirateMode: isPirateMode),
                        settingsCopy("OpenAI also works for local OpenAI-compatible servers such as LM Studio.", pirate: "OpenAI also works for local OpenAI-compatible servers such as LM Studio.", isPirateMode: isPirateMode),
                        settingsCopy("Gemini, OpenAI, and Anthropic work for real hosted cloud models.", pirate: "Gemini, OpenAI, and Anthropic work for real hosted cloud models.", isPirateMode: isPirateMode)
                    ]
                )

                guideSection(
                    title: settingsCopy("2. Set the model and endpoint", pirate: "2. Set the model and endpoint", isPirateMode: isPirateMode),
                    lines: [
                        settingsCopy("Model name should match the server's model ID exactly.", pirate: "Model name should match the server's model ID exactly.", isPirateMode: isPirateMode),
                        settingsCopy("Endpoint URL should be the API route your server expects.", pirate: "Endpoint URL should be the API route your server expects.", isPirateMode: isPirateMode),
                        settingsCopy("If the server uses a proxy or a custom route, paste that URL here.", pirate: "If the server uses a proxy or a custom route, paste that URL here.", isPirateMode: isPirateMode)
                    ]
                )

                guideSection(
                    title: settingsCopy("3. Add a key only when needed", pirate: "3. Add a key only when needed", isPirateMode: isPirateMode),
                    lines: [
                        settingsCopy("Hosted cloud models usually need an API key stored in Keychain.", pirate: "Hosted cloud models usually need an API key stored in Keychain.", isPirateMode: isPirateMode),
                        settingsCopy("Local Ollama setups do not need a key.", pirate: "Local Ollama setups do not need a key.", isPirateMode: isPirateMode),
                        settingsCopy("LM Studio or another local proxy may or may not require a token.", pirate: "LM Studio or another local proxy may or may not require a token.", isPirateMode: isPirateMode)
                    ]
                )

                guideSection(
                    title: settingsCopy("4. What Anchored expects back", pirate: "4. What Anchored expects back", isPirateMode: isPirateMode),
                    lines: [
                        settingsCopy("Best case: structured JSON with a productive, distracting, or neutral label.", pirate: "Best case: structured JSON with a productive, distracting, or neutral label.", isPirateMode: isPirateMode),
                        settingsCopy("Legacy yes / no replies still work, but free-form prose does not.", pirate: "Legacy yes / no replies still work, but free-form prose does not.", isPirateMode: isPirateMode),
                        settingsCopy("Cloud results never override explicit app or domain rules.", pirate: "Cloud results never override explicit app or domain rules.", isPirateMode: isPirateMode)
                    ]
                )
            }
            .padding(16)
        }
        .frame(width: 370, height: 320)
    }

    @ViewBuilder
    private func guideSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(SettingsTheme.textPrimary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(SettingsTheme.accent)
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(SettingsTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - General Settings

struct GeneralSettingsPane: View {
    let isPirateMode: Bool
    @Binding var scrollTarget: SettingsScrollTarget?
    @StateObject private var prefs = PreferencesManager.shared
    @ObservedObject private var langManager = LanguageManager.shared

    private let thresholds: [(Double, String)] = [
        (300.0, "5 min"), (600.0, "10 min"), (900.0, "15 min"), (1800.0, "30 min")
    ]
    private let countdowns = [5, 10, 15, 20, 30]

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
            return "\(mins)m"
        }

        return "\(mins)m \(secs)s"
    }

    private var scheduleReferenceDate: Date {
        var components = DateComponents()
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 978_307_200)
    }

    private func date(for minute: Int) -> Date {
        let clamped = max(0, min(23 * 60 + 59, minute))
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: clamped / 60,
            minute: clamped % 60,
            second: 0,
            of: scheduleReferenceDate
        ) ?? scheduleReferenceDate
    }

    private func minute(for date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func timePickerBinding(_ minuteBinding: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: { date(for: minuteBinding.wrappedValue) },
            set: { minuteBinding.wrappedValue = minute(for: $0) }
        )
    }

    var body: some View {
        SettingsPane(
            title: settingsCopy("General", pirate: "Rigging", isPirateMode: isPirateMode),
            contextLabel: settingsCopy("Applies to all profiles", pirate: "Applies to all profiles", isPirateMode: isPirateMode),
            scrollTarget: $scrollTarget
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Focus Behavior", pirate: "Voyage Behavior", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Focus Threshold", pirate: "Voyage Threshold", isPirateMode: isPirateMode),
                        description: settingsCopy("Start a focus session after continuously working for this long.", pirate: "Start a focus session after continuously workin' fer this long.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        HStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { prefs.focusThreshold },
                                set: { newValue in
                                    let rounded = (newValue / 30.0).rounded() * 30.0
                                    prefs.focusThreshold = max(30, min(3600, rounded))
                                }
                            ), in: 30...3600)
                                .frame(width: 238)
                            Text(formatDuration(prefs.focusThreshold))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }

                    SettingsRow(
                        label: settingsCopy("Distraction Warning Countdown", pirate: "Siren Warning Countdown", isPirateMode: isPirateMode),
                        description: settingsCopy("Wait this long before dimming after a distraction is detected.", pirate: "Wait this long before dimming after a distraction is detected.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        HStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(prefs.countdownDuration) },
                                set: { newValue in
                                    let rounded = Int((newValue / 5.0).rounded() * 5.0)
                                    prefs.countdownDuration = max(0, min(60, rounded))
                                }
                            ), in: 0...60)
                                .frame(width: 238)
                            Text(formatDuration(Double(prefs.countdownDuration)))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }

                    SettingsRow(
                        label: settingsCopy("Warning Pill", pirate: "Warning Pill", isPirateMode: isPirateMode),
                        description: settingsCopy("Show the floating warning pill before dimming begins.", pirate: "Show the floating warning pill before the fog rolls in.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.showCountdownPill)
                    }

                    SettingsRow(
                        label: settingsCopy("Screen Dim Level", pirate: "Siren Fog Density", isPirateMode: isPirateMode),
                        description: settingsCopy("How dark the screen gets when distraction dimming is active.", pirate: "How thick the fog rolls in when distracted.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        HStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { prefs.dimOpacity },
                                set: { newValue in
                                    let rounded = (newValue / 0.05).rounded() * 0.05
                                    prefs.dimOpacity = max(0.1, min(0.95, rounded))
                                }
                            ), in: 0.1...0.95)
                                .frame(width: 238)
                            Text(String(format: "%.0f%%", prefs.dimOpacity * 100))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }

                    SettingsRow(
                        label: settingsCopy("Dim Transition Duration", pirate: "Fog Roll-in Duration", isPirateMode: isPirateMode),
                        description: settingsCopy("How quickly the dim overlay reaches its selected level.", pirate: "How quickly the dim overlay reaches its selected level.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        HStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { prefs.dimTransitionDuration },
                                set: { newValue in
                                    let rounded = (newValue / 0.5).rounded() * 0.5
                                    prefs.dimTransitionDuration = max(0.0, min(30.0, rounded))
                                }
                            ), in: 0.0...30.0)
                                .frame(width: 238)
                            Text(prefs.dimTransitionDuration == 0 ? settingsCopy("Instant", pirate: "Poff 💨", isPirateMode: isPirateMode) : String(format: "%.1fs", prefs.dimTransitionDuration))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }
                }
            }
            .id(SettingsScrollTarget.generalFocusBehavior)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Focus Schedule", pirate: "Voyage Schedule", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Enable Schedule", pirate: "Enable Schedule", isPirateMode: isPirateMode),
                        description: settingsCopy("Automatic focus, nudges, and loop-breaking only run during these hours.", pirate: "Automatic focus, nudges, and loop-breaking only run during these hours.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.focusScheduleEnabled)
                    }

                    SettingsRow(
                        label: settingsCopy("Start Time", pirate: "Start Time", isPirateMode: isPirateMode),
                        description: settingsCopy("Focus automation can begin after this time each day.", pirate: "Focus automation can begin after this time each day.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        DatePicker(
                            "",
                            selection: timePickerBinding(Binding(
                                get: { prefs.focusScheduleStartMinute },
                                set: { prefs.focusScheduleStartMinute = $0 }
                            )),
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(!prefs.focusScheduleEnabled)
                        .opacity(prefs.focusScheduleEnabled ? 1 : 0.58)
                    }

                    SettingsRow(
                        label: settingsCopy("End Time", pirate: "End Time", isPirateMode: isPirateMode),
                        description: settingsCopy("Anchored stops automatic enforcement after this time.", pirate: "Anchored stops automatic enforcement after this time.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        DatePicker(
                            "",
                            selection: timePickerBinding(Binding(
                                get: { prefs.focusScheduleEndMinute },
                                set: { prefs.focusScheduleEndMinute = $0 }
                            )),
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(!prefs.focusScheduleEnabled)
                        .opacity(prefs.focusScheduleEnabled ? 1 : 0.58)
                    }

                    SettingsRow(
                        label: settingsCopy("Lunch Break", pirate: "Lunch Break", isPirateMode: isPirateMode),
                        description: settingsCopy("Pause automatic enforcement during lunch so the app stays out of the way.", pirate: "Pause automatic enforcement during lunch so the app stays out of the way.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.focusScheduleLunchBreakEnabled)
                            .disabled(!prefs.focusScheduleEnabled)
                            .opacity(prefs.focusScheduleEnabled ? 1 : 0.48)
                    }

                    if prefs.focusScheduleLunchBreakEnabled {
                        SettingsRow(
                            label: settingsCopy("Lunch Start", pirate: "Lunch Start", isPirateMode: isPirateMode),
                            description: settingsCopy("When the lunch pause begins.", pirate: "When the lunch pause begins.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            DatePicker(
                                "",
                                selection: timePickerBinding(Binding(
                                    get: { prefs.focusScheduleLunchStartMinute },
                                    set: { prefs.focusScheduleLunchStartMinute = $0 }
                                )),
                                displayedComponents: [.hourAndMinute]
                            )
                            .labelsHidden()
                            .frame(width: 140)
                            .disabled(!prefs.focusScheduleEnabled)
                            .opacity(prefs.focusScheduleEnabled ? 1 : 0.58)
                        }

                        SettingsRow(
                            label: settingsCopy("Lunch End", pirate: "Lunch End", isPirateMode: isPirateMode),
                            description: settingsCopy("When automatic enforcement can resume.", pirate: "When automatic enforcement can resume.", isPirateMode: isPirateMode),
                            showDivider: false
                        ) {
                            DatePicker(
                                "",
                                selection: timePickerBinding(Binding(
                                    get: { prefs.focusScheduleLunchEndMinute },
                                    set: { prefs.focusScheduleLunchEndMinute = $0 }
                                )),
                                displayedComponents: [.hourAndMinute]
                            )
                            .labelsHidden()
                            .frame(width: 140)
                            .disabled(!prefs.focusScheduleEnabled)
                            .opacity(prefs.focusScheduleEnabled ? 1 : 0.58)
                        }
                    }
                }

                Text(settingsCopy("Manual sessions still work any time. The schedule only controls automatic behavior.", pirate: "Manual voyages still work any time. The schedule only controls automatic behavior.", isPirateMode: isPirateMode))
                    .font(.system(size: 11))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.horizontal, 4)
            }
            .id(SettingsScrollTarget.generalFocusSchedule)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Doomscroll Loop Breaker", pirate: "Loop Breaker", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Loop Breaker", pirate: "Break the Loop", isPirateMode: isPirateMode),
                        description: settingsCopy("Alert you when you've been doomscrolling a distraction app outside a focus session for too long, and offer to dim the screen.", pirate: "Warn ye when ye've been doomscrollin' for too long, and offer to fog yer screen.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.enableDoomscrollLoopBreaker)
                            .disabled(prefs.commitmentLockEnabled)
                            .opacity(prefs.commitmentLockEnabled ? 0.55 : 1)
                    }

                    SettingsRow(
                        label: settingsCopy("Loop Timeout", pirate: "Scroll Timeout", isPirateMode: isPirateMode),
                        description: settingsCopy("How long you can scroll a distraction app before the loop-breaker alert appears.", pirate: "How long ye can scroll before the loop-breaker warning fires.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        HStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { prefs.doomscrollThreshold },
                                set: { newValue in
                                    let rounded = (newValue / 60.0).rounded() * 60.0
                                    prefs.doomscrollThreshold = max(60, min(3600, rounded))
                                }
                            ), in: 60...3600)
                                .frame(width: 238)
                                .disabled(!prefs.enableDoomscrollLoopBreaker)
                                .opacity(prefs.enableDoomscrollLoopBreaker ? 1 : 0.4)
                            Text(formatDuration(prefs.doomscrollThreshold))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }
                }
            }
            .id(SettingsScrollTarget.generalDoomscroll)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Session Review", pirate: "Voyage Review", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Automatic Session Duration", pirate: "Automatic Voyage Duration", isPirateMode: isPirateMode),
                        description: settingsCopy("How long an automatically started session runs. This does not change the focus threshold.", pirate: "How long an automatic voyage runs. This does not change the sailing threshold.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        HStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { prefs.automaticSessionDuration },
                                set: { newValue in
                                    let rounded = (newValue / 60.0).rounded() * 60.0
                                    prefs.automaticSessionDuration = max(60, min(7200, rounded))
                                }
                            ), in: 5 * 60...120 * 60)
                                .frame(width: 238)
                            Text(formatDuration(prefs.automaticSessionDuration))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(SettingsTheme.textSecondary)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }

                    SettingsRow(
                        label: settingsCopy("Session Summary Prompt", pirate: "Voyage Summary Prompt", isPirateMode: isPirateMode),
                        description: settingsCopy("Offer a private, skippable summary prompt when you choose Done.", pirate: "Offer a private, skippable log when ye choose Done.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.sessionSummaryPromptEnabled)
                    }

                    SettingsRow(
                        label: settingsCopy("Weekly Review Notifications", pirate: "Weekly Review Bells", isPirateMode: isPirateMode),
                        description: settingsCopy("Send a local aggregate review every Sunday at 8:00 AM when notification permission is available.", pirate: "Send a local tally every Sunday at 8:00 AM when notification permission allows.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        Toggle("", isOn: $prefs.weeklyReviewNotificationsEnabled)
                    }
                }
            }
            .id(SettingsScrollTarget.generalSessionReview)

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
            .id(SettingsScrollTarget.generalLanguageMode)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Commitment Lock", pirate: "Commitment Lock", isPirateMode: isPirateMode),
                        description: settingsCopy("Keeps launch at login and protected focus features enabled. You can always quit Anchored from the menu bar.", pirate: "Keeps launch at login and protected focus features enabled. Ye can always quit Anchored from the menu bar.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        if prefs.commitmentLockEnabled {
                            Button {
                                prefs.commitmentLockEnabled = false
                            } label: {
                                Label(settingsCopy("Unlock", pirate: "Unlock", isPirateMode: isPirateMode), systemImage: "lock.open.fill")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Toggle("", isOn: $prefs.commitmentLockEnabled)
                        }
                    }

                    SettingsRow(
                        label: settingsCopy("Launch at Login", pirate: "Launch on Ship Start", isPirateMode: isPirateMode),
                        description: settingsCopy("Automatically launch Anchored when you log in.", pirate: "Automatically start Anchored when ye boot yer Mac.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.launchAtLogin)
                            .disabled(prefs.commitmentLockEnabled)
                            .opacity(prefs.commitmentLockEnabled ? 0.55 : 1)
                    }

                    SettingsRow(
                        label: settingsCopy("Focus Alerts", pirate: "Anchor Bells", isPirateMode: isPirateMode),
                        description: settingsCopy("Show an alert when a focus session auto-starts.", pirate: "Show a warning when a focus session auto-starts.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        Toggle("", isOn: $prefs.enableSmartNudges)
                    }
                }
            }
            .id(SettingsScrollTarget.generalSystem)
        }
    }
}

// MARK: - Productivity Intelligence Settings

struct ProductivityIntelligenceSettingsPane: View {
    let isPirateMode: Bool
    @Binding var scrollTarget: SettingsScrollTarget?
    @StateObject private var prefs = PreferencesManager.shared

    @State private var apiKeyDraft: String = ""
    @State private var isEditingApiKey = false
    @State private var showCloudModelGuide = false

    private func providerName() -> String {
        switch prefs.cloudProvider {
        case 1: return "openai"
        case 2: return "anthropic"
        case 3: return "ollama"
        default: return "gemini"
        }
    }

    private func saveApiKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainHelper.deleteKey(forProvider: providerName())
            apiKeyDraft = ""
        } else {
            try? KeychainHelper.saveKey(trimmed, forProvider: providerName())
            apiKeyDraft = trimmed
        }
    }

    private func beginEditingApiKey() {
        apiKeyDraft = KeychainHelper.loadKey(forProvider: providerName()) ?? ""
        isEditingApiKey = true
    }

    private func cancelEditingApiKey() {
        apiKeyDraft = ""
        isEditingApiKey = false
    }

    private func clearApiKey() {
        try? KeychainHelper.deleteKey(forProvider: providerName())
        cancelEditingApiKey()
    }

    var body: some View {
        SettingsPane(
            title: settingsCopy("Productivity Intelligence", pirate: "Rigging Intelligence", isPirateMode: isPirateMode),
            subtitle: settingsCopy("Choose how Anchored reads the current site: local text, visual fallback, and cloud models now live together.", pirate: "Choose how Anchored reads the current site: local text, visual spyglass, and cloud winds now live together.", isPirateMode: isPirateMode),
            scrollTarget: $scrollTarget
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(settingsCopy("How the stack works", pirate: "How the stack works", isPirateMode: isPirateMode))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(SettingsTheme.textPrimary)

                        VStack(alignment: .leading, spacing: 10) {
                            intelligenceBullet(
                                title: settingsCopy("Rules first", pirate: "Rules first", isPirateMode: isPirateMode),
                                detail: settingsCopy("Explicit app and domain rules always win before any model gets a say.", pirate: "Explicit app and domain rules always win before any model gets a say.", isPirateMode: isPirateMode)
                            )
                            intelligenceBullet(
                                title: settingsCopy("Local checks", pirate: "Local checks", isPirateMode: isPirateMode),
                                detail: settingsCopy("On-device text and visual analysis can promote a neutral context without sending raw context off the Mac.", pirate: "On-deck text and visual analysis can promote a neutral context without sending raw context off the Mac.", isPirateMode: isPirateMode)
                            )
                            intelligenceBullet(
                                title: settingsCopy("Cloud checks", pirate: "Cloud checks", isPirateMode: isPirateMode),
                                detail: settingsCopy("Cloud AI is optional and can point to hosted providers or a local server like Ollama or LM Studio.", pirate: "Cloud winds are optional and can point to hosted providers or a local server like Ollama or LM Studio.", isPirateMode: isPirateMode)
                            )
                        }
                    }
                    .padding(16)
                }
                .id(SettingsScrollTarget.intelligenceOverview)

                VStack(alignment: .leading, spacing: 6) {
                    Text(settingsCopy("On-Device Checks", pirate: "On-Deck Checks", isPirateMode: isPirateMode))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SettingsTheme.textSecondary)
                        .padding(.leading, 2)

                    SettingsGroup {
                        SettingsRow(
                            label: settingsCopy("Local Productivity Check", pirate: "Local Productivity Check", isPirateMode: isPirateMode),
                            description: settingsCopy("Runs a fully on-device text scorer over the bundle ID, title, URL, and visible OCR text. Turning this on disables cloud AI. Only high-confidence productive results may promote a neutral context; blocked rules still win. Disabled by default.", pirate: "Runs a fully on-deck text scorer over the bundle, title, URL, and visible OCR text. Turning this on disables cloud AI. Only strong productive results may promote a neutral context; blocked rules still win. Off by default.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            Toggle("", isOn: $prefs.enableLocalTextClassification)
                        }

                        SettingsRow(
                            label: settingsCopy("Experimental Visual Fallback", pirate: "Experimental Visual Spyglass", isPirateMode: isPirateMode),
                            description: settingsCopy("Optional local screen analysis used only after deterministic, local-text, and cloud classification remain neutral. It can only promote a current neutral context to focus; distracting results stay advisory. Disabled by default.", pirate: "Optional local screen analysis used only after all structured checks stay neutral. It can only steer a current neutral sight to focus; distracting results stay advisory. Off by default.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            Toggle("", isOn: $prefs.enableImageClassification)
                        }

                        if prefs.enableImageClassification {
                            SettingsRow(
                                label: settingsCopy("Use SmolVLM 256M (Local VLM)", pirate: "Call SmolVLM 256M (Local VLM)", isPirateMode: isPirateMode),
                                description: settingsCopy("Queries a local SmolVLM 4-bit vision model (only 145 MB).", pirate: "Steer visual checks to local SmolVLM 4-bit model.", isPirateMode: isPirateMode),
                                showDivider: false
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
                .id(SettingsScrollTarget.intelligenceLocal)

                VStack(alignment: .leading, spacing: 6) {
                    Text(settingsCopy("Cloud Model Connection", pirate: "Cloud Model Connection", isPirateMode: isPirateMode))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SettingsTheme.textSecondary)
                        .padding(.leading, 2)

                    SettingsGroup {
                        SettingsRow(
                            label: settingsCopy("Cloud AI Productivity Check", pirate: "Cloud AI Productivity Check", isPirateMode: isPirateMode),
                            description: settingsCopy("Use cloud AI classification for high-precision focus validation. Turning this on disables the local on-device check.", pirate: "Ask the cloud winds if yer context be productive. Turning this on disables the local on-deck check.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            Toggle("", isOn: $prefs.enableCloudClassification)
                        }

                        SettingsRow(
                            label: settingsCopy("Cloud Provider", pirate: "Cloud Provider", isPirateMode: isPirateMode),
                            description: settingsCopy("Choose which cloud LLM service to query.", pirate: "Choose which cloud LLM service to query.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            Picker("", selection: $prefs.cloudProvider) {
                                Text("Gemini").tag(0)
                                Text("OpenAI").tag(1)
                                Text("Anthropic").tag(2)
                                Text("Ollama").tag(3)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                        }

                        SettingsRow(
                            label: settingsCopy("API Key", pirate: "Letters of Marque (API Key)", isPirateMode: isPirateMode),
                            description: prefs.cloudProvider == 3
                                ? settingsCopy("Ollama runs locally and does not require an API key.", pirate: "Ollama runs locally and does not require an API key.", isPirateMode: isPirateMode)
                                : settingsCopy("Stored securely in Keychain. Use Edit Key to replace or clear it.", pirate: "Stored securely in Keychain. Use Edit Key to replace or clear it.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            if prefs.cloudProvider == 3 {
                                Text(settingsCopy("No API key required.", pirate: "No API key required.", isPirateMode: isPirateMode))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(SettingsTheme.textSecondary)
                                    .frame(width: 180, alignment: .trailing)
                            } else if isEditingApiKey {
                                VStack(alignment: .trailing, spacing: 8) {
                                    SecureField("API Key", text: $apiKeyDraft, onCommit: {
                                        saveApiKey()
                                        isEditingApiKey = false
                                    })
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 180)

                                    HStack(spacing: 8) {
                                        Button(settingsCopy("Save", pirate: "Save", isPirateMode: isPirateMode)) {
                                            saveApiKey()
                                            isEditingApiKey = false
                                        }
                                        .buttonStyle(.borderless)

                                        Button(settingsCopy("Cancel", pirate: "Abandon", isPirateMode: isPirateMode), role: .cancel) {
                                            cancelEditingApiKey()
                                        }
                                        .buttonStyle(.borderless)

                                        Button(settingsCopy("Clear", pirate: "Clear", isPirateMode: isPirateMode), role: .destructive) {
                                            clearApiKey()
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            } else {
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(settingsCopy("Key stored securely.", pirate: "Key stored securely.", isPirateMode: isPirateMode))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(SettingsTheme.textSecondary)

                                    Button(settingsCopy("Edit Key", pirate: "Edit Key", isPirateMode: isPirateMode)) {
                                        beginEditingApiKey()
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        SettingsRow(
                            label: settingsCopy("Model Name", pirate: "Model Name", isPirateMode: isPirateMode),
                            description: settingsCopy("The identifier of the cloud model to use.", pirate: "The identifier of the cloud model to use.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            TextField("Model Name", text: $prefs.cloudModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }

                        SettingsRow(
                            label: settingsCopy("Endpoint URL", pirate: "Endpoint URL", isPirateMode: isPirateMode),
                            description: settingsCopy("The API base URL or custom reverse proxy endpoint.", pirate: "The API base URL or custom reverse proxy endpoint.", isPirateMode: isPirateMode),
                            showDivider: false
                        ) {
                            TextField("Endpoint URL", text: $prefs.cloudEndpoint)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 250)
                        }
                    }

                    SettingsRow(
                        label: settingsCopy("Custom Model Guide", pirate: "Custom Model Guide", isPirateMode: isPirateMode),
                        description: settingsCopy("Use the info button for setup steps for local or hosted models.", pirate: "Use the info button fer setup steps fer local or hosted models.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        Button {
                            showCloudModelGuide.toggle()
                        } label: {
                            Text("ⓘ")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(SettingsTheme.accent)
                                .frame(width: 24, height: 24)
                                .background(SettingsTheme.accent.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(settingsCopy("Show setup steps for local or hosted models", pirate: "Show setup steps for local or hosted models", isPirateMode: isPirateMode))
                        .help(settingsCopy("Show setup steps for local or hosted models", pirate: "Show setup steps for local or hosted models", isPirateMode: isPirateMode))
                        .popover(isPresented: $showCloudModelGuide, arrowEdge: .trailing) {
                            CloudModelGuidePopover(isPirateMode: isPirateMode)
                        }
                    }
                }
                .id(SettingsScrollTarget.intelligenceCloud)
            }
        }
        .onChange(of: prefs.cloudProvider) { _ in
            if isEditingApiKey {
                cancelEditingApiKey()
            }
        }
        .onDisappear {
            if isEditingApiKey {
                saveApiKey()
                isEditingApiKey = false
            }
        }
    }

    @ViewBuilder
    private func intelligenceBullet(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(SettingsTheme.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(SettingsTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Privacy & Data Settings

struct PrivacySettingsPane: View {
    let isPirateMode: Bool
    @Binding var scrollTarget: SettingsScrollTarget?
    @StateObject private var prefs = PreferencesManager.shared

    @State private var observationCount: Int?
    @State private var oldestDate: Date?
    @State private var isLoading = true
    @State private var loadError: String?

    @State private var showEnableDisclosure = false
    @State private var showDisableConfirmation = false
    @State private var showClearConfirmation = false
    @State private var isClearing = false
    @State private var feedbackCount = 0
    @State private var showClearFeedbackConfirmation = false
    @State private var isClearingFeedback = false
    @State private var showClearSummariesConfirmation = false
    @State private var isClearingSummaries = false

    private let retentionOptions = [1, 7, 30, 90, 365]

    var body: some View {
        SettingsPane(
            title: settingsCopy("Privacy & Data", pirate: "Privacy & Data", isPirateMode: isPirateMode),
            subtitle: settingsCopy("Manage locally stored activity data, retention, and privacy controls.", pirate: "Manage locally stored activity data, retention, and privacy controls.", isPirateMode: isPirateMode),
            scrollTarget: $scrollTarget
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Context History", pirate: "Context History", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Enable Context History", pirate: "Enable Context History", isPirateMode: isPirateMode),
                        description: settingsCopy("Stores sanitized app titles and URLs locally for history features. Disabled by default.", pirate: "Stores sanitized titles and routes locally. Off by default.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: Binding(
                            get: { prefs.contextHistoryEnabled },
                            set: { newValue in
                                if newValue {
                                    showEnableDisclosure = true
                                } else {
                                    showDisableConfirmation = true
                                }
                            }
                        ))
                    }

                    SettingsRow(
                        label: settingsCopy("Retention Period", pirate: "Retention Period", isPirateMode: isPirateMode),
                        description: settingsCopy("Observations older than this are automatically deleted.", pirate: "Old sights beyond this horizon are cast overboard.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        Picker("", selection: $prefs.contextHistoryRetentionDays) {
                            ForEach(retentionOptions, id: \.self) { days in
                                Text(retentionLabel(days: days)).tag(days)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                }

                if !prefs.contextHistoryEnabled {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)
                            .padding(.top, 1)
                        Text(settingsCopy("When disabled, no new context is stored. Previous observations remain until cleared or expired. Session analytics are always preserved.", pirate: "When off, no new sights are charted. Old marks stay till ye clear or they expire. Voyage analytics remain safe.", isPirateMode: isPirateMode))
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            }
            .id(SettingsScrollTarget.privacyContextHistory)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Local Storage", pirate: "Local Hold", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(settingsCopy("Loading history summary...", pirate: "Charting hold contents...", isPirateMode: isPirateMode))
                                .font(.system(size: 12))
                                .foregroundColor(SettingsTheme.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else if let error = loadError {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(SettingsTheme.bronze)
                                    .font(.system(size: 11))
                                Text(settingsCopy("Failed to load summary", pirate: "Failed to survey hold", isPirateMode: isPirateMode))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(SettingsTheme.textSecondary)
                            Button(settingsCopy("Retry", pirate: "Retry", isPirateMode: isPirateMode)) {
                                refreshStats()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else {
                    SettingsRow(
                        label: settingsCopy("Observation Count", pirate: "Observations Stowed", isPirateMode: isPirateMode),
                        description: settingsCopy("Total sanitized context snapshots stored locally.", pirate: "Total sanitized sights in the hold.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                            Text(formattedObservationCount)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(SettingsTheme.textSecondary)
                                .accessibilityLabel("Observation count \(observationCount ?? 0)")
                        }

                        SettingsRow(
                            label: settingsCopy("Oldest Record", pirate: "Oldest Mark", isPirateMode: isPirateMode),
                            description: settingsCopy("Date of the earliest retained observation.", pirate: "When the oldest mark was first charted.", isPirateMode: isPirateMode),
                            showDivider: true
                        ) {
                            Text(formattedOldestDate)
                                .font(.system(size: 12))
                                .foregroundColor(SettingsTheme.textSecondary)
                                .accessibilityLabel(oldestAccessibilityLabel)
                                .frame(maxWidth: 200, alignment: .trailing)
                                .multilineTextAlignment(.trailing)
                        }

                        SettingsRow(
                            label: settingsCopy("Clear History", pirate: "Clear History", isPirateMode: isPirateMode),
                            description: settingsCopy("Deletes all context observations. Sessions and analytics are preserved.", pirate: "Deletes all context marks. Voyages and tallies remain safe.", isPirateMode: isPirateMode),
                            showDivider: false
                        ) {
                            destructivePillButton(
                                title: settingsCopy("Clear History…", pirate: "Clear History…", isPirateMode: isPirateMode),
                                isLoading: isClearing,
                                isDisabled: (observationCount ?? 0) == 0 || isClearing
                            ) {
                                showClearConfirmation = true
                            }
                        }
                    }
                }
            }
            .id(SettingsScrollTarget.privacyLocalStorage)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Session Summaries", pirate: "Voyage Summaries", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Clear Saved Summaries", pirate: "Clear Saved Summaries", isPirateMode: isPirateMode),
                        description: settingsCopy("Deletes written session summaries while preserving session duration analytics.", pirate: "Deletes written voyage notes while preserving voyage tallies.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        destructivePillButton(
                            title: settingsCopy("Clear Summaries…", pirate: "Clear Summaries…", isPirateMode: isPirateMode),
                            isLoading: isClearingSummaries,
                            isDisabled: isClearingSummaries
                        ) {
                            showClearSummariesConfirmation = true
                        }
                    }
                }
            }
            .id(SettingsScrollTarget.privacySessionSummaries)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Classification Feedback", pirate: "Classification Feedback", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Save Corrections Locally", pirate: "Save Corrections Locally", isPirateMode: isPirateMode),
                        description: settingsCopy("Stores only coarse, privacy-safe correction data locally: normalized domain, page category, intent category, decision, and timestamp. Titles, full URLs, OCR, screenshots, and raw events are never saved.", pirate: "Stores only coarse, privacy-safe correction data locally: normalized domain, page category, intent category, decision, and timestamp. Titles, full URLs, OCR, screenshots, and raw events are never saved.", isPirateMode: isPirateMode),
                        showDivider: true
                    ) {
                        Toggle("", isOn: $prefs.classificationFeedbackEnabled)
                    }

                    SettingsRow(
                        label: settingsCopy("Interaction Summary", pirate: "Interaction Summary", isPirateMode: isPirateMode),
                        description: settingsCopy("Optional memory-only foreground and idle aggregates. Disabled by default; no typed content or event details are collected.", pirate: "Optional memory-only watch and idle tallies. Off by default; no words or raw events are collected.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        Toggle("", isOn: $prefs.interactionSummaryEnabled)
                    }
                }

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Saved Corrections", pirate: "Saved Corrections", isPirateMode: isPirateMode),
                        description: settingsCopy("Correction examples and page-scoped learning records are automatically pruned with the selected retention period.", pirate: "Correction examples and page-scoped learning records are automatically pruned with the selected retention horizon.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        HStack(spacing: 8) {
                            Text("\(feedbackCount)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(SettingsTheme.textSecondary)
                            destructivePillButton(
                                title: settingsCopy("Clear…", pirate: "Clear…", isPirateMode: isPirateMode),
                                isLoading: isClearingFeedback,
                                isDisabled: feedbackCount == 0 || isClearingFeedback
                            ) {
                                showClearFeedbackConfirmation = true
                            }
                        }
                    }
                }
            }
            .id(SettingsScrollTarget.privacyClassificationFeedback)

            VStack(alignment: .leading, spacing: 6) {
                Text(settingsCopy("Diagnostics", pirate: "Diagnostics", isPirateMode: isPirateMode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .padding(.leading, 2)

                SettingsGroup {
                    SettingsRow(
                        label: settingsCopy("Copy Diagnostic Report", pirate: "Copy Diagnostic Report", isPirateMode: isPirateMode),
                        description: settingsCopy("Copies a sanitized report to the clipboard for support.", pirate: "Copies a sanitized report to the clipboard for support.", isPirateMode: isPirateMode),
                        showDivider: false
                    ) {
                        Button(settingsCopy("Copy", pirate: "Copy", isPirateMode: isPirateMode)) {
                            copyDiagnosticReport()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .id(SettingsScrollTarget.privacyDiagnostics)
        }
        .onAppear {
            refreshStats()
            refreshFeedbackCount()
        }
        .onReceive(prefs.$contextHistoryEnabled) { _ in
            refreshStats()
        }
        .onReceive(prefs.$classificationFeedbackEnabled) { enabled in
            ClassificationFeedbackStore.shared.isEnabled = enabled
            refreshFeedbackCount()
        }
        .alert(settingsCopy("Enable Context History?", pirate: "Enable Context History?", isPirateMode: isPirateMode), isPresented: $showEnableDisclosure) {
            Button(settingsCopy("Cancel", pirate: "Abandon", isPirateMode: isPirateMode), role: .cancel) {}
            Button(settingsCopy("Enable", pirate: "Enable", isPirateMode: isPirateMode)) {
                prefs.contextHistoryEnabled = true
                ContextHistoryStore.shared.isEnabled = true
            }
        } message: {
            Text(settingsCopy("Context history stores sanitized app titles and HTTP paths (up to 1,024 chars) locally on this Mac. Credentials, query parameters, and fragments are stripped. Data never leaves this device unless Cloud AI is separately enabled. You can change retention or clear all history at any time. Session analytics are stored separately and always preserved.", pirate: "Context history stows sanitized titles and paths locally on this vessel. Secrets, queries, and fragments are scrubbed. Nothing leaves the ship unless Cloud AI is separately enabled. Ye may adjust retention or clear the hold anytime. Voyage tallies remain untouched.", isPirateMode: isPirateMode))
        }
        .alert(settingsCopy("Disable Context History?", pirate: "Disable Context History?", isPirateMode: isPirateMode), isPresented: $showDisableConfirmation) {
            Button(settingsCopy("Cancel", pirate: "Keep On", isPirateMode: isPirateMode), role: .cancel) {}
            Button(settingsCopy("Disable", pirate: "Disable", isPirateMode: isPirateMode), role: .destructive) {
                prefs.contextHistoryEnabled = false
                ContextHistoryStore.shared.isEnabled = false
            }
        } message: {
            Text(settingsCopy("No new context will be stored. Existing observations remain until cleared or expired by retention settings. Session analytics and streaks are unaffected and will be preserved.", pirate: "No new sights will be charted. Old marks remain till cleared or expired. Voyage tallies and streaks stay safe aboard.", isPirateMode: isPirateMode))
        }
        .alert(settingsCopy("Clear History?", pirate: "Clear History?", isPirateMode: isPirateMode), isPresented: $showClearConfirmation) {
            Button(settingsCopy("Cancel", pirate: "Abandon", isPirateMode: isPirateMode), role: .cancel) {}
            Button(settingsCopy("Clear History", pirate: "Clear History", isPirateMode: isPirateMode), role: .destructive) {
                performClear()
            }
        } message: {
            Text(settingsCopy("This permanently deletes all stored context observations and AI classification outcomes. This action cannot be undone. Session rows and dashboard aggregates will be preserved.", pirate: "This permanently deletes all charted sights and AI outcomes. This cannot be undone. Voyage logs and aggregates remain safe.", isPirateMode: isPirateMode))
        }
        .alert(settingsCopy("Clear Saved Corrections?", pirate: "Clear Saved Corrections?", isPirateMode: isPirateMode), isPresented: $showClearFeedbackConfirmation) {
            Button(settingsCopy("Cancel", pirate: "Abandon", isPirateMode: isPirateMode), role: .cancel) {}
            Button(settingsCopy("Clear", pirate: "Clear", isPirateMode: isPirateMode), role: .destructive) {
                performClearFeedback()
            }
        } message: {
            Text(settingsCopy("This permanently deletes locally stored correction examples. Context history and session analytics are unchanged.", pirate: "This clears stored correction examples. Context history and voyage analytics remain unchanged.", isPirateMode: isPirateMode))
        }
        .alert(settingsCopy("Clear Summaries?", pirate: "Clear Summaries?", isPirateMode: isPirateMode), isPresented: $showClearSummariesConfirmation) {
            Button(settingsCopy("Cancel", pirate: "Abandon", isPirateMode: isPirateMode), role: .cancel) {}
            Button(settingsCopy("Clear Summaries", pirate: "Clear Summaries", isPirateMode: isPirateMode), role: .destructive) {
                isClearingSummaries = true
                DispatchQueue.global(qos: .userInitiated).async {
                    try? SessionStore.shared.clearAllSessionSummaries()
                    DispatchQueue.main.async {
                        isClearingSummaries = false
                    }
                }
            }
        } message: {
            Text(settingsCopy("This permanently deletes written summaries only. Session analytics and durations remain intact.", pirate: "This deletes written notes only. Voyage tallies remain intact.", isPirateMode: isPirateMode))
        }
    }

    private func copyDiagnosticReport() {
        let header = DiagnosticReportHeader(
            generatedAt: Date(),
            appVersion: Bundle.main.anchoredVersionString,
            buildVersion: Bundle.main.anchoredBuildString,
            macOSVersion: macOSVersionString(),
            databaseMigrationVersion: "\(SQLiteDatabaseMigrations.currentVersion)",
            accessibilityPermissionGranted: AXIsProcessTrusted(),
            screenRecordingPermissionGranted: CGPreflightScreenCaptureAccess(),
            enabledSubsystems: enabledSubsystems()
        )
        _ = DiagnosticsCenter.shared.copyDiagnosticReport(header: header)
    }

    private func enabledSubsystems() -> [String] {
        var subsystems = ["engine", "timers", "workspace", "permissions"]

        if prefs.focusScheduleEnabled {
            subsystems.append("schedule")
        }
        if prefs.enableDoomscrollLoopBreaker {
            subsystems.append("doomscroll")
        }
        if prefs.enableImageClassification || prefs.enableCloudClassification || prefs.enableLocalTextClassification {
            subsystems.append("classification")
        }
        if prefs.contextHistoryEnabled || prefs.classificationFeedbackEnabled || prefs.interactionSummaryEnabled || prefs.sessionSummaryPromptEnabled || prefs.weeklyReviewNotificationsEnabled {
            subsystems.append("session")
        }

        var seen = Set<String>()
        return subsystems.filter { seen.insert($0).inserted }
    }

    private func macOSVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var formattedObservationCount: String {
        guard !isLoading, let observationCount else {
            return "—"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        return formatter.string(from: NSNumber(value: observationCount)) ?? "\(observationCount)"
    }

    private var formattedOldestDate: String {
        guard let date = oldestDate else {
            if (observationCount ?? 0) == 0 {
                return settingsCopy("No history", pirate: "No history", isPirateMode: isPirateMode)
            }
            return settingsCopy("Unknown", pirate: "Unknown", isPirateMode: isPirateMode)
        }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var oldestAccessibilityLabel: String {
        if oldestDate != nil {
            return "Oldest record \(formattedOldestDate)"
        }
        return "No history"
    }

    private func retentionLabel(days: Int) -> String {
        switch days {
        case 1: return settingsCopy("1 day", pirate: "1 day", isPirateMode: isPirateMode)
        case 7: return settingsCopy("7 days", pirate: "7 days", isPirateMode: isPirateMode)
        case 30: return settingsCopy("30 days", pirate: "30 days", isPirateMode: isPirateMode)
        case 90: return settingsCopy("90 days", pirate: "90 days", isPirateMode: isPirateMode)
        case 365: return settingsCopy("1 year", pirate: "1 year", isPirateMode: isPirateMode)
        default: return "\(days) days"
        }
    }

    private func refreshStats() {
        isLoading = true
        loadError = nil
        let store = ContextHistoryStore.shared
        store.observationCount { result in
            switch result {
            case .success(let count):
                self.observationCount = count
                if count == 0 {
                    self.oldestDate = nil
                    self.isLoading = false
                } else {
                    store.oldestObservationDate { dateResult in
                        switch dateResult {
                        case .success(let date):
                            self.oldestDate = date
                            self.isLoading = false
                        case .failure(let error):
                            self.loadError = error.localizedDescription
                            self.isLoading = false
                        }
                    }
                }
            case .failure(let error):
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func performClear() {
        isClearing = true
        ContextHistoryStore.shared.clearAll { _ in
            ClassificationOutcomeStore.shared.clearAll { _ in
                DispatchQueue.main.async {
                    self.isClearing = false
                    self.refreshStats()
                }
            }
        }
    }

    private func refreshFeedbackCount() {
        ClassificationFeedbackStore.shared.count { result in
            if case .success(let count) = result {
                feedbackCount = count
            }
        }
    }

    @ViewBuilder
    private func destructivePillButton(
        title: String,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: .destructive, action: action) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
                    .frame(width: 14, height: 14)
            } else {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(5)
            }
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }

    private func performClearFeedback() {
        isClearingFeedback = true
        ClassificationFeedbackStore.shared.clearAll { _ in
            DispatchQueue.main.async {
                isClearingFeedback = false
                refreshFeedbackCount()
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
    @Binding var scrollTarget: SettingsScrollTarget?

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
        SettingsPane(title: "\(profile.name) Profile", scrollTarget: $scrollTarget) {
            VStack(alignment: .leading, spacing: 6) {
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
            }
            .id(SettingsScrollTarget.profileOverview)

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
            .id(SettingsScrollTarget.profileAllowedApps)

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
                    .id(SettingsScrollTarget.profileAllowedSuggestions)
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
            .id(SettingsScrollTarget.profileDistractionApps)

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
    @State private var appBreakdownState: Loadable<[(String, TimeInterval)]> = .idle
    @State private var requestGeneration: Int = 0
    @StateObject private var vm = MenuBarViewModel(focusEngine: FocusEngine(
        activityMonitor: AppSwitchMonitor(),
        distractionListManager: DistractionListManager.shared
    ))

    private var totalDuration: TimeInterval {
        appBreakdown.map(\.1).reduce(0, +)
    }

    var body: some View {
        SettingsPane(title: "Analytics") {
            VStack(alignment: .leading, spacing: 28) {
                TidalWaveChartView()
                FleetTreeSpreadmapView()
                ConstellationHeatmapView()

                VStack(alignment: .leading, spacing: 8) {
                    Text(settingsCopy("Time by App", pirate: "Sailing Time by Port", isPirateMode: isPirateMode))
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundColor(SettingsTheme.accent)
                        .padding(.leading, 4)

                    Group {
                        switch appBreakdownState {
                        case .idle, .loading:
                            HStack(spacing: 8) {
                                ProgressView().tint(SettingsTheme.accent)
                                Text("Loading...")
                                    .font(.system(size: 11))
                                    .foregroundColor(SettingsTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                        case .failed(let message):
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Failed to load")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundColor(SettingsTheme.textSecondary)
                            }
                        case .empty:
                            emptyState(settingsCopy("No logs recorded yet.", pirate: "No logs recorded yet.", isPirateMode: isPirateMode))
                        case .loaded:
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
                    }
                }

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
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        let generation = requestGeneration &+ 1
        requestGeneration = generation
        appBreakdownState = .loading
        vm.refresh()
        DispatchQueue.global(qos: .userInitiated).async {
            let breakdown = SessionStore.shared.getAppBreakdown()
            let sorted = breakdown.sorted { $0.1 > $1.1 }.map { ($0.key, $0.value) }
            DispatchQueue.main.async {
                guard generation == requestGeneration else { return }
                appBreakdown = sorted
                appBreakdownState = sorted.isEmpty ? .empty : .loaded(sorted)
            }
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

// MARK: - Analytics

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
    let onCheckForUpdates: (() -> Void)?
    @Binding var scrollTarget: SettingsScrollTarget?
    var body: some View {
        let versionLabel = "Version \(Bundle.main.anchoredVersionString) (Build \(Bundle.main.anchoredBuildString))"
        SettingsPane(
            title: settingsCopy("About", pirate: "Crew Info", isPirateMode: isPirateMode),
            scrollTarget: $scrollTarget
        ) {
            HStack(spacing: 20) {
                Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Anchored")
                        .font(.system(size: 16, weight: .semibold))
                    Text(settingsCopy(versionLabel, pirate: versionLabel, isPirateMode: isPirateMode))
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
            .id(SettingsScrollTarget.aboutOverview)

            SettingsGroup {
                SettingsRow(label: settingsCopy("Check for Updates", pirate: "Scan for Upgrades", isPirateMode: isPirateMode), showDivider: true) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button(settingsCopy("Check Now", pirate: "Scan Now", isPirateMode: isPirateMode)) {
                            onCheckForUpdates?()
                        }
                        .disabled(onCheckForUpdates == nil)
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))

                        if onCheckForUpdates == nil {
                            Text("Published release builds enable Sparkle update checks.")
                                .font(.system(size: 11))
                                .foregroundColor(SettingsTheme.textSecondary)
                        }
                    }
                }
                SettingsRow(label: settingsCopy("Privacy", pirate: "Pirate Code (Privacy)", isPirateMode: isPirateMode), showDivider: false) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.accent)
                }
            }
            .id(SettingsScrollTarget.aboutActions)

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

private extension Bundle {
    var anchoredVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var anchoredBuildString: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
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

import SwiftUI

enum SettingsScrollTarget: Hashable {
    case generalFocusBehavior
    case generalFocusSchedule
    case generalDoomscroll
    case generalSessionReview
    case generalLanguageMode
    case generalSystem
    case privacyContextHistory
    case privacyLocalStorage
    case privacySessionSummaries
    case privacyClassificationFeedback
    case privacyCloudAI
    case privacyDiagnostics
    case profileOverview
    case profileAllowedApps
    case profileAllowedSuggestions
    case profileDistractionApps
    case profileDistractionSuggestions
    case aboutOverview
    case aboutActions
}

enum SettingsSearchRoute: Hashable {
    case general(SettingsScrollTarget)
    case privacy(SettingsScrollTarget)
    case profile(SettingsScrollTarget)
    case captainsLog
    case about(SettingsScrollTarget)

    var sidebarItem: SidebarItem {
        switch self {
        case .general:
            return .general
        case .privacy:
            return .privacy
        case .profile:
            return .profile(ProfileManager.shared.activeProfile.id)
        case .captainsLog:
            return .captainsLog
        case .about:
            return .about
        }
    }

    var scrollTarget: SettingsScrollTarget? {
        switch self {
        case .general(let target), .privacy(let target), .profile(let target), .about(let target):
            return target
        case .captainsLog:
            return nil
        }
    }
}

struct SettingsSearchResult: Identifiable, Hashable {
    let id: String
    let paneTitle: String
    let sectionTitle: String
    let title: String
    let detail: String
    let aliases: [String]
    let route: SettingsSearchRoute

    func relevanceScore(for query: String) -> Int? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        let fields: [(String, Int)] = [
            (title, 0),
            (sectionTitle, 1),
            (paneTitle, 2),
            (detail, 3)
        ]

        if let directMatch = fields.compactMap({ field, baseScore -> Int? in
            let lowered = field.lowercased()
            if lowered == needle { return baseScore * 10 }
            if lowered.hasPrefix(needle) { return baseScore * 10 + 1 }
            if lowered.contains(needle) { return baseScore * 10 + 2 }
            return nil
        }).min() {
            return directMatch
        }

        if let keywordMatch = aliases.compactMap({ keyword -> Int? in
            let lowered = keyword.lowercased()
            if lowered == needle { return 40 }
            if lowered.hasPrefix(needle) { return 41 }
            if lowered.contains(needle) { return 42 }
            return nil
        }).min() {
            return keywordMatch
        }

        return nil
    }

    func matches(query: String) -> Bool {
        relevanceScore(for: query) != nil
    }

    var destinationLabel: String {
        "\(paneTitle) · \(sectionTitle)"
    }
}

struct SettingsSearchSection: Identifiable, Hashable {
    let id: String
    let title: String
    let results: [SettingsSearchResult]
}

enum SettingsSearchIndex {
    static func sections(
        query: String,
        isPirateMode: Bool,
        activeProfileName: String
    ) -> [SettingsSearchSection] {
        rankedSections(
            query: query,
            isPirateMode: isPirateMode,
            activeProfileName: activeProfileName
        )
    }

    static func results(
        query: String,
        isPirateMode: Bool,
        activeProfileName: String
    ) -> [SettingsSearchResult] {
        rankedResults(
            query: query,
            isPirateMode: isPirateMode,
            activeProfileName: activeProfileName
        )
    }

    private static func rankedSections(
        query: String,
        isPirateMode: Bool,
        activeProfileName: String
    ) -> [SettingsSearchSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let results = rankedResults(
            query: trimmed,
            isPirateMode: isPirateMode,
            activeProfileName: activeProfileName
        )

        return group(results)
    }

    private static func rankedResults(
        query: String,
        isPirateMode: Bool,
        activeProfileName: String
    ) -> [SettingsSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return allResults(
            isPirateMode: isPirateMode,
            activeProfileName: activeProfileName
        )
        .enumerated()
        .compactMap { index, result -> RankedSearchResult? in
            guard let score = result.relevanceScore(for: trimmed) else { return nil }
            return RankedSearchResult(result: result, score: score, order: index)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.order < rhs.order
        }
        .map(\.result)
    }

    private struct RankedSearchResult {
        let result: SettingsSearchResult
        let score: Int
        let order: Int
    }

    private static func group(_ results: [SettingsSearchResult]) -> [SettingsSearchSection] {
        let paneOrder = [
            "General",
            "Privacy & Data",
            "Profile",
            "Captain's Log",
            "About"
        ]

        let groupedByPane = Dictionary(grouping: results, by: { $0.paneTitle })
        return paneOrder.compactMap { paneTitle in
            guard let paneResults = groupedByPane[paneTitle], !paneResults.isEmpty else { return nil }

            return SettingsSearchSection(
                id: paneTitle,
                title: paneTitle,
                results: paneResults
            )
        }
    }

    private static func allResults(
        isPirateMode: Bool,
        activeProfileName: String
    ) -> [SettingsSearchResult] {
        let profileTitle = settingsCopy("\(activeProfileName) Profile", pirate: "\(activeProfileName) Profile", isPirateMode: isPirateMode)
        return [
            // General
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Behavior", pirate: "Voyage Behavior", isPirateMode: isPirateMode),
                title: settingsCopy("Focus Threshold", pirate: "Voyage Threshold", isPirateMode: isPirateMode),
                detail: settingsCopy("How long you must focus before the session starts.", pirate: "How long ye must sail before dropping anchor.", isPirateMode: isPirateMode),
                aliases: ["focus", "threshold", "automatic focus"],
                route: .general(.generalFocusBehavior)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Behavior", pirate: "Voyage Behavior", isPirateMode: isPirateMode),
                title: settingsCopy("Distraction Warning Countdown", pirate: "Siren Warning Countdown", isPirateMode: isPirateMode),
                detail: settingsCopy("Seconds allowed on a distraction app before the screen dims.", pirate: "Seconds on a distraction app before the fog dims yer screen.", isPirateMode: isPirateMode),
                aliases: ["countdown", "warning", "dim"],
                route: .general(.generalFocusBehavior)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Behavior", pirate: "Voyage Behavior", isPirateMode: isPirateMode),
                title: settingsCopy("Warning Pill", pirate: "Warning Pill", isPirateMode: isPirateMode),
                detail: settingsCopy("Show the floating warning pill before dimming begins.", pirate: "Show the floating warning pill before the fog rolls in.", isPirateMode: isPirateMode),
                aliases: ["pill", "countdown", "warning"],
                route: .general(.generalFocusBehavior)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Behavior", pirate: "Voyage Behavior", isPirateMode: isPirateMode),
                title: settingsCopy("Screen Dim Level", pirate: "Siren Fog Density", isPirateMode: isPirateMode),
                detail: settingsCopy("How dark the screen gets when distraction dimming is active.", pirate: "How thick the fog rolls in when distracted.", isPirateMode: isPirateMode),
                aliases: ["dim", "screen", "opacity"],
                route: .general(.generalFocusBehavior)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Behavior", pirate: "Voyage Behavior", isPirateMode: isPirateMode),
                title: settingsCopy("Dim Transition Duration", pirate: "Fog Roll-in Duration", isPirateMode: isPirateMode),
                detail: settingsCopy("The time it takes to reach full screen dimming.", pirate: "How fast the fog takes over yer screens.", isPirateMode: isPirateMode),
                aliases: ["transition", "dim", "animation"],
                route: .general(.generalFocusBehavior)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Schedule", pirate: "Voyage Schedule", isPirateMode: isPirateMode),
                title: settingsCopy("Enable Schedule", pirate: "Enable Schedule", isPirateMode: isPirateMode),
                detail: settingsCopy("Automatic focus, nudges, and loop-breaking only run during these hours.", pirate: "Automatic focus, nudges, and loop-breaking only run during these hours.", isPirateMode: isPirateMode),
                aliases: ["schedule", "hours", "automation"],
                route: .general(.generalFocusSchedule)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Schedule", pirate: "Voyage Schedule", isPirateMode: isPirateMode),
                title: settingsCopy("Start Time", pirate: "Start Time", isPirateMode: isPirateMode),
                detail: settingsCopy("Focus automation can begin after this time each day.", pirate: "Focus automation can begin after this time each day.", isPirateMode: isPirateMode),
                aliases: ["schedule", "start", "begin"],
                route: .general(.generalFocusSchedule)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Schedule", pirate: "Voyage Schedule", isPirateMode: isPirateMode),
                title: settingsCopy("End Time", pirate: "End Time", isPirateMode: isPirateMode),
                detail: settingsCopy("Anchored stops automatic enforcement after this time.", pirate: "Anchored stops automatic enforcement after this time.", isPirateMode: isPirateMode),
                aliases: ["schedule", "end", "quiet"],
                route: .general(.generalFocusSchedule)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Schedule", pirate: "Voyage Schedule", isPirateMode: isPirateMode),
                title: settingsCopy("Lunch Break", pirate: "Lunch Break", isPirateMode: isPirateMode),
                detail: settingsCopy("Pause automatic enforcement during lunch so the app stays out of the way.", pirate: "Pause automatic enforcement during lunch so the app stays out of the way.", isPirateMode: isPirateMode),
                aliases: ["schedule", "break", "lunch"],
                route: .general(.generalFocusSchedule)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Schedule", pirate: "Voyage Schedule", isPirateMode: isPirateMode),
                title: settingsCopy("Lunch Start", pirate: "Lunch Start", isPirateMode: isPirateMode),
                detail: settingsCopy("When the lunch pause begins.", pirate: "When the lunch pause begins.", isPirateMode: isPirateMode),
                aliases: ["schedule", "lunch"],
                route: .general(.generalFocusSchedule)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Focus Schedule", pirate: "Voyage Schedule", isPirateMode: isPirateMode),
                title: settingsCopy("Lunch End", pirate: "Lunch End", isPirateMode: isPirateMode),
                detail: settingsCopy("When automatic enforcement can resume.", pirate: "When automatic enforcement can resume.", isPirateMode: isPirateMode),
                aliases: ["schedule", "lunch"],
                route: .general(.generalFocusSchedule)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Doomscroll Loop Breaker", pirate: "Loop Breaker", isPirateMode: isPirateMode),
                title: settingsCopy("Loop Breaker", pirate: "Break the Loop", isPirateMode: isPirateMode),
                detail: settingsCopy("Alert you when you've been doomscrolling a distraction app outside a focus session for too long, and offer to dim the screen.", pirate: "Warn ye when ye've been doomscrollin' for too long, and offer to fog yer screen.", isPirateMode: isPirateMode),
                aliases: ["doomscroll", "break", "loop"],
                route: .general(.generalDoomscroll)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Doomscroll Loop Breaker", pirate: "Loop Breaker", isPirateMode: isPirateMode),
                title: settingsCopy("Loop Timeout", pirate: "Scroll Timeout", isPirateMode: isPirateMode),
                detail: settingsCopy("How long you can scroll a distraction app before the loop-breaker alert appears.", pirate: "How long ye can scroll before the loop-breaker warning fires.", isPirateMode: isPirateMode),
                aliases: ["doomscroll", "timeout", "threshold"],
                route: .general(.generalDoomscroll)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Session Review", pirate: "Voyage Review", isPirateMode: isPirateMode),
                title: settingsCopy("Automatic Session Duration", pirate: "Automatic Voyage Duration", isPirateMode: isPirateMode),
                detail: settingsCopy("How long an automatically started session runs. This does not change the focus threshold.", pirate: "How long an automatic voyage runs. This does not change the sailing threshold.", isPirateMode: isPirateMode),
                aliases: ["session", "duration", "break"],
                route: .general(.generalSessionReview)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Session Review", pirate: "Voyage Review", isPirateMode: isPirateMode),
                title: settingsCopy("Session Summary Prompt", pirate: "Voyage Summary Prompt", isPirateMode: isPirateMode),
                detail: settingsCopy("Offer a private, skippable summary prompt when you choose Done.", pirate: "Offer a private, skippable log when ye choose Done.", isPirateMode: isPirateMode),
                aliases: ["summary", "session", "review"],
                route: .general(.generalSessionReview)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Session Review", pirate: "Voyage Review", isPirateMode: isPirateMode),
                title: settingsCopy("Weekly Review Notifications", pirate: "Weekly Review Bells", isPirateMode: isPirateMode),
                detail: settingsCopy("Send a local aggregate review every Sunday at 8:00 AM when notification permission is available.", pirate: "Send a local tally every Sunday at 8:00 AM when notification permission allows.", isPirateMode: isPirateMode),
                aliases: ["notification", "weekly", "review"],
                route: .general(.generalSessionReview)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Language & Mode", pirate: "Tongue & Navigation", isPirateMode: isPirateMode),
                title: settingsCopy("Ship Language", pirate: "Ship's Tongue", isPirateMode: isPirateMode),
                detail: settingsCopy("The language used throughout the app.", pirate: "The tongue spoken across yer ship.", isPirateMode: isPirateMode),
                aliases: ["language", "locale", "translation"],
                route: .general(.generalLanguageMode)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("Language & Mode", pirate: "Tongue & Navigation", isPirateMode: isPirateMode),
                title: settingsCopy("Tone", pirate: "Voyage Path", isPirateMode: isPirateMode),
                detail: settingsCopy("Choose pirate speech or standard mode.", pirate: "Choose the fun pirate route or the boring side.", isPirateMode: isPirateMode),
                aliases: ["mode", "pirate", "standard"],
                route: .general(.generalLanguageMode)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Commitment Lock", pirate: "Commitment Lock", isPirateMode: isPirateMode),
                detail: settingsCopy("Keeps launch at login and protected focus features enabled. You can always quit Anchored from the menu bar.", pirate: "Keeps launch at login and protected focus features enabled. Ye can always quit Anchored from the menu bar.", isPirateMode: isPirateMode),
                aliases: ["lock", "commitment", "quit"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Launch at Login", pirate: "Launch on Ship Start", isPirateMode: isPirateMode),
                detail: settingsCopy("Automatically launch Anchored when you log in.", pirate: "Automatically start Anchored when ye boot yer Mac.", isPirateMode: isPirateMode),
                aliases: ["launch", "login", "startup"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Focus Alerts", pirate: "Anchor Bells", isPirateMode: isPirateMode),
                detail: settingsCopy("Show an alert when a focus session auto-starts.", pirate: "Show a warning when a focus session auto-starts.", isPirateMode: isPirateMode),
                aliases: ["alert", "notification", "focus"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Experimental Visual Fallback", pirate: "Experimental Visual Spyglass", isPirateMode: isPirateMode),
                detail: settingsCopy("Optional local screen analysis used only after deterministic, local-text, and cloud classification remain neutral. It can only promote a current neutral context to focus; distracting results stay advisory. Disabled by default.", pirate: "Optional local screen analysis used only after all structured checks stay neutral. It can only steer a current neutral sight to focus; distracting results stay advisory. Off by default.", isPirateMode: isPirateMode),
                aliases: ["visual", "screen", "fallback"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Use SmolVLM 256M (Local VLM)", pirate: "Call SmolVLM 256M (Local VLM)", isPirateMode: isPirateMode),
                detail: settingsCopy("Queries a local SmolVLM 4-bit vision model (only 145 MB).", pirate: "Steer visual checks to local SmolVLM 4-bit model.", isPirateMode: isPirateMode),
                aliases: ["smolvlm", "local", "vision"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Local Productivity Check", pirate: "Local Productivity Check", isPirateMode: isPirateMode),
                detail: settingsCopy("Runs a fully on-device text scorer over the bundle ID, title, URL, and visible OCR text. Turning this on disables cloud AI. Only high-confidence productive results may promote a neutral context; blocked rules still win. Disabled by default.", pirate: "Runs a fully on-deck text scorer over the bundle, title, URL, and visible OCR text. Turning this on disables cloud AI. Only strong productive results may clear a neutral sight; blocked rules still win. Off by default.", isPirateMode: isPirateMode),
                aliases: ["local", "text", "productivity"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Cloud AI Productivity Check", pirate: "Cloud AI Productivity Check", isPirateMode: isPirateMode),
                detail: settingsCopy("Use cloud AI classification for high-precision focus validation. Turning this on disables the local on-device check.", pirate: "Ask the cloud winds if yer context be productive. Turning this on disables the local on-deck check.", isPirateMode: isPirateMode),
                aliases: ["cloud", "ai", "classification"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Cloud Provider", pirate: "Cloud Provider", isPirateMode: isPirateMode),
                detail: settingsCopy("Choose which cloud LLM service to query.", pirate: "Choose which cloud LLM service to query.", isPirateMode: isPirateMode),
                aliases: ["cloud", "provider", "model"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("API Key", pirate: "Letters of Marque (API Key)", isPirateMode: isPirateMode),
                detail: settingsCopy("Enter your personal API key. Stored securely in Keychain.", pirate: "Enter your personal API key. Stored securely in Keychain.", isPirateMode: isPirateMode),
                aliases: ["key", "api", "cloud"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Model Name", pirate: "Model Name", isPirateMode: isPirateMode),
                detail: settingsCopy("The identifier of the cloud model to use.", pirate: "The identifier of the cloud model to use.", isPirateMode: isPirateMode),
                aliases: ["model", "cloud"],
                route: .general(.generalSystem)
            ),
            result(
                paneTitle: "General",
                sectionTitle: settingsCopy("System", pirate: "Ship Deck", isPirateMode: isPirateMode),
                title: settingsCopy("Endpoint URL", pirate: "Endpoint URL", isPirateMode: isPirateMode),
                detail: settingsCopy("The API base URL or custom reverse proxy endpoint.", pirate: "The API base URL or custom reverse proxy endpoint.", isPirateMode: isPirateMode),
                aliases: ["endpoint", "url", "cloud"],
                route: .general(.generalSystem)
            ),

            // Privacy
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Context History", pirate: "Context History", isPirateMode: isPirateMode),
                title: settingsCopy("Enable Context History", pirate: "Enable Context History", isPirateMode: isPirateMode),
                detail: settingsCopy("Stores sanitized app titles and URLs locally for history features. Disabled by default.", pirate: "Stores sanitized titles and routes locally. Off by default.", isPirateMode: isPirateMode),
                aliases: ["privacy", "history", "context"],
                route: .privacy(.privacyContextHistory)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Context History", pirate: "Context History", isPirateMode: isPirateMode),
                title: settingsCopy("Retention Period", pirate: "Retention Period", isPirateMode: isPirateMode),
                detail: settingsCopy("Observations older than this are automatically deleted.", pirate: "Old sights beyond this horizon are cast overboard.", isPirateMode: isPirateMode),
                aliases: ["history", "retention", "privacy"],
                route: .privacy(.privacyContextHistory)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Local Storage", pirate: "Local Hold", isPirateMode: isPirateMode),
                title: settingsCopy("Clear All History", pirate: "Clear All History", isPirateMode: isPirateMode),
                detail: settingsCopy("Deletes all context observations. Sessions and analytics are preserved.", pirate: "Deletes all context marks. Voyages and tallies remain safe.", isPirateMode: isPirateMode),
                aliases: ["history", "clear", "privacy"],
                route: .privacy(.privacyLocalStorage)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Session Summaries", pirate: "Voyage Summaries", isPirateMode: isPirateMode),
                title: settingsCopy("Clear Saved Summaries", pirate: "Clear Saved Summaries", isPirateMode: isPirateMode),
                detail: settingsCopy("Deletes written session summaries while preserving session duration analytics.", pirate: "Deletes written voyage notes while preserving voyage tallies.", isPirateMode: isPirateMode),
                aliases: ["summary", "history", "privacy"],
                route: .privacy(.privacySessionSummaries)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Classification Feedback", pirate: "Classification Feedback", isPirateMode: isPirateMode),
                title: settingsCopy("Save Corrections Locally", pirate: "Save Corrections Locally", isPirateMode: isPirateMode),
                detail: settingsCopy("Stores only app IDs, domains, labels, and correction types. Titles, full URLs, OCR, screenshots, and raw events are never stored.", pirate: "Stores only safe labels and routes. No titles, full URLs, sights, or raw events are kept.", isPirateMode: isPirateMode),
                aliases: ["feedback", "corrections", "privacy"],
                route: .privacy(.privacyClassificationFeedback)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Classification Feedback", pirate: "Classification Feedback", isPirateMode: isPirateMode),
                title: settingsCopy("Interaction Summary", pirate: "Interaction Summary", isPirateMode: isPirateMode),
                detail: settingsCopy("Optional memory-only foreground and idle aggregates. Disabled by default; no typed content or event details are collected.", pirate: "Optional memory-only watch and idle tallies. Off by default; no words or raw events are collected.", isPirateMode: isPirateMode),
                aliases: ["analytics", "summary", "privacy"],
                route: .privacy(.privacyClassificationFeedback)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Classification Feedback", pirate: "Classification Feedback", isPirateMode: isPirateMode),
                title: settingsCopy("Saved Corrections", pirate: "Saved Corrections", isPirateMode: isPirateMode),
                detail: settingsCopy("Correction examples are automatically pruned with the selected retention period.", pirate: "Correction examples follow the selected retention horizon.", isPirateMode: isPirateMode),
                aliases: ["corrections", "feedback", "privacy"],
                route: .privacy(.privacyClassificationFeedback)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Cloud AI", pirate: "Cloud Winds", isPirateMode: isPirateMode),
                title: settingsCopy("Cloud AI Productivity Check", pirate: "Cloud AI Productivity Check", isPirateMode: isPirateMode),
                detail: settingsCopy("When enabled, context may be sent to your selected cloud provider for classification. Disable to keep all analysis on-device.", pirate: "When on, context may be sent to cloud winds. Keep off for local-only analysis.", isPirateMode: isPirateMode),
                aliases: ["cloud", "ai", "privacy"],
                route: .privacy(.privacyCloudAI)
            ),
            result(
                paneTitle: "Privacy & Data",
                sectionTitle: settingsCopy("Diagnostics", pirate: "Diagnostics", isPirateMode: isPirateMode),
                title: settingsCopy("Copy Diagnostic Report", pirate: "Copy Diagnostic Report", isPirateMode: isPirateMode),
                detail: settingsCopy("Copies a sanitized report to the clipboard for support.", pirate: "Copies a sanitized report to the clipboard for support.", isPirateMode: isPirateMode),
                aliases: ["diagnostic", "report", "copy", "clipboard"],
                route: .privacy(.privacyDiagnostics)
            ),

            // Profile
            result(
                paneTitle: "Profile",
                sectionTitle: profileTitle,
                title: settingsCopy("Profile Name", pirate: "Profile Name", isPirateMode: isPirateMode),
                detail: settingsCopy("Rename the active work profile.", pirate: "Rename the active work profile.", isPirateMode: isPirateMode),
                aliases: ["profile", "name"],
                route: .profile(.profileOverview)
            ),
            result(
                paneTitle: "Profile",
                sectionTitle: profileTitle,
                title: settingsCopy("Allowed Apps", pirate: "Allowed Apps", isPirateMode: isPirateMode),
                detail: settingsCopy("Explicitly permitted apps for this profile.", pirate: "Explicitly permitted apps for this profile.", isPirateMode: isPirateMode),
                aliases: ["profile", "allowed", "work"],
                route: .profile(.profileAllowedApps)
            ),
            result(
                paneTitle: "Profile",
                sectionTitle: profileTitle,
                title: settingsCopy("Suggested Apps", pirate: "Suggested Apps", isPirateMode: isPirateMode),
                detail: settingsCopy("Apps that can be added to the allowed list.", pirate: "Apps that can be added to the allowed list.", isPirateMode: isPirateMode),
                aliases: ["profile", "suggested", "allowed"],
                route: .profile(.profileAllowedApps)
            ),
            result(
                paneTitle: "Profile",
                sectionTitle: profileTitle,
                title: settingsCopy("Distraction Apps", pirate: "Distraction Apps", isPirateMode: isPirateMode),
                detail: settingsCopy("Explicitly blocked apps for this profile.", pirate: "Explicitly blocked apps for this profile.", isPirateMode: isPirateMode),
                aliases: ["profile", "blocked", "distraction"],
                route: .profile(.profileDistractionApps)
            ),
            result(
                paneTitle: "Profile",
                sectionTitle: profileTitle,
                title: settingsCopy("Suggested Apps", pirate: "Suggested Apps", isPirateMode: isPirateMode),
                detail: settingsCopy("Apps that can be added to the distraction list.", pirate: "Apps that can be added to the distraction list.", isPirateMode: isPirateMode),
                aliases: ["profile", "suggested", "blocked"],
                route: .profile(.profileDistractionApps)
            ),

            // Captain's Log
            result(
                paneTitle: "Captain's Log",
                sectionTitle: settingsCopy("Analytics", pirate: "Analytics", isPirateMode: isPirateMode),
                title: settingsCopy("Captain's Log", pirate: "Captain's Log", isPirateMode: isPirateMode),
                detail: settingsCopy("Open analytics, recent sessions, and app breakdowns.", pirate: "Open analytics, recent voyages, and app breakdowns.", isPirateMode: isPirateMode),
                aliases: ["analytics", "dashboard", "logs", "reports"],
                route: .captainsLog
            ),

            // About
            result(
                paneTitle: "About",
                sectionTitle: settingsCopy("About", pirate: "Crew Info", isPirateMode: isPirateMode),
                title: settingsCopy("Version", pirate: "Version", isPirateMode: isPirateMode),
                detail: settingsCopy("App version and build information.", pirate: "App version and build information.", isPirateMode: isPirateMode),
                aliases: ["about", "version", "build"],
                route: .about(.aboutOverview)
            ),
            result(
                paneTitle: "About",
                sectionTitle: settingsCopy("About", pirate: "Crew Info", isPirateMode: isPirateMode),
                title: settingsCopy("Check for Updates", pirate: "Scan for Upgrades", isPirateMode: isPirateMode),
                detail: settingsCopy("Check whether a newer release is available.", pirate: "Check whether a newer release is available.", isPirateMode: isPirateMode),
                aliases: ["updates", "about"],
                route: .about(.aboutActions)
            ),
            result(
                paneTitle: "About",
                sectionTitle: settingsCopy("About", pirate: "Crew Info", isPirateMode: isPirateMode),
                title: settingsCopy("Privacy", pirate: "Pirate Code (Privacy)", isPirateMode: isPirateMode),
                detail: settingsCopy("Review the app privacy policy.", pirate: "Review the app privacy code.", isPirateMode: isPirateMode),
                aliases: ["privacy", "policy"],
                route: .about(.aboutActions)
            )
        ]
    }

    private static func result(
        paneTitle: String,
        sectionTitle: String,
        title: String,
        detail: String,
        aliases: [String],
        route: SettingsSearchRoute
    ) -> SettingsSearchResult {
        SettingsSearchResult(
            id: "\(paneTitle)::\(sectionTitle)::\(title)",
            paneTitle: paneTitle,
            sectionTitle: sectionTitle,
            title: title,
            detail: detail,
            aliases: aliases,
            route: route
        )
    }
}

struct SettingsSearchResultsView: View {
    let query: String
    let sections: [SettingsSearchSection]
    let onSelect: (SettingsSearchResult) -> Void

    private var themePalette: ThemePalette {
        PreferencesManager.shared.selectedThemePalette
    }

    private var accent: Color { themePalette.accentColor }
    private var textPrimary: Color { themePalette.textPrimaryColor }
    private var textSecondary: Color { themePalette.textSecondaryColor }
    private var surfaceRaised: Color { themePalette.surfaceRaisedColor }
    private var border: Color { themePalette.borderColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if sections.isEmpty {
                        noResultsView
                    } else {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader(section)

                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(section.results) { result in
                                        Button {
                                            onSelect(result)
                                        } label: {
                                            searchRow(result)
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(ControlRoomShellBackground(palette: themePalette))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ControlRoomShellBackground(palette: themePalette))
    }

    private var searchHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search Results")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(textPrimary)

                if !query.isEmpty {
                    Text("Matches for “\(query)”")
                        .font(.system(size: 12))
                        .foregroundColor(textSecondary)
                } else {
                    Text("Choose a setting to navigate to.")
                        .font(.system(size: 12))
                        .foregroundColor(textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func sectionHeader(_ section: SettingsSearchSection) -> some View {
        Text(section.title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.0)
            .foregroundColor(textSecondary)
            .textCase(.uppercase)
    }

    private var noResultsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No settings found")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(textPrimary)
            Text("No matching settings were found for “\(query)”.")
                .font(.system(size: 12))
                .foregroundColor(textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceRaised.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(border.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func searchRow(_ result: SettingsSearchResult) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(textPrimary)
                    Text(result.destinationLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(textSecondary)
                        .lineLimit(1)
                }
                Text(result.detail)
                    .font(.system(size: 11))
                    .foregroundColor(textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accent.opacity(0.8))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(surfaceRaised.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(border.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

private func settingsCopy(_ standard: String, pirate: String, isPirateMode: Bool) -> String {
    isPirateMode ? pirate : standard
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

import Foundation
import AppKit
import Combine

extension Notification.Name {
    /// Notification posted when the distraction list changes.
    public static let distractionListDidChange = Notification.Name("com.varun.Anchored.distractionListDidChange")
}

/// Manages the list of distraction application bundle identifiers, storing them in `UserDefaults`.
public final class DistractionListManager: ObservableObject {
    public static let shared = DistractionListManager()
    
    private let userDefaultsKey = "com.varun.Anchored.distractionList"
    private let defaults: UserDefaults
    private let applicationSearchRoots: [URL]
    
    // Backing set for O(1) lookups
    private var distractionSet: Set<String>
    
    /// The list of all distraction bundle IDs, exposed for UI display and observation.
    @Published public private(set) var allDistractions: [String] = []
    
    /// The default list of distraction application bundle IDs.
    public static let defaultDistractions: [String] = [
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "com.apple.MobileSMS",
        "ru.keepcoder.Telegram",
        "com.atebits.Tweetie2",
        "com.valvesoftware.steam",
        "com.spotify.client",
        "com.apple.Music"
    ]
    
    public init(defaults: UserDefaults = .standard, applicationSearchRoots: [URL]? = nil) {
        self.defaults = defaults
        self.applicationSearchRoots = applicationSearchRoots ?? Self.defaultApplicationSearchRoots()
        if let stored = defaults.stringArray(forKey: userDefaultsKey) {
            self.distractionSet = Set(stored)
            self.allDistractions = stored
        } else {
            self.distractionSet = Set(Self.defaultDistractions)
            self.allDistractions = Self.defaultDistractions
            defaults.set(Self.defaultDistractions, forKey: userDefaultsKey)
        }
    }
    
    public func isDistraction(_ bundleID: String) -> Bool {
        return distractionSet.contains(bundleID)
    }
    
    public func add(_ bundleID: String) {
        guard !distractionSet.contains(bundleID) else { return }
        distractionSet.insert(bundleID)
        allDistractions.append(bundleID)
        persist()
        notify()
    }
    
    public func remove(_ bundleID: String) {
        guard distractionSet.contains(bundleID) else { return }
        distractionSet.remove(bundleID)
        allDistractions.removeAll { $0 == bundleID }
        persist()
        notify()
    }
    
    // MARK: - App Scanner
    
    /// Scans installed apps and returns ones that look like distractions
    /// (social, entertainment, gaming, messaging) not already in the distraction list.
    public var installedSuggestions: [(bundleID: String, name: String)] {
        scanInstalledApplications(in: applicationSearchRoots)
    }

    private static func defaultApplicationSearchRoots() -> [URL] {
        [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func scanInstalledApplications(in roots: [URL]) -> [(bundleID: String, name: String)] {
        let fileManager = FileManager.default
        var discovered: [(bundleID: String, name: String)] = []
        var seen = Set<String>()
        
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "app" else { continue }
                
                let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
                guard fileManager.fileExists(atPath: infoPlistURL.path),
                      let dict = NSDictionary(contentsOf: infoPlistURL),
                      let bundleID = dict["CFBundleIdentifier"] as? String else { continue }
                
                guard bundleID != "com.varun.Anchored" else { continue }
                guard !distractionSet.contains(bundleID) else { continue }
                guard !seen.contains(bundleID) else { continue }
                
                let name = (dict["CFBundleDisplayName"] as? String)
                    ?? (dict["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                
                let category = (dict["LSApplicationCategoryType"] as? String) ?? ""
                let nameLower = name.lowercased()
                let catLower = category.lowercased()
                
                let isDistractionCategory =
                    catLower.contains("games") ||
                    catLower.contains("entertainment") ||
                    catLower.contains("social") ||
                    catLower.contains("communication") ||
                    catLower.contains("messaging") ||
                    catLower.contains("business") ||
                    catLower.contains("productivity") ||
                    catLower.contains("music") ||
                    catLower.contains("news") ||
                    catLower.contains("sports") ||
                    catLower.contains("lifestyle") ||
                    catLower.contains("shopping")
                
                let matchesKeywords =
                    nameLower.contains("discord") ||
                    nameLower.contains("slack") ||
                    nameLower.contains("telegram") ||
                    nameLower.contains("whatsapp") ||
                    nameLower.contains("signal") ||
                    nameLower.contains("messenger") ||
                    nameLower.contains("message") ||
                    nameLower.contains("messages") ||
                    nameLower.contains("chat") ||
                    nameLower.contains("teams") ||
                    nameLower.contains("zoom") ||
                    nameLower.contains("weixin") ||
                    nameLower.contains("wechat") ||
                    nameLower.contains("line") ||
                    nameLower.contains("skype") ||
                    nameLower.contains("viber") ||
                    nameLower.contains("mattermost") ||
                    nameLower.contains("zulip") ||
                    nameLower.contains("element") ||
                    nameLower.contains("wire") ||
                    nameLower.contains("threema") ||
                    nameLower.contains("kakao") ||
                    nameLower.contains("twitter") ||
                    nameLower.contains("reddit") ||
                    nameLower.contains("youtube") ||
                    nameLower.contains("netflix") ||
                    nameLower.contains("twitch") ||
                    nameLower.contains("tiktok") ||
                    nameLower.contains("instagram") ||
                    nameLower.contains("facebook") ||
                    nameLower.contains("steam") ||
                    nameLower.contains("spotify") ||
                    nameLower.contains("chess") ||
                    nameLower.contains("game") ||
                    nameLower.contains("minecraft") ||
                    nameLower.contains("clash") ||
                    nameLower.contains("fortnite") ||
                    nameLower.contains("league") ||
                    nameLower.contains("news") ||
                    nameLower.contains("feedly") ||
                    nameLower.contains("pocket")
                
                if isDistractionCategory || matchesKeywords {
                    seen.insert(bundleID)
                    discovered.append((bundleID: bundleID, name: name))
                }
                
                enumerator.skipDescendants()
            }
        }
        
        return discovered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func persist() {
        defaults.set(allDistractions, forKey: userDefaultsKey)
    }
    
    private func notify() {
        NotificationCenter.default.post(name: .distractionListDidChange, object: self)
    }
}

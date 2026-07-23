import Foundation
import Combine

extension Notification.Name {
    public static let activeProfileDidChange = Notification.Name("com.varun.Anchored.activeProfileDidChange")
    public static let profilesDidChange = Notification.Name("com.varun.Anchored.profilesDidChange")
}

public class ProfileManager: ObservableObject {
    public static let shared = ProfileManager()
    
    private let profilesKey = "com.varun.Anchored.profiles"
    private let activeProfileKey = "com.varun.Anchored.activeProfileName"
    
    private let defaults: UserDefaults
    
    @Published public var profiles: [WorkProfile] = []
    @Published public var activeProfile: WorkProfile
    
    public static var defaultProfiles: [WorkProfile] {
        let categorized = InstalledAppSuggestionProvider.shared.categorizeAllInstalledApps()
        
        let codingApps = Array(Set([
            "com.hnc.Discord",
            "com.tinyspeck.slackmacgap",
            "com.apple.MobileSMS",
            "ru.keepcoder.Telegram",
            "com.valvesoftware.steam",
            "com.spotify.client",
            "com.apple.Music"
        ].filter { DistractionListManager.defaultDistractions.contains($0) } + categorized.distractionApps)).sorted()
        
        let videoApps = Array(Set([
            "com.hnc.Discord",
            "com.apple.MobileSMS",
            "ru.keepcoder.Telegram",
            "com.valvesoftware.steam",
            "com.tinyspeck.slackmacgap"
        ].filter { DistractionListManager.defaultDistractions.contains($0) } + categorized.distractionApps)).sorted()
            .filter { $0 != "com.spotify.client" && $0 != "com.apple.Music" }
        
        let writingApps = Array(Set([
            "com.hnc.Discord",
            "com.tinyspeck.slackmacgap",
            "com.apple.MobileSMS",
            "ru.keepcoder.Telegram",
            "com.valvesoftware.steam",
            "com.spotify.client",
            "com.apple.Music"
        ].filter { DistractionListManager.defaultDistractions.contains($0) } + categorized.distractionApps)).sorted()
        
        let codingAllowed = Array(Set(["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.apple.Terminal", "com.figma.Desktop"] + categorized.codingApps))
        
        var videoAllowed = categorized.videoApps
        if videoAllowed.isEmpty {
            videoAllowed = ["com.apple.FinalCut", "com.adobe.PremierePro.24", "com.figma.Desktop"]
        }
        
        var writingAllowed = categorized.writingApps
        if writingAllowed.isEmpty {
            writingAllowed = ["com.apple.iWork.Pages", "com.microsoft.Word"]
        }
        
        return [
            WorkProfile(
                name: "Coding",
                distractionApps: codingApps,
                distractionDomains: ["youtube.com", "twitter.com", "x.com", "reddit.com", "twitch.tv", "netflix.com"],
                allowedApps: codingAllowed.sorted(),
                allowedDomains: ["github.com", "stackoverflow.com", "developer.apple.com", "docs.python.org", "npmjs.com", "crates.io", "pkg.go.dev"]
            ),
            WorkProfile(
                name: "Video",
                distractionApps: videoApps,
                distractionDomains: ["twitter.com", "x.com", "reddit.com", "netflix.com"],
                allowedApps: videoAllowed.sorted(),
                allowedDomains: ["youtube.com", "studio.youtube.com", "frame.io", "vimeo.com"]
            ),
            WorkProfile(
                name: "Writing",
                distractionApps: writingApps,
                distractionDomains: ["youtube.com", "twitter.com", "x.com", "reddit.com", "twitch.tv", "netflix.com"],
                allowedApps: writingAllowed.sorted(),
                allowedDomains: ["docs.google.com", "wikipedia.org", "scholar.google.com", "notion.so", "medium.com"]
            )
        ]
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        // Retrieve or initialize profiles
        var loadedProfiles: [WorkProfile] = []
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([WorkProfile].self, from: data) {
            loadedProfiles = decoded
        } else {
            loadedProfiles = Self.defaultProfiles
        }
        
        // Retrieve or initialize active profile
        let activeName = defaults.string(forKey: activeProfileKey) ?? "Coding"
        var foundActive = loadedProfiles.first(where: { $0.name.localizedCaseInsensitiveCompare(activeName) == .orderedSame })
            ?? loadedProfiles.first
            ?? WorkProfile(name: "Coding")
            
        var didModifyProfiles = false
        let didInitialAppScanKey = "com.varun.Anchored.didInitialAppScan"
        if !defaults.bool(forKey: didInitialAppScanKey) {
            let categorized = InstalledAppSuggestionProvider.shared.categorizeAllInstalledApps()
            
            // Merge for Coding profile
            if let codingIndex = loadedProfiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare("Coding") == .orderedSame }) {
                var profile = loadedProfiles[codingIndex]
                profile.allowedApps = Array(Set(profile.allowedApps + categorized.codingApps)).sorted()
                profile.distractionApps = Array(Set(profile.distractionApps + categorized.distractionApps)).sorted()
                loadedProfiles[codingIndex] = profile
                didModifyProfiles = true
            }
            
            // Merge for Video profile
            if let videoIndex = loadedProfiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare("Video") == .orderedSame }) {
                var profile = loadedProfiles[videoIndex]
                profile.allowedApps = Array(Set(profile.allowedApps + categorized.videoApps)).sorted()
                profile.distractionApps = Array(Set(profile.distractionApps + categorized.distractionApps)).sorted()
                loadedProfiles[videoIndex] = profile
                didModifyProfiles = true
            }
            
            // Merge for Writing profile
            if let writingIndex = loadedProfiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare("Writing") == .orderedSame }) {
                var profile = loadedProfiles[writingIndex]
                profile.allowedApps = Array(Set(profile.allowedApps + categorized.writingApps)).sorted()
                profile.distractionApps = Array(Set(profile.distractionApps + categorized.distractionApps)).sorted()
                loadedProfiles[writingIndex] = profile
                didModifyProfiles = true
            }
            
            if let activeUpdated = loadedProfiles.first(where: { $0.id == foundActive.id }) {
                foundActive = activeUpdated
            }
            
            defaults.set(true, forKey: didInitialAppScanKey)
        }
        
        // Initialize stored properties using Published wrappers to avoid initialization sequence issues
        self._profiles = Published(initialValue: loadedProfiles)
        self._activeProfile = Published(initialValue: foundActive)
        
        // If they were not persisted yet, or if we modified them, persist them now
        if defaults.data(forKey: profilesKey) == nil || didModifyProfiles {
            saveToUserDefaults()
        }
    }
    
    public func switchProfile(to name: String) {
        if let found = profiles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            activeProfile = found
            saveToUserDefaults()
            NotificationCenter.default.post(name: .activeProfileDidChange, object: self)
        }
    }
    
    public func updateProfile(_ profile: WorkProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            var activeChanged = false
            if activeProfile.id == profile.id {
                activeProfile = profile
                activeChanged = true
            }
            saveToUserDefaults()
            NotificationCenter.default.post(name: .profilesDidChange, object: self)
            if activeChanged {
                NotificationCenter.default.post(name: .activeProfileDidChange, object: self)
            }
        }
    }

    /// Applies a correction as an explicit rule and removes the opposite rule
    /// for the same target so new contradictions cannot be created.
    @discardableResult
    public func applyCorrection(
        _ correction: ClassificationCorrection,
        bundleID: String,
        url: URL?
    ) -> Bool {
        var updated = activeProfile
        var changed = false

        switch correction {
        case .allowApp, .markSessionProductive:
            if !updated.allowedApps.contains(bundleID) {
                updated.allowedApps.append(bundleID)
                changed = true
            }
            let originalCount = updated.distractionApps.count
            updated.distractionApps.removeAll { $0 == bundleID }
            changed = changed || originalCount != updated.distractionApps.count
        case .blockApp:
            if !updated.distractionApps.contains(bundleID) {
                updated.distractionApps.append(bundleID)
                changed = true
            }
            let originalCount = updated.allowedApps.count
            updated.allowedApps.removeAll { $0 == bundleID }
            changed = changed || originalCount != updated.allowedApps.count
        case .allowDomain, .blockDomain:
            guard let domain = url?.host?.lowercased(), !domain.isEmpty else { return false }
            if correction == .allowDomain {
                if !updated.allowedDomains.contains(domain) {
                    updated.allowedDomains.append(domain)
                    changed = true
                }
                let originalCount = updated.distractionDomains.count
                updated.distractionDomains.removeAll { $0 == domain }
                changed = changed || originalCount != updated.distractionDomains.count
            } else {
                if !updated.distractionDomains.contains(domain) {
                    updated.distractionDomains.append(domain)
                    changed = true
                }
                let originalCount = updated.allowedDomains.count
                updated.allowedDomains.removeAll { $0 == domain }
                changed = changed || originalCount != updated.allowedDomains.count
            }
        }

        guard changed else { return false }
        updateProfile(updated)
        return true
    }
    
    public func switchProfile(id: UUID) {
        if let found = profiles.first(where: { $0.id == id }) {
            activeProfile = found
            saveToUserDefaults()
            NotificationCenter.default.post(name: .activeProfileDidChange, object: self)
        }
    }
    
    public func addProfile(_ profile: WorkProfile) {
        guard !profiles.contains(where: { $0.id == profile.id || $0.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame }) else { return }
        profiles.append(profile)
        saveToUserDefaults()
        NotificationCenter.default.post(name: .profilesDidChange, object: self)
    }
    
    @discardableResult
    public func addProfile(name: String) -> WorkProfile {
        let newProfile = WorkProfile(name: name)
        addProfile(newProfile)
        return newProfile
    }
    
    public func deleteProfile(id: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            deleteProfile(at: index)
        }
    }
    
    public func deleteProfile(at index: Int) {
        guard index >= 0 && index < profiles.count else { return }
        let removedProfile = profiles.remove(at: index)
        var activeChanged = false
        if activeProfile.id == removedProfile.id {
            if let first = profiles.first {
                activeProfile = first
            } else {
                let defaultProfile = WorkProfile(name: "Coding")
                profiles = [defaultProfile]
                activeProfile = defaultProfile
            }
            activeChanged = true
        }
        saveToUserDefaults()
        NotificationCenter.default.post(name: .profilesDidChange, object: self)
        if activeChanged {
            NotificationCenter.default.post(name: .activeProfileDidChange, object: self)
        }
    }
    
    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            defaults.set(encoded, forKey: profilesKey)
        }
        defaults.set(activeProfile.name, forKey: activeProfileKey)
    }
}

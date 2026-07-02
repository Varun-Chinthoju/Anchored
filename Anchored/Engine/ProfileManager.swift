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
        let codingApps = [
            "com.hnc.Discord",
            "com.tinyspeck.slackmacgap",
            "com.apple.MobileSMS",
            "ru.keepcoder.Telegram",
            "com.valvesoftware.steam",
            "com.spotify.client",
            "com.apple.Music"
        ].filter { DistractionListManager.defaultDistractions.contains($0) }
        
        let videoApps = [
            "com.hnc.Discord",
            "com.apple.MobileSMS",
            "ru.keepcoder.Telegram",
            "com.valvesoftware.steam",
            "com.tinyspeck.slackmacgap"
        ].filter { DistractionListManager.defaultDistractions.contains($0) }
        
        let writingApps = [
            "com.hnc.Discord",
            "com.tinyspeck.slackmacgap",
            "com.apple.MobileSMS",
            "ru.keepcoder.Telegram",
            "com.valvesoftware.steam",
            "com.spotify.client",
            "com.apple.Music"
        ].filter { DistractionListManager.defaultDistractions.contains($0) }
        
        return [
            WorkProfile(
                name: "Coding",
                distractionApps: codingApps,
                distractionDomains: ["youtube.com", "twitter.com", "x.com", "reddit.com", "instagram.com", "tiktok.com", "facebook.com", "twitch.tv", "netflix.com"],
                allowedDomains: ["github.com", "stackoverflow.com", "developer.apple.com", "docs.python.org", "npmjs.com", "crates.io", "pkg.go.dev"]
            ),
            WorkProfile(
                name: "Video",
                distractionApps: videoApps,
                distractionDomains: ["twitter.com", "x.com", "reddit.com", "instagram.com", "tiktok.com", "facebook.com", "netflix.com"],
                allowedDomains: ["youtube.com", "studio.youtube.com", "frame.io", "vimeo.com"]
            ),
            WorkProfile(
                name: "Writing",
                distractionApps: writingApps,
                distractionDomains: ["youtube.com", "twitter.com", "x.com", "reddit.com", "instagram.com", "tiktok.com", "twitch.tv", "netflix.com"],
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
        let foundActive = loadedProfiles.first(where: { $0.name.localizedCaseInsensitiveCompare(activeName) == .orderedSame })
            ?? loadedProfiles.first
            ?? WorkProfile(name: "Coding")
        
        // Initialize stored properties using Published wrappers to avoid initialization sequence issues
        self._profiles = Published(initialValue: loadedProfiles)
        self._activeProfile = Published(initialValue: foundActive)
        
        // If they were not persisted yet, persist them now
        if defaults.data(forKey: profilesKey) == nil {
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

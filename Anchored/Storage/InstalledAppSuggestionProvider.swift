import Foundation
import AppKit

struct CategorizedApps {
    let codingApps: [String]
    let videoApps: [String]
    let writingApps: [String]
    let distractionApps: [String]
}

final class InstalledAppSuggestionProvider {
    static let shared = InstalledAppSuggestionProvider()

    private let cacheLock = NSLock()
    private var cachedDiscovered: [(bundleID: String, name: String, category: String)]?
    private var cachedCategorized: CategorizedApps?

    private init() {}
    
    // Returns installed apps that may be useful when configuring a profile.
    var installedSuggestions: [(bundleID: String, name: String)] {
        cacheLock.lock()
        if let cached = cachedDiscovered {
            cacheLock.unlock()
            return cached.map { (bundleID: $0.bundleID, name: $0.name) }
        }
        cacheLock.unlock()

        let scanned = scanInstalledApplications()

        cacheLock.lock()
        cachedDiscovered = scanned
        cacheLock.unlock()

        return scanned.map { (bundleID: $0.bundleID, name: $0.name) }
    }
    
    // Scans all installed apps and groups them by category
    func categorizeAllInstalledApps() -> CategorizedApps {
        cacheLock.lock()
        if let cached = cachedCategorized {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let categorized = computeCategorizeAllInstalledApps()

        cacheLock.lock()
        cachedCategorized = categorized
        cacheLock.unlock()

        return categorized
    }

    private func computeCategorizeAllInstalledApps() -> CategorizedApps {
        let fileManager = FileManager.default
        var coding: [String] = []
        var video: [String] = []
        var writing: [String] = []
        var distraction: [String] = []
        
        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        
        var seenBundleIDs = Set<String>()
        
        for path in searchPaths {
            let directoryURL = URL(fileURLWithPath: path)
            guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                continue
            }
            
            for url in urls where url.pathExtension == "app" {
                let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
                guard fileManager.fileExists(atPath: infoPlistURL.path),
                      let dict = NSDictionary(contentsOf: infoPlistURL) else {
                    continue
                }
                
                guard let bundleID = dict["CFBundleIdentifier"] as? String else {
                    continue
                }
                
                guard bundleID != "com.varun.Anchored" else { continue }
                guard !seenBundleIDs.contains(bundleID) else { continue }
                seenBundleIDs.insert(bundleID)
                
                let name = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                let category = (dict["LSApplicationCategoryType"] as? String) ?? ""
                
                let nameLower = name.lowercased()
                let categoryLower = category.lowercased()
                
                // 1. Distraction Check
                let isDistractionCategory = categoryLower.contains("games") ||
                                            categoryLower.contains("entertainment") ||
                                            categoryLower.contains("social") ||
                                            categoryLower.contains("communication") ||
                                            categoryLower.contains("messaging") ||
                                            categoryLower.contains("music") ||
                                            categoryLower.contains("news") ||
                                            categoryLower.contains("sports") ||
                                            categoryLower.contains("lifestyle") ||
                                            categoryLower.contains("shopping")
                
                let matchesDistractionKeywords = nameLower.contains("discord") ||
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
                
                if isDistractionCategory || matchesDistractionKeywords {
                    distraction.append(bundleID)
                    continue
                }
                
                // 2. Coding Check
                let isCodingCategory = categoryLower.contains("developer-tools")
                let matchesCodingKeywords = nameLower.contains("xcode") ||
                                            nameLower.contains("vscode") ||
                                            nameLower.contains("cursor") ||
                                            nameLower.contains("windsurf") ||
                                            nameLower.contains("zed") ||
                                            nameLower.contains("studio") ||
                                            nameLower.contains("intellij") ||
                                            nameLower.contains("rider") ||
                                            nameLower.contains("webstorm") ||
                                            nameLower.contains("clion") ||
                                            nameLower.contains("sublime") ||
                                            nameLower.contains("textmate") ||
                                            nameLower.contains("terminal") ||
                                            nameLower.contains("iterm") ||
                                            nameLower.contains("warp") ||
                                            nameLower.contains("postman") ||
                                            nameLower.contains("bruno") ||
                                            nameLower.contains("insomnia") ||
                                            nameLower.contains("antigravity") ||
                                            nameLower.contains("sourcetree") ||
                                            nameLower.contains("fork") ||
                                            nameLower.contains("github") ||
                                            nameLower.contains("eclipse") ||
                                            nameLower.contains("gitkraken") ||
                                            nameLower.contains("tower") ||
                                            nameLower.contains("copilot")
                
                if isCodingCategory || matchesCodingKeywords {
                    coding.append(bundleID)
                    continue
                }
                
                // 3. Video / Design Check
                let isVideoDesignCategory = categoryLower.contains("graphics-design") ||
                                            categoryLower.contains("video") ||
                                            categoryLower.contains("photography")
                let matchesVideoDesignKeywords = nameLower.contains("figma") ||
                                                 nameLower.contains("blender") ||
                                                 nameLower.contains("photoshop") ||
                                                 nameLower.contains("illustrator") ||
                                                 nameLower.contains("premiere") ||
                                                 nameLower.contains("after effects") ||
                                                 nameLower.contains("final cut") ||
                                                 nameLower.contains("davinci") ||
                                                 nameLower.contains("unity") ||
                                                 nameLower.contains("unreal") ||
                                                 nameLower.contains("lightroom") ||
                                                 nameLower.contains("indesign") ||
                                                 nameLower.contains("audition") ||
                                                 nameLower.contains("cinema 4d") ||
                                                 nameLower.contains("logic pro") ||
                                                 nameLower.contains("garageband") ||
                                                 nameLower.contains("imovie") ||
                                                 nameLower.contains("sketch") ||
                                                 nameLower.contains("canva")
                
                if isVideoDesignCategory || matchesVideoDesignKeywords {
                    video.append(bundleID)
                    continue
                }
                
                // 4. Writing / Productivity Check
                let isWritingCategory = categoryLower.contains("productivity") ||
                                        categoryLower.contains("business") ||
                                        categoryLower.contains("reference")
                let matchesWritingKeywords = nameLower.contains("notion") ||
                                             nameLower.contains("obsidian") ||
                                             nameLower.contains("bear") ||
                                             nameLower.contains("craft") ||
                                             nameLower.contains("drafts") ||
                                             nameLower.contains("onenote") ||
                                             nameLower.contains("pages") ||
                                             nameLower.contains("word") ||
                                             nameLower.contains("excel") ||
                                             nameLower.contains("powerpoint") ||
                                             nameLower.contains("keynote") ||
                                             nameLower.contains("numbers") ||
                                             nameLower.contains("scrivener") ||
                                             nameLower.contains("ulysses") ||
                                             nameLower.contains("evernote") ||
                                             nameLower.contains("acrobat") ||
                                             nameLower.contains("pdf")
                
                if isWritingCategory || matchesWritingKeywords {
                    writing.append(bundleID)
                    continue
                }
            }
        }
        
        return CategorizedApps(
            codingApps: coding,
            videoApps: video,
            writingApps: writing,
            distractionApps: distraction
        )
    }
    
    // Scans macOS application directories and checks Info.plists using developer categories and keywords
    private func scanInstalledApplications() -> [(bundleID: String, name: String, category: String)] {
        let fileManager = FileManager.default
        var discovered: [(String, String, String)] = []
        
        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        
        for path in searchPaths {
            let directoryURL = URL(fileURLWithPath: path)
            guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                continue
            }
            
            for url in urls where url.pathExtension == "app" {
                let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
                guard fileManager.fileExists(atPath: infoPlistURL.path),
                      let dict = NSDictionary(contentsOf: infoPlistURL) else {
                    continue
                }
                
                guard let bundleID = dict["CFBundleIdentifier"] as? String else {
                    continue
                }
                
                let name = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                
                // Exclude distraction list items and Anchored itself
                guard bundleID != "com.varun.Anchored" else { continue }
                guard !DistractionListManager.shared.isDistraction(bundleID) else { continue }
                
                let category = (dict["LSApplicationCategoryType"] as? String) ?? ""
                
                let nameLower = name.lowercased()
                let categoryLower = category.lowercased()
                
                // Standard Launch Services categories for developer and creative tools
                let isProductiveCategory = categoryLower.contains("developer-tools") ||
                                           categoryLower.contains("graphics-design") ||
                                           categoryLower.contains("video") ||
                                           categoryLower.contains("productivity") ||
                                           categoryLower.contains("photography") ||
                                           categoryLower.contains("business")
                
                // Keyword match lists for IDEs, video editors, 3D platforms, developer utilities, note taking, and music apps
                let matchesKeywords = nameLower.contains("xcode") ||
                                      nameLower.contains("vscode") ||
                                      nameLower.contains("cursor") ||
                                      nameLower.contains("windsurf") ||
                                      nameLower.contains("zed") ||
                                      nameLower.contains("studio") ||
                                      nameLower.contains("intellij") ||
                                      nameLower.contains("rider") ||
                                      nameLower.contains("webstorm") ||
                                      nameLower.contains("clion") ||
                                      nameLower.contains("sublime") ||
                                      nameLower.contains("textmate") ||
                                      nameLower.contains("terminal") ||
                                      nameLower.contains("iterm") ||
                                      nameLower.contains("warp") ||
                                      nameLower.contains("figma") ||
                                      nameLower.contains("blender") ||
                                      nameLower.contains("photoshop") ||
                                      nameLower.contains("illustrator") ||
                                      nameLower.contains("premiere") ||
                                      nameLower.contains("after effects") ||
                                      nameLower.contains("final cut") ||
                                      nameLower.contains("davinci") ||
                                      nameLower.contains("unity") ||
                                      nameLower.contains("unreal") ||
                                      nameLower.contains("notion") ||
                                      nameLower.contains("obsidian") ||
                                      nameLower.contains("bear") ||
                                      nameLower.contains("craft") ||
                                      nameLower.contains("drafts") ||
                                      nameLower.contains("onenote") ||
                                      nameLower.contains("slack") ||
                                      nameLower.contains("spotify") ||
                                      nameLower.contains("music") ||
                                      nameLower.contains("deezer") ||
                                      nameLower.contains("tidal") ||
                                      nameLower.contains("postman") ||
                                      nameLower.contains("bruno") ||
                                      nameLower.contains("insomnia") ||
                                      nameLower.contains("brave") ||
                                      nameLower.contains("chrome") ||
                                      nameLower.contains("safari") ||
                                      nameLower.contains("arc") ||
                                      nameLower.contains("firefox")
                 
                if isProductiveCategory || matchesKeywords {
                    discovered.append((bundleID, name, category))
                }
            }
        }
        
        // Remove duplicates and sort alphabetically
        var seenBundleIDs = Set<String>()
        return discovered.filter { item in
            if seenBundleIDs.contains(item.0) {
                return false
            }
            seenBundleIDs.insert(item.0)
            return true
        }.sorted(by: { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending })
    }
}

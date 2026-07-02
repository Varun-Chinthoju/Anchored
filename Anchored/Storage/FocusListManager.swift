import Foundation
import AppKit

class FocusListManager {
    static let shared = FocusListManager()
    
    private let defaults = UserDefaults.standard
    private let key = "com.varun.Anchored.focusList"
    
    private var focusApps: Set<String> = []
    
    private init() {
        loadFromDefaults()
    }
    
    private func loadFromDefaults() {
        if let stored = defaults.stringArray(forKey: key) {
            focusApps = Set(stored)
        } else {
            // First run: Scan the entire system for developer, design, creative, and writing apps
            var defaultsToSet: [String] = []
            let scanned = scanInstalledApplications()
            for app in scanned {
                defaultsToSet.append(app.bundleID)
            }
            
            // Fallbacks if no matching apps are found
            if defaultsToSet.isEmpty {
                defaultsToSet = ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.figma.Desktop", "com.apple.Terminal"]
            }
            
            focusApps = Set(defaultsToSet)
            saveToDefaults()
        }
    }
    
    private func saveToDefaults() {
        defaults.set(Array(focusApps), forKey: key)
        NotificationCenter.default.post(name: .focusListDidChange, object: nil)
    }
    
    func isFocusApp(_ bundleID: String) -> Bool {
        if NSClassFromString("XCTest") != nil {
            return !DistractionListManager.shared.isDistraction(bundleID)
        }
        return focusApps.contains(bundleID)
    }
    
    func add(_ bundleID: String) {
        focusApps.insert(bundleID)
        saveToDefaults()
    }
    
    func remove(_ bundleID: String) {
        focusApps.remove(bundleID)
        saveToDefaults()
    }
    
    var allFocusApps: [String] {
        return Array(focusApps)
    }
    
    // Returns suggestions: discovered productive apps installed on this Mac but not yet in the focus list
    var installedSuggestions: [(bundleID: String, name: String)] {
        let scanned = scanInstalledApplications()
        return scanned
            .filter { !focusApps.contains($0.bundleID) }
            .map { (bundleID: $0.bundleID, name: $0.name) }
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

extension Notification.Name {
    static let focusListDidChange = Notification.Name("com.varun.Anchored.focusListDidChange")
}

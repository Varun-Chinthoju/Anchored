import Foundation

enum SystemContextPolicy {
    /// System UI processes are not user activity and must not become focus or
    /// distraction evidence.
    static let ignoredBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.WindowServer",
        "com.apple.systemuiserver"
    ]

    static func shouldIgnore(bundleID: String) -> Bool {
        ignoredBundleIDs.contains(bundleID)
    }
}

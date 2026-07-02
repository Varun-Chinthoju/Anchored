import Foundation

public struct URLMatcher {
    /// Checks if a given URL's domain matches any domain in the list.
    /// Supports subdomain matching, e.g. "youtube.com" matches "youtube.com", "m.youtube.com", "www.youtube.com", but not "notyoutube.com".
    public static func matches(url: URL, domains: [String]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return matches(host: host, domains: domains)
    }
    
    public static func matches(host: String, domains: [String]) -> Bool {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for domain in domains {
            let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if cleanDomain.isEmpty { continue }
            if cleanHost == cleanDomain {
                return true
            }
            if cleanHost.hasSuffix("." + cleanDomain) {
                return true
            }
        }
        return false
    }
}

import Foundation

struct ContextSanitizer {
    static func sanitizeTitle(_ title: String?) -> String {
        guard let title else { return "" }

        let cleanedCharacters = title.map { character -> Character in
            if character.unicodeScalars.allSatisfy({ $0.properties.isWhitespace || $0.properties.generalCategory == .control }) {
                return " "
            }
            return character
        }

        let collapsed = String(cleanedCharacters)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(collapsed.prefix(512))
    }

    static func sanitizePersistedURL(_ url: URL?) -> String? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return nil
        }

        var sanitizedComponents = components
        sanitizedComponents.scheme = scheme
        sanitizedComponents.host = host
        sanitizedComponents.user = nil
        sanitizedComponents.password = nil
        sanitizedComponents.query = nil
        sanitizedComponents.fragment = nil

        let path = sanitizePath(sanitizedComponents.percentEncodedPath)
        sanitizedComponents.percentEncodedPath = path

        guard let sanitizedURL = sanitizedComponents.url else {
            return nil
        }

        return sanitizedURL.absoluteString
    }

    private static func sanitizePath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }

        let capped = String(path.prefix(1024))
        if capped.hasPrefix("/") {
            return capped
        }
        return "/" + capped
    }
}

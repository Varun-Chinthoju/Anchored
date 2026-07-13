import OSLog

/// Privacy-safe runtime tracing for diagnosing focus decisions in the installed app.
/// Raw URLs, titles, OCR, and typed content are intentionally excluded.
enum RuntimeTrace {
    private static let logger = Logger(subsystem: "com.varun.Anchored", category: "runtime")

    static func event(_ name: String, fields: [String: String] = [:]) {
        let payload = fields.keys.sorted().map { key in
            "\(key)=\(fields[key] ?? "")"
        }.joined(separator: " ")
        logger.info("event=\(name, privacy: .public) \(payload, privacy: .public)")
    }

    static func collectionErrorCode(_ error: CollectionError) -> String {
        switch error {
        case .timedOut: return "timedOut"
        case .permissionDenied: return "permissionDenied"
        case .execFailed: return "execFailed"
        }
    }
}

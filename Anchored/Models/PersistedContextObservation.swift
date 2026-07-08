import Foundation
import GRDB

struct PersistedContextObservation: Codable, Equatable {
    enum Source: String, Codable, CaseIterable {
        case application
        case chromium
        case safari
        case firefox
    }

    let id: UUID
    let observedAt: Date
    let bundleID: String
    let appName: String
    let source: Source
    let title: String
    let sanitizedURL: String?
    let domain: String?
    let sessionState: SessionState

    private enum CodingKeys: String, CodingKey {
        case id
        case observedAt = "timestamp"
        case bundleID
        case appName
        case source
        case title
        case sanitizedURL = "url"
        case domain
        case sessionState
    }

    init(
        id: UUID = UUID(),
        observedAt: Date = Date(),
        bundleID: String,
        appName: String,
        source: Source,
        title: String,
        sanitizedURL: String? = nil,
        domain: String? = nil,
        sessionState: SessionState = .idle
    ) {
        self.id = id
        self.observedAt = observedAt
        self.bundleID = bundleID
        self.appName = appName
        self.source = source
        self.title = title
        self.sanitizedURL = sanitizedURL
        self.domain = domain
        self.sessionState = sessionState
    }

    var identity: Identity {
        Identity(
            bundleID: bundleID,
            sanitizedURL: sanitizedURL,
            title: title
        )
    }

    func sanitizedForPersistence() -> PersistedContextObservation {
        let sanitizedURL = Self.sanitizedURL(sanitizedURL)
        return PersistedContextObservation(
            id: id,
            observedAt: observedAt,
            bundleID: bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            title: ContextSanitizer.sanitizeTitle(title),
            sanitizedURL: sanitizedURL,
            domain: Self.domain(from: sanitizedURL),
            sessionState: sessionState
        )
    }

    static func make(
        bundleID: String,
        appName: String,
        source: Source,
        title: String?,
        url: URL?,
        sessionState: SessionState,
        observedAt: Date = Date()
    ) -> PersistedContextObservation {
        PersistedContextObservation(
            observedAt: observedAt,
            bundleID: bundleID,
            appName: appName,
            source: source,
            title: title ?? "",
            sanitizedURL: ContextSanitizer.sanitizePersistedURL(url),
            domain: Self.domain(from: ContextSanitizer.sanitizePersistedURL(url)),
            sessionState: sessionState
        ).sanitizedForPersistence()
    }

    static func make(
        bundleID: String,
        appName: String,
        source: String,
        title: String?,
        url: URL?,
        sessionState: SessionState,
        observedAt: Date = Date()
    ) -> PersistedContextObservation {
        make(
            bundleID: bundleID,
            appName: appName,
            source: Source(rawValue: source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .application,
            title: title,
            url: url,
            sessionState: sessionState,
            observedAt: observedAt
        )
    }

    private static func sanitizedURL(_ url: String?) -> String? {
        guard let url else { return nil }
        return ContextSanitizer.sanitizePersistedURL(URL(string: url))
    }

    private static func domain(from url: String?) -> String? {
        guard let url,
              let components = URLComponents(string: url),
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return nil
        }
        return host
    }

    struct Identity: Equatable {
        let bundleID: String
        let sanitizedURL: String?
        let title: String
    }
}

extension PersistedContextObservation: FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "context_observations"

    init(row: Row) {
        self.id = (row["id"] as UUID?) ?? UUID()
        self.observedAt = row["timestamp"] ?? Date.distantPast
        self.bundleID = row["bundleID"] ?? ""
        self.appName = row["appName"] ?? ""
        self.source = Source(rawValue: row["source"] ?? "") ?? .application
        self.title = row["title"] ?? ""
        self.sanitizedURL = row["url"]
        self.domain = row["domain"]
        self.sessionState = SessionState(rawValue: row["sessionState"] ?? "") ?? .idle
    }
}

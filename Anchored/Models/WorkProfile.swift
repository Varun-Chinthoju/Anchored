import Foundation

public struct WorkProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var distractionApps: [String]
    public var distractionDomains: [String]
    public var allowedDomains: [String]
    
    public init(
        id: UUID = UUID(),
        name: String,
        distractionApps: [String] = [],
        distractionDomains: [String] = [],
        allowedDomains: [String] = []
    ) {
        self.id = id
        self.name = name
        self.distractionApps = distractionApps
        self.distractionDomains = distractionDomains
        self.allowedDomains = allowedDomains
    }
}

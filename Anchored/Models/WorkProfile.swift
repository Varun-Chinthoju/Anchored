import Foundation

public struct WorkProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var distractionApps: [String]
    public var distractionDomains: [String]
    public var allowedApps: [String]
    public var allowedDomains: [String]
    
    public init(
        id: UUID = UUID(),
        name: String,
        distractionApps: [String] = [],
        distractionDomains: [String] = [],
        allowedApps: [String] = [],
        allowedDomains: [String] = []
    ) {
        self.id = id
        self.name = name
        self.distractionApps = distractionApps
        self.distractionDomains = distractionDomains
        self.allowedApps = allowedApps
        self.allowedDomains = allowedDomains
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case distractionApps
        case distractionDomains
        case allowedApps
        case allowedDomains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        distractionApps = try container.decodeIfPresent([String].self, forKey: .distractionApps) ?? []
        distractionDomains = try container.decodeIfPresent([String].self, forKey: .distractionDomains) ?? []
        allowedApps = try container.decodeIfPresent([String].self, forKey: .allowedApps) ?? []
        allowedDomains = try container.decodeIfPresent([String].self, forKey: .allowedDomains) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(distractionApps, forKey: .distractionApps)
        try container.encode(distractionDomains, forKey: .distractionDomains)
        try container.encode(allowedApps, forKey: .allowedApps)
        try container.encode(allowedDomains, forKey: .allowedDomains)
    }
}

extension String {
    public func splitEmojiAndText() -> (emoji: String?, text: String) {
        guard let firstChar = self.first else { return (nil, self) }
        guard let firstScalar = firstChar.unicodeScalars.first else { return (nil, self) }
        
        let isEmoji = firstScalar.properties.isEmoji &&
                      (firstScalar.properties.isEmojiPresentation ||
                       self.first!.unicodeScalars.count > 1 ||
                       firstScalar.value >= 0x2000)
        
        if isEmoji {
            let emoji = String(firstChar)
            let remainingText = String(self.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return (emoji, remainingText)
        }
        return (nil, self)
    }
}

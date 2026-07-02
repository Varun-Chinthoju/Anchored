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

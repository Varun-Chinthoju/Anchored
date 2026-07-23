import Foundation

struct RuntimeToken: Equatable {
    let lifecycleGeneration: UInt64
    let contextGeneration: UInt64
    let sessionID: UUID?
    let profileID: UUID
    let classificationConfigurationRevision: UInt64
}


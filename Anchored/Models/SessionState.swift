import Foundation

enum SessionState: String, Codable, CaseIterable, Equatable {
    case idle
    case watching
    case anchored
}

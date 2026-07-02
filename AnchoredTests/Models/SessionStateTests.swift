import XCTest
@testable import Anchored

final class SessionStateTests: XCTestCase {
    
    func testSessionStateJSONCoding() throws {
        for state in SessionState.allCases {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            
            let data = try encoder.encode(state)
            let decodedState = try decoder.decode(SessionState.self, from: data)
            
            XCTAssertEqual(state, decodedState)
            XCTAssertEqual("\"\(state.rawValue)\"", String(data: data, encoding: .utf8))
        }
    }
}

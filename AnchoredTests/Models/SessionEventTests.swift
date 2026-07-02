import XCTest
@testable import Anchored

final class SessionEventTests: XCTestCase {
    
    func testSessionEventJSONCoding() throws {
        let event = SessionEvent(
            id: UUID(),
            timestamp: Date(),
            type: .sessionStart,
            appBundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            url: nil,
            focusDurationSeconds: 1920,
            sessionDurationSeconds: 1500,
            distractionAppBundleID: "com.hnc.Discord",
            action: .anchored
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try encoder.encode(event)
        let decodedEvent = try decoder.decode(SessionEvent.self, from: data)
        
        XCTAssertEqual(event.id, decodedEvent.id)
        XCTAssertEqual(event.timestamp.timeIntervalSince1970, decodedEvent.timestamp.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(event.type, decodedEvent.type)
        XCTAssertEqual(event.appBundleID, decodedEvent.appBundleID)
        XCTAssertEqual(event.appName, decodedEvent.appName)
        XCTAssertNil(decodedEvent.url)
        XCTAssertEqual(event.focusDurationSeconds, decodedEvent.focusDurationSeconds)
        XCTAssertEqual(event.sessionDurationSeconds, decodedEvent.sessionDurationSeconds)
        XCTAssertEqual(event.distractionAppBundleID, decodedEvent.distractionAppBundleID)
        XCTAssertEqual(event.action, decodedEvent.action)
    }
}

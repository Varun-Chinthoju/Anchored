import XCTest
@testable import Anchored

final class ContextSnapshotTests: XCTestCase {
    
    func testContextSnapshotJSONCoding() throws {
        let date = Date()
        let snapshot = ContextSnapshot(
            bundleIdentifier: "com.apple.dt.Xcode",
            localizedName: "Xcode",
            url: URL(string: "https://example.com/path"),
            title: "ContextSnapshotTests.swift",
            source: .chromium,
            observedAt: date
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(ContextSnapshot.self, from: data)
        
        XCTAssertEqual(snapshot.bundleIdentifier, decoded.bundleIdentifier)
        XCTAssertEqual(snapshot.localizedName, decoded.localizedName)
        XCTAssertEqual(snapshot.url, decoded.url)
        XCTAssertEqual(snapshot.title, decoded.title)
        XCTAssertEqual(snapshot.source, decoded.source)
        XCTAssertEqual(snapshot.observedAt.timeIntervalSince1970, decoded.observedAt.timeIntervalSince1970, accuracy: 0.001)
    }
    
    func testContextIdentityEqualityIgnoresTimestampsAndSources() {
        let date1 = Date()
        let date2 = Date().addingTimeInterval(10)
        
        let snapshot1 = ContextSnapshot(
            bundleIdentifier: "com.apple.dt.Xcode",
            localizedName: "Xcode",
            url: URL(string: "https://user:pass@Example.COM/some/path?query=1#fragment"),
            title: "  Project\n\u{000B}One\t\t\r\n",
            source: .chromium,
            observedAt: date1
        )
        
        let snapshot2 = ContextSnapshot(
            bundleIdentifier: "com.apple.dt.Xcode",
            localizedName: "Xcode",
            url: URL(string: "https://Example.COM/some/path?query=2#another"),
            title: "Project One",
            source: .safari,
            observedAt: date2
        )
        
        XCTAssertEqual(snapshot1.identity, snapshot2.identity)
        XCTAssertEqual(snapshot1.identity.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(snapshot1.identity.sanitizedURL, "https://example.com/some/path")
        XCTAssertEqual(snapshot1.identity.normalizedTitle, "Project One")
    }
    
    func testContextIdentitySanitizesURLsAndTitlesWithUnicode() {
        let title = String(repeating: "🙂", count: 600)
        let snapshot = ContextSnapshot(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            url: URL(string: "ftp://example.com/file.txt"), // non-http/https URL -> nil
            title: title,
            source: .safari
        )
        
        let identity = snapshot.identity
        XCTAssertEqual(identity.bundleID, "com.apple.Safari")
        XCTAssertNil(identity.sanitizedURL)
        XCTAssertEqual(identity.normalizedTitle.count, 512)
        XCTAssertTrue(identity.normalizedTitle.allSatisfy { $0 == "🙂" })
    }
}

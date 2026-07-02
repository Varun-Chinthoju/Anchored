import XCTest
@testable import Anchored

class URLMatcherTests: XCTestCase {
    func testExactMatch() {
        XCTAssertTrue(URLMatcher.matches(host: "youtube.com", domains: ["youtube.com"]))
        XCTAssertTrue(URLMatcher.matches(host: "YOUTUBE.COM", domains: ["youtube.com"]))
        XCTAssertTrue(URLMatcher.matches(host: "youtube.com", domains: ["YOUTUBE.COM"]))
    }
    
    func testSubdomainMatch() {
        XCTAssertTrue(URLMatcher.matches(host: "m.youtube.com", domains: ["youtube.com"]))
        XCTAssertTrue(URLMatcher.matches(host: "www.youtube.com", domains: ["youtube.com"]))
        XCTAssertTrue(URLMatcher.matches(host: "some.sub.domain.youtube.com", domains: ["youtube.com"]))
    }
    
    func testNoMatch() {
        XCTAssertFalse(URLMatcher.matches(host: "notyoutube.com", domains: ["youtube.com"]))
        XCTAssertFalse(URLMatcher.matches(host: "youtube.com.attacker.com", domains: ["youtube.com"]))
    }
    
    func testURLMatches() {
        if let url1 = URL(string: "https://m.youtube.com/watch?v=123") {
            XCTAssertTrue(URLMatcher.matches(url: url1, domains: ["youtube.com"]))
        }
        if let url2 = URL(string: "https://google.com") {
            XCTAssertFalse(URLMatcher.matches(url: url2, domains: ["youtube.com"]))
        }
    }
}

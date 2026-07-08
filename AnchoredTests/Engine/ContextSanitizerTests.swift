import XCTest
@testable import Anchored

final class ContextSanitizerTests: XCTestCase {
    func testSanitizeTitleCollapsesWhitespaceAndControlCharacters() {
        let title = "  Project\n\u{000B}One\t\t\r\n"

        XCTAssertEqual(ContextSanitizer.sanitizeTitle(title), "Project One")
    }

    func testSanitizeTitleCapsAtExtendedGraphemeBoundaries() {
        let title = String(repeating: "🙂", count: 600)

        let sanitized = ContextSanitizer.sanitizeTitle(title)

        XCTAssertEqual(sanitized.count, 512)
        XCTAssertTrue(sanitized.allSatisfy { $0 == "🙂" })
    }

    func testSanitizePersistedURLStripsCredentialsQueryAndFragment() {
        let url = URL(string: "https://user:pass@Example.COM/some/path?query=1#fragment")!

        XCTAssertEqual(
            ContextSanitizer.sanitizePersistedURL(url),
            "https://example.com/some/path"
        )
    }

    func testSanitizePersistedURLRejectsNonHttpSchemes() {
        XCTAssertNil(ContextSanitizer.sanitizePersistedURL(URL(string: "ftp://example.com/file.txt")!))
        XCTAssertNil(ContextSanitizer.sanitizePersistedURL(URL(string: "file:///tmp/test.txt")!))
    }

    func testSanitizePersistedURLCapsPath() {
        let longPath = "/" + String(repeating: "a", count: 1200)
        let url = URL(string: "https://example.com\(longPath)")!

        let sanitized = ContextSanitizer.sanitizePersistedURL(url)

        XCTAssertNotNil(sanitized)
        XCTAssertEqual(sanitized?.count, "https://example.com".count + 1024)
    }
}

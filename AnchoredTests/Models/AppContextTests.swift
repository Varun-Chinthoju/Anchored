import XCTest
@testable import Anchored

final class AppContextTests: XCTestCase {
    
    func testAppContextJSONCoding() throws {
        let context = AppContext(
            bundleIdentifier: "com.apple.dt.Xcode",
            localizedName: "Xcode",
            title: "AppContextTests.swift"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(context)
        let decodedContext = try decoder.decode(AppContext.self, from: data)
        
        XCTAssertEqual(context, decodedContext)
        XCTAssertEqual(context.bundleIdentifier, decodedContext.bundleIdentifier)
        XCTAssertEqual(context.localizedName, decodedContext.localizedName)
        XCTAssertEqual(context.title, decodedContext.title)
    }
}

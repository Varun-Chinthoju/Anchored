import XCTest
@testable import Anchored

class MockAccessibilityProvider: AccessibilityContextProviding {
    var result: AccessibilityContextProviderResult = .permissionDenied
    var calledCount = 0
    var lastBundleID: String?
    
    func context(for bundleID: String) -> AccessibilityContextProviderResult {
        calledCount += 1
        lastBundleID = bundleID
        return result
    }
}

class MockAppleEventExecutorForCollector: AppleEventExecuting {
    var completions: [(Result<String, ExecutorError>) -> Void] = []
    var executedScripts: [String] = []
    
    func execute(_ scriptSource: String, timeout: TimeInterval, completion: @escaping (Result<String, ExecutorError>) -> Void) {
        executedScripts.append(scriptSource)
        completions.append(completion)
    }
    
    func triggerAll(with result: Result<String, ExecutorError>) {
        let currentCompletions = completions
        completions.removeAll()
        for comp in currentCompletions {
            comp(result)
        }
    }
    
    func triggerAtIndex(_ index: Int, with result: Result<String, ExecutorError>) {
        if index < completions.count {
            let comp = completions.remove(at: index)
            comp(result)
        }
    }
}

final class ContextCollectorTests: XCTestCase {
    
    func testNativeAppRetrievalSuccess() {
        let mockAccessibility = MockAccessibilityProvider()
        mockAccessibility.result = .success(title: "Xcode Window", url: nil)
        
        let collector = ContextCollector(accessibilityProvider: mockAccessibility)
        let expectation = self.expectation(description: "Native app context collected")
        
        collector.collectContext(for: "com.apple.dt.Xcode") { result in
            switch result {
            case .success(let snapshot):
                XCTAssertEqual(snapshot.bundleIdentifier, "com.apple.dt.Xcode")
                XCTAssertEqual(snapshot.title, "Xcode Window")
                XCTAssertNil(snapshot.url)
                XCTAssertEqual(snapshot.source, .application)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(mockAccessibility.calledCount, 1)
        XCTAssertEqual(mockAccessibility.lastBundleID, "com.apple.dt.Xcode")
    }
    
    func testNativeAppPermissionDenied() {
        let mockAccessibility = MockAccessibilityProvider()
        mockAccessibility.result = .permissionDenied
        
        let collector = ContextCollector(accessibilityProvider: mockAccessibility)
        let expectation = self.expectation(description: "Native app fails with permission denied")
        
        collector.collectContext(for: "com.apple.dt.Xcode") { result in
            switch result {
            case .success(let snapshot):
                XCTFail("Expected failure, got success: \(snapshot)")
            case .failure(let error):
                XCTAssertEqual(error, .permissionDenied)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testBrowserRetrievalSuccess() {
        let mockExecutor = MockAppleEventExecutorForCollector()
        let mockAccessibility = MockAccessibilityProvider()
        
        let collector = ContextCollector(accessibilityProvider: mockAccessibility, executor: mockExecutor)
        let expectation = self.expectation(description: "Browser context collected")
        
        collector.collectContext(for: "com.google.Chrome") { result in
            switch result {
            case .success(let snapshot):
                XCTAssertEqual(snapshot.bundleIdentifier, "com.google.Chrome")
                XCTAssertEqual(snapshot.title, "Chrome Tab Title")
                XCTAssertEqual(snapshot.url, URL(string: "https://example.com"))
                XCTAssertEqual(snapshot.source, .chromium)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        XCTAssertEqual(mockExecutor.completions.count, 1)
        mockExecutor.triggerAll(with: .success("Chrome Tab Title\nhttps://example.com"))
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testRejectsStaleOutofOrderCallback() {
        let mockExecutor = MockAppleEventExecutorForCollector()
        let mockAccessibility = MockAccessibilityProvider()
        
        let collector = ContextCollector(accessibilityProvider: mockAccessibility, executor: mockExecutor)
        
        var firstResult: Result<ContextSnapshot, CollectionError>?
        var secondResult: Result<ContextSnapshot, CollectionError>?
        
        let exp1 = self.expectation(description: "First request ignores callback because it is stale")
        exp1.isInverted = true // We expect this block NEVER to be called because it will be discarded.
        
        let exp2 = self.expectation(description: "Second request completes successfully")
        
        // Trigger first request
        collector.collectContext(for: "com.google.Chrome") { result in
            firstResult = result
            exp1.fulfill()
        }
        
        // Trigger second request (increments generation count)
        collector.collectContext(for: "com.google.Chrome") { result in
            secondResult = result
            exp2.fulfill()
        }
        
        XCTAssertEqual(mockExecutor.completions.count, 2)
        
        // Trigger second request's completion first (index 1)
        mockExecutor.triggerAtIndex(1, with: .success("Second Title\nhttps://example2.com"))
        
        // Trigger first request's completion now (index 0)
        mockExecutor.triggerAtIndex(0, with: .success("First Title\nhttps://example1.com"))
        
        // We wait a short time to verify exp1 is indeed not fulfilled, and exp2 is.
        waitForExpectations(timeout: 0.5)
        
        XCTAssertNil(firstResult)
        XCTAssertNotNil(secondResult)
        XCTAssertEqual(try? secondResult?.get().title, "Second Title")
        XCTAssertEqual(try? secondResult?.get().url, URL(string: "https://example2.com"))
    }
}

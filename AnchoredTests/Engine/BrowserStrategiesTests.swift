import XCTest
@testable import Anchored

class MockAppleScriptExecutor: AppleScriptExecutor {
    var executeCallback: ((String) throws -> String)?
    var executedScripts: [String] = []
    
    func execute(_ source: String) throws -> String {
        executedScripts.append(source)
        if let callback = executeCallback {
            return try callback(source)
        }
        return ""
    }
}

class BrowserStrategiesTests: XCTestCase {
    
    func testChromiumBrowserStrategySuccess() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { source in
            XCTAssertTrue(source.contains("tell application \"Google Chrome\""))
            XCTAssertTrue(source.contains("return (title of active tab) & \"\\n\" & (URL of active tab)"))
            return "Google\nhttps://www.google.com"
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.title, "Google")
        XCTAssertEqual(context?.url, URL(string: "https://www.google.com"))
        XCTAssertEqual(mockExecutor.executedScripts.count, 1)
    }
    
    func testChromiumBrowserStrategyTitleWithNewlines() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _ in
            return "Google\nSearch\nEngine\nhttps://www.google.com"
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.title, "Google\nSearch\nEngine")
        XCTAssertEqual(context?.url, URL(string: "https://www.google.com"))
    }
    
    func testChromiumBrowserStrategyEmptyTitle() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _ in
            return "\nhttps://www.google.com"
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.title, "")
        XCTAssertEqual(context?.url, URL(string: "https://www.google.com"))
    }
    
    func testChromiumBrowserStrategyInsufficientParts() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _ in
            return "https://www.google.com"
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.title, "")
        XCTAssertEqual(context?.url, URL(string: "https://www.google.com"))
    }
    
    func testChromiumBrowserStrategyInvalidURL() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _ in
            return "Google\ninvalid-url-without-scheme"
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNil(context)
    }
    
    func testChromiumBrowserStrategyEmptyResult() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "company.thebrowser.Browser",
            appName: "Arc",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _ in
            return ""
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNil(context)
    }
    
    func testChromiumBrowserStrategyFailure() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.microsoft.edgemac",
            appName: "Microsoft Edge",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _ in
            throw AppleScriptError.executionFailed(code: -1708, message: "User cancelled")
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNil(context)
    }
    
    func testSafariBrowserStrategyJavaScriptSuccess() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = SafariBrowserStrategy(executor: mockExecutor)
        
        mockExecutor.executeCallback = { source in
            if source.contains("do JavaScript") {
                return "https://www.apple.com"
            }
            XCTFail("Should not fall back if JS is successful")
            return ""
        }
        
        let context = strategy.getActiveContext()
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.url, URL(string: "https://www.apple.com"))
        XCTAssertEqual(context?.title, "")
        XCTAssertEqual(mockExecutor.executedScripts.count, 1)
        XCTAssertFalse(strategy.hasTriggeredWarning)
    }
    
    class MockSafariDelegate: SafariBrowserStrategyDelegate {
        var didDetectDisabledJSCalled = false
        var detectedStrategy: SafariBrowserStrategy?
        
        func safariBrowserStrategyDidDetectDisabledJavaScriptEvents(_ strategy: SafariBrowserStrategy) {
            didDetectDisabledJSCalled = true
            detectedStrategy = strategy
        }
    }
    
    func testSafariBrowserStrategyJavaScriptDisabledFallback() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = SafariBrowserStrategy(executor: mockExecutor)
        let delegate = MockSafariDelegate()
        strategy.delegate = delegate
        
        let expectation = self.expectation(description: "Delegate and callback are triggered")
        var callbackCalled = false
        strategy.onJavaScriptEventsDisabled = {
            callbackCalled = true
            expectation.fulfill()
        }
        
        mockExecutor.executeCallback = { source in
            if source.contains("do JavaScript") {
                // Simulate JavaScript disabled error
                throw AppleScriptError.executionFailed(code: 8, message: "You must enable 'Allow JavaScript from Apple Events'...")
            } else if source.contains("return URL of current tab of window 1") {
                // Fallback returns URL
                return "https://www.apple.com/safari"
            }
            XCTFail("Unexpected script executed")
            return ""
        }
        
        let context = strategy.getActiveContext()
        
        // Wait for async dispatch
        waitForExpectations(timeout: 1.0)
        
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.url, URL(string: "https://www.apple.com/safari"))
        XCTAssertEqual(context?.title, "")
        XCTAssertTrue(delegate.didDetectDisabledJSCalled)
        XCTAssertTrue(callbackCalled)
        XCTAssertIdentical(delegate.detectedStrategy, strategy)
        XCTAssertTrue(strategy.hasTriggeredWarning)
        XCTAssertEqual(mockExecutor.executedScripts.count, 2)
    }
    
    func testSafariBrowserStrategyWarningTriggeredOnlyOnce() {
        let mockExecutor = MockAppleScriptExecutor()
        let strategy = SafariBrowserStrategy(executor: mockExecutor)
        let delegate = MockSafariDelegate()
        strategy.delegate = delegate
        
        // Pre-trigger warning
        strategy.hasTriggeredWarning = true
        
        mockExecutor.executeCallback = { source in
            if source.contains("do JavaScript") {
                throw AppleScriptError.executionFailed(code: 8, message: "Allow JavaScript from Apple Events error")
            } else {
                return "https://www.apple.com"
            }
        }
        
        let context = strategy.getActiveContext()
        
        // Give a short window to verify delegates/callbacks were NOT called again
        let runLoopExpectation = self.expectation(description: "Run loop cycle")
        DispatchQueue.main.async {
            runLoopExpectation.fulfill()
        }
        waitForExpectations(timeout: 0.5)
        
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.url, URL(string: "https://www.apple.com"))
        XCTAssertEqual(context?.title, "")
        XCTAssertFalse(delegate.didDetectDisabledJSCalled)
    }
    
    func testBrowserStrategyFactory() {
        XCTAssertNotNil(BrowserStrategyFactory.strategy(for: "com.google.Chrome"))
        XCTAssertNotNil(BrowserStrategyFactory.strategy(for: "company.thebrowser.Browser"))
        XCTAssertNotNil(BrowserStrategyFactory.strategy(for: "com.microsoft.edgemac"))
        XCTAssertNotNil(BrowserStrategyFactory.strategy(for: "com.brave.Browser"))
        XCTAssertNotNil(BrowserStrategyFactory.strategy(for: "com.apple.Safari"))
        XCTAssertNotNil(BrowserStrategyFactory.strategy(for: "org.mozilla.firefox"))
        
        XCTAssertTrue(BrowserStrategyFactory.isSupportedBrowser("com.google.Chrome"))
        XCTAssertTrue(BrowserStrategyFactory.isSupportedBrowser("com.apple.Safari"))
        XCTAssertTrue(BrowserStrategyFactory.isSupportedBrowser("org.mozilla.firefox"))
        XCTAssertFalse(BrowserStrategyFactory.isSupportedBrowser("com.example.nonexistent"))
    }
}

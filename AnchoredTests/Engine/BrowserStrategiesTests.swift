import XCTest
@testable import Anchored

class MockAppleEventExecutor: AppleEventExecuting {
    var executeCallback: ((String, TimeInterval) throws -> String)?
    var executedScripts: [String] = []
    
    func execute(_ source: String, timeout: TimeInterval, completion: @escaping (Result<String, ExecutorError>) -> Void) {
        executedScripts.append(source)
        if let callback = executeCallback {
            do {
                let result = try callback(source, timeout)
                completion(.success(result))
            } catch {
                completion(.failure(.execFailed(error.localizedDescription)))
            }
        } else {
            completion(.failure(.execFailed("No mock callback configured")))
        }
    }
}

class BrowserStrategiesTests: XCTestCase {
    
    func testChromiumBrowserStrategySuccess() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { source, timeout in
            XCTAssertTrue(source.contains("tell application \"Google Chrome\""))
            XCTAssertTrue(source.contains("return (title of active tab) & \"\\n\" & (URL of active tab)"))
            return "Google\nhttps://www.google.com"
        }
        
        let expectation = self.expectation(description: "Get active context success")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTAssertEqual(context.title, "Google")
                XCTAssertEqual(context.url, URL(string: "https://www.google.com"))
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(mockExecutor.executedScripts.count, 1)
    }
    
    func testChromiumBrowserStrategyTitleWithNewlines() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _, _ in
            return "Google\nSearch\nEngine\nhttps://www.google.com"
        }
        
        let expectation = self.expectation(description: "Get active context title with newlines")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTAssertEqual(context.title, "Google\nSearch\nEngine")
                XCTAssertEqual(context.url, URL(string: "https://www.google.com"))
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testChromiumBrowserStrategyEmptyTitle() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _, _ in
            return "\nhttps://www.google.com"
        }
        
        let expectation = self.expectation(description: "Get active context empty title")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTAssertEqual(context.title, "")
                XCTAssertEqual(context.url, URL(string: "https://www.google.com"))
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testChromiumBrowserStrategyInsufficientParts() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _, _ in
            return "https://www.google.com"
        }
        
        let expectation = self.expectation(description: "Get active context insufficient parts")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTAssertEqual(context.title, "")
                XCTAssertEqual(context.url, URL(string: "https://www.google.com"))
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testChromiumBrowserStrategyInvalidURL() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _, _ in
            return "Google\ninvalid-url-without-scheme"
        }
        
        let expectation = self.expectation(description: "Get active context invalid URL")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTFail("Expected failure, got: \(context)")
            case .failure(let error):
                XCTAssertEqual(error, .execFailed("Invalid URL string: invalid-url-without-scheme"))
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testChromiumBrowserStrategyEmptyResult() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "company.thebrowser.Browser",
            appName: "Arc",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _, _ in
            return ""
        }
        
        let expectation = self.expectation(description: "Get active context empty result")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTFail("Expected failure, got: \(context)")
            case .failure(let error):
                XCTAssertEqual(error, .execFailed("Empty response from browser"))
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testChromiumBrowserStrategyFailure() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = ChromiumBrowserStrategy(
            bundleIdentifier: "com.microsoft.edgemac",
            appName: "Microsoft Edge",
            executor: mockExecutor
        )
        
        mockExecutor.executeCallback = { _, _ in
            throw NSError(domain: "test", code: -1708, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])
        }
        
        let expectation = self.expectation(description: "Get active context execution failure")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTFail("Expected failure, got: \(context)")
            case .failure(let error):
                XCTAssertEqual(error, .execFailed("User cancelled"))
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testSafariBrowserStrategyJavaScriptSuccess() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = SafariBrowserStrategy(executor: mockExecutor)
        
        mockExecutor.executeCallback = { source, timeout in
            if source.contains("do JavaScript") {
                return "Apple\nhttps://www.apple.com"
            }
            XCTFail("Should not fall back if JS is successful")
            return ""
        }
        
        let expectation = self.expectation(description: "Safari JS Success")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTAssertEqual(context.url, URL(string: "https://www.apple.com"))
                XCTAssertEqual(context.title, "Apple")
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
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
        let mockExecutor = MockAppleEventExecutor()
        let strategy = SafariBrowserStrategy(executor: mockExecutor)
        let delegate = MockSafariDelegate()
        strategy.delegate = delegate
        
        let expectation = self.expectation(description: "Delegate and callback are triggered")
        var callbackCalled = false
        strategy.onJavaScriptEventsDisabled = {
            callbackCalled = true
            expectation.fulfill()
        }
        
        mockExecutor.executeCallback = { source, timeout in
            if source.contains("do JavaScript") {
                // Simulate JavaScript disabled error message containing "Allow JavaScript from Apple Events"
                throw NSError(domain: "test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Allow JavaScript from Apple Events is off"])
            } else if source.contains("(name of current tab of window 1)") {
                return "Apple Support\nhttps://www.apple.com/safari"
            }
            XCTFail("Unexpected script executed")
            return ""
        }
        
        let getContextExpectation = self.expectation(description: "Get context completion")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTAssertEqual(context.url, URL(string: "https://www.apple.com/safari"))
                XCTAssertEqual(context.title, "Apple Support")
                getContextExpectation.fulfill()
            case .failure(let error):
                XCTFail("Expected fallback success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertTrue(delegate.didDetectDisabledJSCalled)
        XCTAssertTrue(callbackCalled)
        XCTAssertIdentical(delegate.detectedStrategy, strategy)
        XCTAssertTrue(strategy.hasTriggeredWarning)
        XCTAssertEqual(mockExecutor.executedScripts.count, 2)
    }
    
    func testSafariBrowserStrategyWarningTriggeredOnlyOnce() {
        let mockExecutor = MockAppleEventExecutor()
        let strategy = SafariBrowserStrategy(executor: mockExecutor)
        let delegate = MockSafariDelegate()
        strategy.delegate = delegate
        
        // Pre-trigger warning
        strategy.hasTriggeredWarning = true
        
        mockExecutor.executeCallback = { source, timeout in
            if source.contains("do JavaScript") {
                throw NSError(domain: "test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Allow JavaScript from Apple Events is off"])
            } else if source.contains("(name of current tab of window 1)") {
                return "Apple\nhttps://www.apple.com"
            }
            XCTFail("Unexpected script executed")
            return ""
        }
        
        let expectation = self.expectation(description: "Get context completion warning triggered once")
        strategy.getActiveContext { result in
            switch result {
            case .success(let context):
                XCTAssertEqual(context.url, URL(string: "https://www.apple.com"))
                XCTAssertEqual(context.title, "Apple")
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got: \(error)")
            }
        }
        
        waitForExpectations(timeout: 1.0)
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

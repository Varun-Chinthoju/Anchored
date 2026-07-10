import XCTest
@testable import Anchored

final class AppleEventExecutorTests: XCTestCase {
    
    func testExecuteSuccess() {
        let executor = AppleEventExecutor()
        let expectation = self.expectation(description: "AppleScript executes successfully")
        
        // Simple AppleScript that returns a string
        let script = "return \"Hello World\""
        
        executor.execute(script, timeout: 2.0) { result in
            switch result {
            case .success(let value):
                XCTAssertEqual(value, "Hello World")
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got failure: \(error)")
            }
        }
        
        waitForExpectations(timeout: 3.0)
    }
    
    func testExecuteTimeout() {
        let executor = AppleEventExecutor()
        let expectation = self.expectation(description: "AppleScript times out")
        
        // A script that takes a bit of time (delay 2 seconds)
        let script = "delay 2\nreturn \"Delayed\""
        
        executor.execute(script, timeout: 0.1) { result in
            switch result {
            case .success(let value):
                XCTFail("Expected timeout, got success with: \(value)")
            case .failure(let error):
                XCTAssertEqual(error, .timedOut)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testExecuteCompilationFailure() {
        let executor = AppleEventExecutor()
        let expectation = self.expectation(description: "AppleScript compilation fails")
        
        // Invalid syntax script
        let script = "invalid syntax logic here"
        
        executor.execute(script, timeout: 2.0) { result in
            switch result {
            case .success(let value):
                XCTFail("Expected compilation failure, got success: \(value)")
            case .failure(let error):
                switch error {
                case .execFailed(let msg):
                    XCTAssertFalse(msg.isEmpty)
                    expectation.fulfill()
                default:
                    XCTFail("Expected execFailed, got: \(error)")
                }
            }
        }
        
        waitForExpectations(timeout: 3.0)
    }
    
    func testConcurrencyAndThreadSafety() {
        let executor = AppleEventExecutor()
        let count = 30
        let expectation = self.expectation(description: "All concurrent executions complete")
        expectation.expectedFulfillmentCount = count
        
        let script = "return \"Concurrent\""
        
        for _ in 0..<count {
            DispatchQueue.global().async {
                executor.execute(script, timeout: 1.0) { result in
                    switch result {
                    case .success(let value):
                        XCTAssertEqual(value, "Concurrent")
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("Concurrent request failed: \(error)")
                    }
                }
            }
        }
        
        waitForExpectations(timeout: 5.0)
    }
}

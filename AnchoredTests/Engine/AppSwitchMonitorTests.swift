import XCTest
@testable import Anchored

class MockCollectorForMonitor: ContextCollecting {
    var lastBundleID: String?
    var completions: [(Result<ContextSnapshot, CollectionError>) -> Void] = []
    
    func collectContext(for bundleID: String, completion: @escaping (Result<ContextSnapshot, CollectionError>) -> Void) {
        lastBundleID = bundleID
        completions.append(completion)
    }
    
    func triggerCompletion(with result: Result<ContextSnapshot, CollectionError>) {
        let currentCompletions = completions
        completions.removeAll()
        for comp in currentCompletions {
            comp(result)
        }
    }
}

final class AppSwitchMonitorTests: XCTestCase {
    
    func testAppSwitchMonitorDeduplicationAndFallback() {
        let mockCollector = MockCollectorForMonitor()
        let monitor = AppSwitchMonitor(collector: mockCollector)
        
        var emittedSnapshots: [ContextSnapshot] = []
        monitor.onContextChange = { snapshot in
            emittedSnapshots.append(snapshot)
        }
        
        monitor.start()
        
        // Drain and discard the initial poll triggered by start()
        mockCollector.triggerCompletion(with: .failure(.timedOut))
        
        let initialDrainExpectation = self.expectation(description: "Wait for initial poll to finish")
        DispatchQueue.main.async {
            emittedSnapshots.removeAll()
            initialDrainExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // 1. Simulate first app switch (Finder)
        monitor.handleApplicationActivation(bundleID: "com.apple.Finder")
        XCTAssertEqual(mockCollector.lastBundleID, "com.apple.Finder")
        XCTAssertEqual(mockCollector.completions.count, 1)
        
        let snapshot1 = ContextSnapshot(
            bundleIdentifier: "com.apple.Finder",
            localizedName: "Finder",
            url: nil,
            title: "Finder Window",
            source: .application,
            observedAt: Date()
        )
        
        let expectation1 = self.expectation(description: "First emission callback")
        mockCollector.triggerCompletion(with: .success(snapshot1))
        
        // Wait for main thread dispatch
        DispatchQueue.main.async {
            XCTAssertEqual(emittedSnapshots.count, 1)
            XCTAssertEqual(emittedSnapshots.first?.title, "Finder Window")
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // 2. Simulate duplicate app switch (identical Finder context)
        // This should be deduplicated and NOT emitted
        monitor.handleApplicationActivation(bundleID: "com.apple.Finder")
        XCTAssertEqual(mockCollector.completions.count, 1)
        mockCollector.triggerCompletion(with: .success(snapshot1))
        
        let expectation2 = self.expectation(description: "Deduplication wait")
        DispatchQueue.main.async {
            XCTAssertEqual(emittedSnapshots.count, 1) // Still 1
            expectation2.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // 3. Simulate another Finder switch with different title
        let snapshot2 = ContextSnapshot(
            bundleIdentifier: "com.apple.Finder",
            localizedName: "Finder",
            url: nil,
            title: "Downloads",
            source: .application,
            observedAt: Date()
        )
        monitor.handleApplicationActivation(bundleID: "com.apple.Finder")
        XCTAssertEqual(mockCollector.completions.count, 1)
        mockCollector.triggerCompletion(with: .success(snapshot2))
        
        let expectation3 = self.expectation(description: "Title changed emission")
        DispatchQueue.main.async {
            XCTAssertEqual(emittedSnapshots.count, 2)
            XCTAssertEqual(emittedSnapshots.last?.title, "Downloads")
            expectation3.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // 4. Simulate a failure (fallback should be emitted if different)
        monitor.handleApplicationActivation(bundleID: "com.apple.dt.Xcode")
        XCTAssertEqual(mockCollector.completions.count, 1)
        mockCollector.triggerCompletion(with: .failure(.timedOut))
        
        let expectation4 = self.expectation(description: "Fallback emission")
        DispatchQueue.main.async {
            XCTAssertEqual(emittedSnapshots.count, 3)
            XCTAssertEqual(emittedSnapshots.last?.bundleIdentifier, "com.apple.dt.Xcode")
            XCTAssertNil(emittedSnapshots.last?.url)
            XCTAssertEqual(emittedSnapshots.last?.title, "")
            expectation4.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        monitor.stop()
    }
}

import XCTest
@testable import Anchored

final class ClassificationCacheTests: XCTestCase {
    func testStoresExplainableEntries() {
        let cache = ClassificationCache(maximumEntries: 4)
        let key = ClassificationCacheKey(
            contextIdentity: ContextIdentity(
                bundleID: "com.example.app",
                sanitizedURL: "example.com",
                normalizedTitle: "Example"
            ),
            profileID: UUID(),
            sessionID: nil,
            classificationConfigurationRevision: 1
        )

        let decision = ClassificationDecision.neutral(reason: .neutralFallback)
        cache.store(decision, for: key)

        let entry = cache.cachedClassification(for: key)
        XCTAssertEqual(entry?.decision, decision)
        XCTAssertEqual(entry?.source, .neutralFallback)
        XCTAssertNotNil(entry?.createdAt)
    }

    func testEvictsOldestEntriesBeyondCapacity() {
        let cache = ClassificationCache(maximumEntries: 2)
        let keys = (0..<3).map { index in
            ClassificationCacheKey(
                contextIdentity: ContextIdentity(
                    bundleID: "com.example.app\(index)",
                    sanitizedURL: nil,
                    normalizedTitle: "Title \(index)"
                ),
                profileID: UUID(),
                sessionID: nil,
                classificationConfigurationRevision: 1
            )
        }

        for (index, key) in keys.enumerated() {
            let decision = ClassificationDecision(
                label: .productive,
                confidence: 0.9,
                source: .heuristic,
                reason: .deterministicHeuristic,
                evidence: []
            )
            cache.store(decision, for: key)
            XCTAssertLessThanOrEqual(cache.count, 2, "Cache should remain bounded after entry \(index)")
        }

        XCTAssertNil(cache.cachedClassification(for: keys[0]))
        XCTAssertNotNil(cache.cachedClassification(for: keys[1]))
        XCTAssertNotNil(cache.cachedClassification(for: keys[2]))
    }
}


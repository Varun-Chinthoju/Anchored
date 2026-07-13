import XCTest
@testable import Anchored

final class InteractionSummaryTests: XCTestCase {
    func testProviderTracksForegroundAndIdleDurationWithoutRawEvents() {
        let provider = LocalInteractionSummaryProvider(systemIdleDurationProvider: { 90 })
        let start = Date(timeIntervalSinceReferenceDate: 10_000)

        provider.beginContext(at: start)
        let summary = provider.summary(at: start.addingTimeInterval(90))

        XCTAssertEqual(summary.foregroundDuration, 90)
        XCTAssertEqual(summary.idleDuration, 90)
        XCTAssertEqual(summary.clickBucket, 0)
        XCTAssertEqual(summary.keyBucket, 0)
    }

    func testProviderKeepsOnlyBoundedAggregateBuckets() {
        let provider = LocalInteractionSummaryProvider(systemIdleDurationProvider: { 0 })
        let start = Date(timeIntervalSinceReferenceDate: 10_000)

        provider.beginContext(at: start)
        provider.recordInteraction(at: start.addingTimeInterval(10), kind: .click)
        provider.recordInteraction(at: start.addingTimeInterval(10), kind: .key)
        provider.recordInteraction(at: start.addingTimeInterval(10), kind: .scroll)
        provider.recordInteraction(at: start.addingTimeInterval(10), kind: .movement)

        let summary = provider.summary(at: start.addingTimeInterval(70))

        XCTAssertEqual(summary.idleDuration, 0)
        XCTAssertEqual(summary.clickBucket, 1)
        XCTAssertEqual(summary.keyBucket, 1)
        XCTAssertEqual(summary.scrollBucket, 1)
        XCTAssertEqual(summary.movementBucket, 1)
        XCTAssertEqual(summary.interactionBurstRate, 4 / (70.0 / 60.0), accuracy: 0.001)
    }
}

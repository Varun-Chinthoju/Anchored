import Foundation
import AppKit

struct InteractionSummary: Equatable, Codable, Sendable {
    let foregroundDuration: TimeInterval
    let idleDuration: TimeInterval
    let interactionBurstRate: Double
    let clickBucket: Int
    let keyBucket: Int
    let scrollBucket: Int
    let movementBucket: Int

    init(
        foregroundDuration: TimeInterval = 0,
        idleDuration: TimeInterval = 0,
        interactionBurstRate: Double = 0,
        clickBucket: Int = 0,
        keyBucket: Int = 0,
        scrollBucket: Int = 0,
        movementBucket: Int = 0
    ) {
        self.foregroundDuration = max(0, foregroundDuration)
        self.idleDuration = max(0, idleDuration)
        self.interactionBurstRate = max(0, interactionBurstRate)
        self.clickBucket = max(0, clickBucket)
        self.keyBucket = max(0, keyBucket)
        self.scrollBucket = max(0, scrollBucket)
        self.movementBucket = max(0, movementBucket)
    }

    static let empty = InteractionSummary()
}

protocol InteractionSummaryProviding: AnyObject {
    func beginContext(at date: Date)
    func summary(at date: Date) -> InteractionSummary
}

enum InteractionKind {
    case click
    case key
    case scroll
    case movement
}

/// Local, memory-only interaction aggregate. It does not install an event tap
/// or retain raw events; broader event collection can be added behind this
/// seam later without changing the resolver contract.
final class LocalInteractionSummaryProvider: InteractionSummaryProviding {
    private let lock = NSLock()
    private let systemIdleDurationProvider: () -> TimeInterval
    private var contextStartedAt: Date?
    private var lastActivityAt: Date?
    private var clickCount = 0
    private var keyCount = 0
    private var scrollCount = 0
    private var movementCount = 0

    init(systemIdleDurationProvider: @escaping () -> TimeInterval = {
        let anyInputEventType = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }) {
        self.systemIdleDurationProvider = systemIdleDurationProvider
    }

    func beginContext(at date: Date) {
        lock.lock()
        contextStartedAt = date
        lastActivityAt = date
        clickCount = 0
        keyCount = 0
        scrollCount = 0
        movementCount = 0
        lock.unlock()
    }

    func recordInteraction(at date: Date, kind: InteractionKind) {
        lock.lock()
        lastActivityAt = max(lastActivityAt ?? date, date)
        switch kind {
        case .click:
            clickCount = min(100, clickCount + 1)
        case .key:
            keyCount = min(100, keyCount + 1)
        case .scroll:
            scrollCount = min(100, scrollCount + 1)
        case .movement:
            movementCount = min(100, movementCount + 1)
        }
        lock.unlock()
    }

    func summary(at date: Date) -> InteractionSummary {
        lock.lock()
        defer { lock.unlock() }
        guard let contextStartedAt else { return .empty }
        let foreground = max(0, date.timeIntervalSince(contextStartedAt))
        let lastActivityAt = self.lastActivityAt ?? contextStartedAt
        let contextIdle = max(0, date.timeIntervalSince(lastActivityAt))
        let systemIdle = max(0, systemIdleDurationProvider())
        let idle = min(foreground, min(contextIdle, systemIdle))
        let totalInteractions = clickCount + keyCount + scrollCount + movementCount
        let burstRate = foreground > 0 ? Double(totalInteractions) / (foreground / 60) : 0
        return InteractionSummary(
            foregroundDuration: foreground,
            idleDuration: idle,
            interactionBurstRate: burstRate,
            clickBucket: clickCount,
            keyBucket: keyCount,
            scrollBucket: scrollCount,
            movementBucket: movementCount
        )
    }
}

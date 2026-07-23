import Foundation

struct ClassificationCacheKey: Hashable {
    let contextIdentity: ContextIdentity
    let profileID: UUID
    let sessionID: UUID?
    let classificationConfigurationRevision: UInt64
}

struct CachedClassification {
    let decision: ClassificationDecision
    let source: ClassificationSource
    let createdAt: ContinuousClock.Instant
}

final class ClassificationCache {
    private let maximumEntries: Int
    private let clock: ContinuousClock
    private var entries: [ClassificationCacheKey: CachedClassification] = [:]
    private var insertionOrder: [ClassificationCacheKey] = []

    init(maximumEntries: Int = 256, clock: ContinuousClock = ContinuousClock()) {
        self.maximumEntries = max(1, maximumEntries)
        self.clock = clock
    }

    var count: Int {
        entries.count
    }

    func cachedClassification(for key: ClassificationCacheKey) -> CachedClassification? {
        entries[key]
    }

    func store(_ decision: ClassificationDecision, for key: ClassificationCacheKey) {
        let entry = CachedClassification(
            decision: decision,
            source: decision.source,
            createdAt: clock.now
        )

        if entries.updateValue(entry, forKey: key) == nil {
            insertionOrder.append(key)
        } else if let index = insertionOrder.firstIndex(of: key) {
            insertionOrder.remove(at: index)
            insertionOrder.append(key)
        }

        evictIfNeeded()
    }

    func removeValue(forKey key: ClassificationCacheKey) {
        entries.removeValue(forKey: key)
        insertionOrder.removeAll { $0 == key }
    }

    func removeAll() {
        entries.removeAll()
        insertionOrder.removeAll()
    }

    private func evictIfNeeded() {
        while entries.count > maximumEntries, let oldestKey = insertionOrder.first {
            insertionOrder.removeFirst()
            entries.removeValue(forKey: oldestKey)
        }
    }
}


import Foundation

protocol ContextualLearningRecording: AnyObject {
    var isEnabled: Bool { get set }
    func record(_ record: ContextualLearningRecord, completion: StorageWriteCompletion?)
    func evidence(for snapshot: ContextSnapshot, focusIntent: FocusIntent?) -> ClassificationEvidence?
    func shouldSuggestPermanentRule(for domain: String) -> Bool
    func clearAll(completion: StorageWriteCompletion?)
    func prune(retentionDays: Int, completion: StorageWriteCompletion?)
}

final class ContextualLearningStore: ContextualLearningRecording {
    static let shared = ContextualLearningStore()

    private struct Key: Hashable {
        let normalizedDomain: String
        let pageCategory: ContextualPageCategory
        let intentCategory: ContextualIntentCategory
    }

    private struct Bucket {
        var records: [ContextualLearningRecord] = []
    }

    private let sqliteStore: SQLiteSessionStore
    private let queue = DispatchQueue(label: "com.varun.Anchored.ContextualLearningStore", qos: .utility)
    private let clock: () -> Date
    private let lastCleanupKey: String
    private var buckets: [Key: Bucket] = [:]

    var isEnabled: Bool

    init(
        sqliteStore: SQLiteSessionStore = .shared,
        isEnabled: Bool = false,
        clock: @escaping () -> Date = Date.init,
        lastCleanupKey: String = "com.varun.Anchored.contextualLearningLastCleanup"
    ) {
        self.sqliteStore = sqliteStore
        self.isEnabled = isEnabled
        self.clock = clock
        self.lastCleanupKey = lastCleanupKey

        reloadCache()
    }

    func record(_ record: ContextualLearningRecord, completion: StorageWriteCompletion? = nil) {
        queue.async {
            guard self.isEnabled else {
                self.finish(completion, with: .success(()))
                return
            }

            let sanitized = ContextualLearningRecord(
                normalizedDomain: record.normalizedDomain,
                pageCategory: record.pageCategory,
                intentCategory: record.intentCategory,
                decision: record.decision,
                timestamp: record.timestamp
            )
            self.storeInMemory(sanitized)

            do {
                try self.sqliteStore.insertContextualLearningRecord(sanitized)
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func evidence(for snapshot: ContextSnapshot, focusIntent: FocusIntent?) -> ClassificationEvidence? {
        guard isEnabled else { return nil }
        guard let normalizedDomain = ContextualSiteHeuristic.normalizedDomain(for: snapshot.url) else {
            return nil
        }

        let pageCategory = ContextualSiteHeuristic.pageCategory(for: snapshot.url, title: snapshot.title)
        let intentCategory = ContextualSiteHeuristic.intentCategory(for: focusIntent)
        let exactKey = Key(normalizedDomain: normalizedDomain, pageCategory: pageCategory, intentCategory: intentCategory)

        let records = queue.sync { () -> [ContextualLearningRecord] in
            buckets[exactKey]?.records ?? []
        }

        return signal(for: records)
    }

    func shouldSuggestPermanentRule(for domain: String) -> Bool {
        guard isEnabled else { return false }
        let targetDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = targetDomain.hasPrefix("www.") ? String(targetDomain.dropFirst(4)) : targetDomain
        let count = queue.sync { () -> Int in
            buckets.values
                .flatMap { $0.records }
                .filter { $0.normalizedDomain == normalized && $0.decision == .productive }
                .count
        }
        return count >= 3
    }

    func clearAll(completion: StorageWriteCompletion? = nil) {
        queue.async {
            self.buckets.removeAll()
            do {
                try self.sqliteStore.deleteAllContextualLearningRecords()
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func prune(retentionDays: Int, completion: StorageWriteCompletion? = nil) {
        let cutoff = clock().addingTimeInterval(-TimeInterval(max(1, retentionDays) * 24 * 60 * 60))
        queue.async {
            do {
                try self.sqliteStore.deleteContextualLearningRecords(olderThan: cutoff)
                self.reloadCacheLocked()
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    private func reloadCache() {
        queue.async {
            self.reloadCacheLocked()
        }
    }

    private func reloadCacheLocked() {
        let records = (try? sqliteStore.fetchContextualLearningRecords()) ?? []
        var rebuilt: [Key: Bucket] = [:]
        for record in records {
            let key = Key(
                normalizedDomain: record.normalizedDomain,
                pageCategory: record.pageCategory,
                intentCategory: record.intentCategory
            )
            var bucket = rebuilt[key] ?? Bucket()
            bucket.records.append(record)
            rebuilt[key] = bucket
        }
        buckets = rebuilt
    }

    private func storeInMemory(_ record: ContextualLearningRecord) {
        let key = Key(
            normalizedDomain: record.normalizedDomain,
            pageCategory: record.pageCategory,
            intentCategory: record.intentCategory
        )
        var bucket = buckets[key] ?? Bucket()
        bucket.records.append(record)
        buckets[key] = bucket
    }

    private func signal(for records: [ContextualLearningRecord]) -> ClassificationEvidence? {
        guard !records.isEmpty else { return nil }

        let productiveCount = records.filter { $0.decision == .productive }.count
        let distractingCount = records.filter { $0.decision == .distracting }.count
        let contextualCount = records.filter { $0.decision == .contextual }.count

        if productiveCount >= 2, productiveCount > distractingCount {
            let confidence = min(0.95, 0.55 + Double(productiveCount) * 0.10)
            return ClassificationEvidence(
                label: .productive,
                source: .deterministicRule,
                confidence: confidence,
                reason: .contextualLearning
            )
        }

        if distractingCount >= 2, distractingCount > productiveCount {
            let confidence = min(0.95, 0.55 + Double(distractingCount) * 0.10)
            return ClassificationEvidence(
                label: .distracting,
                source: .deterministicRule,
                confidence: confidence,
                reason: .contextualLearning
            )
        }

        if productiveCount > 0 || distractingCount > 0 || contextualCount > 0 {
            let confidence = min(0.75, 0.50 + Double(records.count) * 0.05)
            return ClassificationEvidence(
                label: .contextual,
                source: .heuristic,
                confidence: confidence,
                reason: .contextualLearning
            )
        }

        return nil
    }
}

private extension ContextualLearningStore {
    func finish(_ completion: StorageWriteCompletion?, with result: Result<Void, Error>) {
        guard let completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

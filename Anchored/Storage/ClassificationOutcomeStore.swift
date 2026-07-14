import Foundation

protocol ClassificationOutcomeRecording: AnyObject {
    var isEnabled: Bool { get set }
    func record(_ outcome: ClassificationOutcome, completion: StorageWriteCompletion?)
    func recordCorrection(
        identity: ClassificationOutcome.Identity,
        correction: ClassificationCorrection,
        correctedAt: Date,
        completion: StorageWriteCompletion?
    )
    func clearAll(completion: StorageWriteCompletion?)
    func prune(retentionDays: Int, completion: StorageWriteCompletion?)
    func count(completion: @escaping (Result<Int, Error>) -> Void)
    func oldestObservationDate(completion: @escaping (Result<Date?, Error>) -> Void)
}

final class ClassificationOutcomeStore: ClassificationOutcomeRecording {
    static let shared = ClassificationOutcomeStore()

    private let sqliteStore: SQLiteSessionStore
    private let queue = DispatchQueue(label: "com.varun.Anchored.ClassificationOutcomeStore", qos: .utility)
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let lastCleanupKey: String
    private let onRecord: ((ClassificationOutcome) -> Void)?
    private let onCorrection: ((ClassificationOutcome.Identity, ClassificationCorrection) -> Void)?

    private var lastPersistedIdentity: ClassificationOutcome.Identity?

    var isEnabled: Bool

    init(
        sqliteStore: SQLiteSessionStore = .shared,
        defaults: UserDefaults = .standard,
        isEnabled: Bool = false,
        clock: @escaping () -> Date = Date.init,
        lastCleanupKey: String = "com.varun.Anchored.classificationOutcomeLastCleanup",
        onRecord: ((ClassificationOutcome) -> Void)? = nil,
        onCorrection: ((ClassificationOutcome.Identity, ClassificationCorrection) -> Void)? = nil
    ) {
        self.sqliteStore = sqliteStore
        self.defaults = defaults
        self.clock = clock
        self.lastCleanupKey = lastCleanupKey
        self.isEnabled = isEnabled
        self.onRecord = onRecord
        self.onCorrection = onCorrection
        self.lastPersistedIdentity = try? sqliteStore.latestClassificationOutcomeIdentity()
    }

    func record(_ outcome: ClassificationOutcome, completion: StorageWriteCompletion? = nil) {
        queue.async {
            guard self.isEnabled else {
                self.finish(completion, with: .success(()))
                return
            }

            let sanitizedOutcome = outcome.sanitizedForPersistence()
            self.onRecord?(sanitizedOutcome)

            do {
                try self.sqliteStore.insertClassificationOutcome(sanitizedOutcome)
                self.lastPersistedIdentity = sanitizedOutcome.identity
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func recordCorrection(
        identity: ClassificationOutcome.Identity,
        correction: ClassificationCorrection,
        correctedAt: Date = Date(),
        completion: StorageWriteCompletion? = nil
    ) {
        queue.async {
            guard self.isEnabled else {
                self.finish(completion, with: .success(()))
                return
            }

            let sanitizedIdentity = identity.sanitizedForPersistence()
            self.onCorrection?(sanitizedIdentity, correction)
            do {
                try self.sqliteStore.updateClassificationOutcomeCorrection(
                    identityKey: sanitizedIdentity.key,
                    correction: correction,
                    correctedAt: correctedAt
                )
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func clearAll(completion: StorageWriteCompletion? = nil) {
        queue.async {
            do {
                try self.sqliteStore.deleteAllClassificationOutcomes()
                self.lastPersistedIdentity = nil
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func prune(retentionDays: Int, completion: StorageWriteCompletion? = nil) {
        let days = max(1, retentionDays)
        let cutoff = clock().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))

        queue.async {
            do {
                try self.sqliteStore.deleteClassificationOutcomes(olderThan: cutoff)
                try self.refreshLastPersistedIdentity()
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func count(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            do {
                let count = try self.sqliteStore.classificationOutcomeCount()
                DispatchQueue.main.async { completion(.success(count)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func oldestObservationDate(completion: @escaping (Result<Date?, Error>) -> Void) {
        queue.async {
            do {
                let date = try self.sqliteStore.oldestClassificationOutcomeDate()
                DispatchQueue.main.async { completion(.success(date)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func performLaunchMaintenance(retentionDays: Int, completion: StorageWriteCompletion? = nil) {
        let now = clock()
        let shouldRun: Bool
        if let lastCleanup = defaults.object(forKey: lastCleanupKey) as? Date {
            shouldRun = now.timeIntervalSince(lastCleanup) >= 24 * 60 * 60
        } else {
            shouldRun = true
        }

        guard shouldRun else {
            finish(completion, with: .success(()))
            return
        }

        prune(retentionDays: retentionDays) { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                self.defaults.set(now, forKey: self.lastCleanupKey)
            }
            completion?(result)
        }
    }

    private func refreshLastPersistedIdentity() throws {
        lastPersistedIdentity = try sqliteStore.latestClassificationOutcomeIdentity()
    }
}

private extension ClassificationOutcome.Identity {
    func sanitizedForPersistence() -> ClassificationOutcome.Identity {
        ClassificationOutcome.Identity(
            contextGeneration: contextGeneration,
            sessionID: sessionID,
            contextIdentity: ContextIdentity(
                bundleID: contextIdentity.bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
                sanitizedURL: contextIdentity.sanitizedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                normalizedTitle: contextIdentity.normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}

private extension ClassificationOutcomeStore {
    func finish(_ completion: StorageWriteCompletion?, with result: Result<Void, Error>) {
        guard let completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

import Foundation

final class ContextHistoryStore {
    static let shared = ContextHistoryStore()

    private let sqliteStore: SQLiteSessionStore
    private let queue = DispatchQueue(label: "com.varun.Anchored.ContextHistoryStore", qos: .utility)
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let lastCleanupKey: String

    private var lastPersistedIdentity: PersistedContextObservation.Identity?

    var isEnabled: Bool

    init(
        sqliteStore: SQLiteSessionStore = .shared,
        defaults: UserDefaults = .standard,
        isEnabled: Bool = false,
        clock: @escaping () -> Date = Date.init,
        lastCleanupKey: String = "com.varun.Anchored.contextHistoryLastCleanup"
    ) {
        self.sqliteStore = sqliteStore
        self.defaults = defaults
        self.clock = clock
        self.lastCleanupKey = lastCleanupKey
        self.isEnabled = isEnabled

        self.lastPersistedIdentity = try? sqliteStore.latestContextObservationIdentity()
    }

    func record(_ observation: PersistedContextObservation, completion: StorageWriteCompletion? = nil) {
        queue.async {
            guard self.isEnabled else {
                self.finishWrite(completion, with: .success(()))
                return
            }

            let sanitizedObservation = observation.sanitizedForPersistence()
            do {
                let shouldSkip = try self.shouldSkipPersisting(sanitizedObservation)
                guard !shouldSkip else {
                    self.finishWrite(completion, with: .success(()))
                    return
                }

                try self.sqliteStore.insertContextObservation(sanitizedObservation)
                self.lastPersistedIdentity = sanitizedObservation.identity
                self.finishWrite(completion, with: .success(()))
            } catch {
                self.finishWrite(completion, with: .failure(error))
            }
        }
    }

    func record(
        bundleID: String,
        appName: String,
        title: String,
        url: URL?,
        source: String,
        sessionState: SessionState,
        observedAt: Date = Date(),
        completion: StorageWriteCompletion? = nil
    ) {
        let observation = PersistedContextObservation.make(
            bundleID: bundleID,
            appName: appName,
            source: source,
            title: title,
            url: url,
            sessionState: sessionState,
            observedAt: observedAt
        )
        record(observation, completion: completion)
    }

    func clearAll(completion: StorageWriteCompletion? = nil) {
        queue.async {
            do {
                try self.sqliteStore.deleteAllContextObservations()
                self.lastPersistedIdentity = nil
                self.finishWrite(completion, with: .success(()))
            } catch {
                self.finishWrite(completion, with: .failure(error))
            }
        }
    }

    func prune(retentionDays: Int, completion: StorageWriteCompletion? = nil) {
        let days = max(1, retentionDays)
        let cutoff = clock().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))

        queue.async {
            do {
                try self.sqliteStore.deleteContextObservations(olderThan: cutoff)
                try self.refreshLastPersistedIdentity()
                self.finishWrite(completion, with: .success(()))
            } catch {
                self.finishWrite(completion, with: .failure(error))
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
            finishWrite(completion, with: .success(()))
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

    func observationCount(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            do {
                let count = try self.sqliteStore.contextObservationCount()
                DispatchQueue.main.async {
                    completion(.success(count))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func oldestObservationDate(completion: @escaping (Result<Date?, Error>) -> Void) {
        queue.async {
            do {
                let date = try self.sqliteStore.oldestContextObservationDate()
                DispatchQueue.main.async {
                    completion(.success(date))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func shouldSkipPersisting(_ observation: PersistedContextObservation) throws -> Bool {
        if let lastPersistedIdentity {
            return lastPersistedIdentity == observation.identity
        }

        if let latestIdentity = try sqliteStore.latestContextObservationIdentity() {
            lastPersistedIdentity = latestIdentity
            return latestIdentity == observation.identity
        }

        return false
    }

    private func refreshLastPersistedIdentity() throws {
        lastPersistedIdentity = try sqliteStore.latestContextObservationIdentity()
    }
}

private extension ContextHistoryStore {
    func finishWrite(_ completion: StorageWriteCompletion?, with result: Result<Void, Error>) {
        guard let completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

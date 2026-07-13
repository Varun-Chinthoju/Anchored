import Foundation

final class ClassificationFeedbackStore {
    static let shared = ClassificationFeedbackStore()

    private let sqliteStore: SQLiteSessionStore
    private let queue = DispatchQueue(label: "com.varun.Anchored.ClassificationFeedbackStore", qos: .utility)
    private let clock: () -> Date
    var isEnabled: Bool

    init(
        sqliteStore: SQLiteSessionStore = .shared,
        isEnabled: Bool = false,
        clock: @escaping () -> Date = Date.init
    ) {
        self.sqliteStore = sqliteStore
        self.isEnabled = isEnabled
        self.clock = clock
    }

    func record(_ feedback: ClassificationFeedback, completion: StorageWriteCompletion? = nil) {
        queue.async {
            guard self.isEnabled else {
                self.finish(completion, with: .success(()))
                return
            }
            do {
                try self.sqliteStore.insertClassificationFeedback(feedback)
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func clearAll(completion: StorageWriteCompletion? = nil) {
        queue.async {
            do {
                try self.sqliteStore.deleteAllClassificationFeedback()
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
                try self.sqliteStore.deleteClassificationFeedback(olderThan: cutoff)
                self.finish(completion, with: .success(()))
            } catch {
                self.finish(completion, with: .failure(error))
            }
        }
    }

    func count(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            do {
                let count = try self.sqliteStore.classificationFeedbackCount()
                DispatchQueue.main.async { completion(.success(count)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

private extension ClassificationFeedbackStore {
    func finish(_ completion: StorageWriteCompletion?, with result: Result<Void, Error>) {
        guard let completion else { return }
        DispatchQueue.main.async { completion(result) }
    }
}


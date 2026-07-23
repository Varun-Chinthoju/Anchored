import Foundation
@testable import Anchored

final class QueuedCloudClassificationService: CloudClassificationServing {
    final class PendingRequest {
        let input: CloudClassificationInput
        private let completion: (Result<ClassificationResult, Error>) -> Void
        private(set) var isCompleted = false

        init(
            input: CloudClassificationInput,
            completion: @escaping (Result<ClassificationResult, Error>) -> Void
        ) {
            self.input = input
            self.completion = completion
        }

        func complete(_ result: Result<ClassificationResult, Error>) {
            guard !isCompleted else { return }
            isCompleted = true
            completion(result)
        }
    }

    private let lock = NSLock()
    private var requests: [PendingRequest] = []

    var onRequest: ((PendingRequest) -> Void)?

    var pendingRequests: [PendingRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests.filter { !$0.isCompleted }
    }

    func pendingRequest(at index: Int) -> PendingRequest? {
        let requests = pendingRequests
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }

    func classify(
        _ input: CloudClassificationInput,
        completion: @escaping (Result<ClassificationResult, Error>) -> Void
    ) {
        let request = PendingRequest(input: input, completion: completion)
        lock.lock()
        requests.append(request)
        lock.unlock()
        onRequest?(request)
    }
}

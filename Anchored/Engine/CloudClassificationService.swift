import Foundation

protocol CloudClassificationServing: AnyObject {
    func classify(_ input: CloudClassificationInput, completion: @escaping (Result<ClassificationResult, Error>) -> Void)
}

final class LiveCloudClassificationService: CloudClassificationServing {
    private let preferences: PreferencesManager

    init(preferences: PreferencesManager) {
        self.preferences = preferences
    }

    func classify(_ input: CloudClassificationInput, completion: @escaping (Result<ClassificationResult, Error>) -> Void) {
        CloudClassifier(preferences: preferences).classify(input: input, completion: completion)
    }
}

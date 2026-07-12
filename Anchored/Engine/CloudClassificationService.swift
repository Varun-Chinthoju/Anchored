import Foundation

struct CloudClassificationInput {
    let appName: String
    let windowTitle: String
    let url: URL?
    let ocrText: String
}

protocol CloudClassificationServing: AnyObject {
    func classify(_ input: CloudClassificationInput, completion: @escaping (Result<Bool, Error>) -> Void)
}

final class LiveCloudClassificationService: CloudClassificationServing {
    private let preferences: PreferencesManager

    init(preferences: PreferencesManager) {
        self.preferences = preferences
    }

    func classify(_ input: CloudClassificationInput, completion: @escaping (Result<Bool, Error>) -> Void) {
        CloudClassifier(preferences: preferences).classify(
            appName: input.appName,
            windowTitle: input.windowTitle,
            url: input.url,
            ocrText: input.ocrText,
            completion: completion
        )
    }
}

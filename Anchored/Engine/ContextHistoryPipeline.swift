import Foundation

final class ContextHistoryPipeline {
    private let focusEngine: FocusEngine
    private let historyStore: ContextHistoryStore
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    init(
        focusEngine: FocusEngine,
        historyStore: ContextHistoryStore = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.focusEngine = focusEngine
        self.historyStore = historyStore
        self.notificationCenter = notificationCenter

        observer = notificationCenter.addObserver(
            forName: .focusEngineContextDidChange,
            object: focusEngine,
            queue: .main
        ) { [weak self] notification in
            self?.recordContext(from: notification)
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    private func recordContext(from notification: Notification) {
        guard historyStore.isEnabled,
              let userInfo = notification.userInfo,
              let snapshot = userInfo["snapshot"] as? ContextSnapshot else {
            return
        }

        historyStore.record(
            bundleID: snapshot.bundleIdentifier,
            appName: snapshot.localizedName,
            title: snapshot.title,
            url: snapshot.url,
            source: snapshot.source.rawValue,
            sessionState: focusEngine.state
        )
    }
}

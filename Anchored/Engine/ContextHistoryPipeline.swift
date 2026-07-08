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
        ) { [weak self] _ in
            self?.recordCurrentContext()
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    private func recordCurrentContext() {
        guard historyStore.isEnabled,
              let context = focusEngine.currentContext else {
            return
        }

        let source = source(for: context.bundleIdentifier)
        historyStore.record(
            bundleID: context.bundleIdentifier,
            appName: context.localizedName,
            title: context.title,
            url: focusEngine.currentURL,
            source: source,
            sessionState: focusEngine.state
        )
    }

    private func source(for bundleID: String) -> String {
        switch BrowserStrategyFactory.strategy(for: bundleID) {
        case is SafariBrowserStrategy:
            return "safari"
        case is FirefoxBrowserStrategy:
            return "firefox"
        case is ChromiumBrowserStrategy:
            return "chromium"
        default:
            return "application"
        }
    }
}

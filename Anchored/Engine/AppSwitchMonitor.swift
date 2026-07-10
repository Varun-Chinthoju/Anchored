import AppKit
import ApplicationServices

/// Monitors application switch events via `NSWorkspace.didActivateApplicationNotification`
/// and publishes the active application's bundle identifier and browser URL asynchronously.
/// V2.6 contract: 2.5s poll, dedup via ContextIdentity, suspend on sleep/lock, stop on permission loss.
final class AppSwitchMonitor: ActivityMonitor {
    var onContextChange: ((ContextSnapshot) -> Void)?

    private let collector: ContextCollecting
    private var activationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var sessionActiveObserver: NSObjectProtocol?
    private var sessionInactiveObserver: NSObjectProtocol?
    private var isMonitoring = false
    private var isSuspendedForSleep = false
    private var isSuspendedForLock = false

    private var pollingTimer: Timer?
    private var activeBundleID: String?
    private var lastPolledIdentity: ContextIdentity?

    init(collector: ContextCollecting = ContextCollector()) {
        self.collector = collector
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard let bundleID = app.bundleIdentifier else { return }
            self.handleApplicationActivation(bundleID: bundleID)
        }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSleep()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        sessionActiveObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSessionUnlock()
        }

        sessionInactiveObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSessionLock()
        }

        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontApp.bundleIdentifier {
            handleApplicationActivation(bundleID: bundleID)
        }

        startPollingTimer()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false

        cancelPollingTimer()
        activeBundleID = nil
        lastPolledIdentity = nil
        isSuspendedForSleep = false
        isSuspendedForLock = false

        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = sessionActiveObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = sessionInactiveObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activationObserver = nil
        sleepObserver = nil
        wakeObserver = nil
        sessionActiveObserver = nil
        sessionInactiveObserver = nil
    }

    func handleApplicationActivation(bundleID: String) {
        activeBundleID = bundleID
        pollActiveContext()
    }

    private func handleSleep() {
        isSuspendedForSleep = true
        cancelPollingTimer()
    }

    private func handleWake() {
        guard isMonitoring, isSuspendedForSleep else { return }
        isSuspendedForSleep = false
        if !isSuspendedForLock {
            startPollingTimer()
            pollActiveContext()
        }
    }

    private func handleSessionLock() {
        isSuspendedForLock = true
        cancelPollingTimer()
    }

    private func handleSessionUnlock() {
        guard isMonitoring, isSuspendedForLock else { return }
        isSuspendedForLock = false
        if !isSuspendedForSleep {
            startPollingTimer()
            pollActiveContext()
        }
    }

    private func startPollingTimer() {
        cancelPollingTimer()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.pollActiveContext()
        }
    }

    private func cancelPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func pollActiveContext() {
        guard let bundleID = activeBundleID else { return }
        guard !isSuspendedForSleep && !isSuspendedForLock else { return }

        collector.collectContext(for: bundleID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.isMonitoring, self.activeBundleID == bundleID else { return }
                guard !self.isSuspendedForSleep && !self.isSuspendedForLock else { return }

                switch result {
                case .success(let snapshot):
                    let newIdentity = snapshot.identity
                    if newIdentity != self.lastPolledIdentity {
                        self.lastPolledIdentity = newIdentity
                        self.onContextChange?(snapshot)
                    }
                case .failure(let error):
                    if case .permissionDenied = error {
                        self.cancelPollingTimer()
                        return
                    }
                    let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
                    let localizedName = runningApp?.localizedName ?? ""
                    let fallbackSnapshot = ContextSnapshot(
                        bundleIdentifier: bundleID,
                        localizedName: localizedName,
                        url: nil,
                        title: "",
                        source: .application,
                        observedAt: Date()
                    )
                    let fallbackIdentity = fallbackSnapshot.identity
                    if fallbackIdentity != self.lastPolledIdentity {
                        self.lastPolledIdentity = fallbackIdentity
                        self.onContextChange?(fallbackSnapshot)
                    }
                }
            }
        }
    }

    deinit {
        stop()
    }
}

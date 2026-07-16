import Foundation

protocol OneShotTimerHandle {
    func cancel()
}

protocol OneShotTimerScheduling {
    func schedule(after interval: TimeInterval, action: @escaping () -> Void) -> OneShotTimerHandle
}

struct LiveOneShotTimerScheduler: OneShotTimerScheduling {
    func schedule(after interval: TimeInterval, action: @escaping () -> Void) -> OneShotTimerHandle {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
        }
        return LiveOneShotTimerHandle(timer: timer)
    }
}

final class LiveOneShotTimerHandle: OneShotTimerHandle {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

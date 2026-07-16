import Foundation

protocol DistractionTimerHandle {
    func cancel()
}

protocol DistractionTimerScheduling {
    func schedule(after interval: TimeInterval, action: @escaping () -> Void) -> DistractionTimerHandle
}

struct LiveDistractionTimerScheduler: DistractionTimerScheduling {
    func schedule(after interval: TimeInterval, action: @escaping () -> Void) -> DistractionTimerHandle {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
        }
        return LiveDistractionTimerHandle(timer: timer)
    }
}

final class LiveDistractionTimerHandle: DistractionTimerHandle {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

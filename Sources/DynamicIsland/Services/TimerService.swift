import AppKit
import Observation

@Observable @MainActor
final class TimerService {
    enum State: Equatable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    private(set) var state: State = .idle
    private(set) var total: TimeInterval = 0

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var alarmTask: Task<Void, Never>?

    var isActive: Bool {
        switch state {
        case .running, .paused: true
        default: false
        }
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var isFinished: Bool { state == .finished }

    func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .running(let end): max(0, end.timeIntervalSince(date))
        case .paused(let remaining): remaining
        default: 0
        }
    }

    func fractionRemaining(at date: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(max(remaining(at: date) / total, 0), 1)
    }

    func start(seconds: TimeInterval) {
        stopAlarm()
        total = seconds
        run(until: Date().addingTimeInterval(seconds))
    }

    func pause() {
        guard case .running(let end) = state else { return }
        finishTask?.cancel()
        state = .paused(remaining: max(0, end.timeIntervalSinceNow))
    }

    func resume() {
        guard case .paused(let remaining) = state else { return }
        run(until: Date().addingTimeInterval(remaining))
    }

    func cancel() {
        finishTask?.cancel()
        stopAlarm()
        state = .idle
    }

    func dismissAlert() {
        stopAlarm()
        if state == .finished { state = .idle }
    }

    private func run(until end: Date) {
        state = .running(end: end)
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, case .running(let current) = self.state, current == end else { return }
            self.finish()
        }
    }

    private func finish() {
        state = .finished
        onFinish?()
        alarmTask = Task { [weak self] in
            for _ in 0..<12 {
                guard !Task.isCancelled else { return }
                NSSound(named: NSSound.Name("Glass"))?.play()
                try? await Task.sleep(for: .seconds(1.4))
            }
            guard !Task.isCancelled else { return }
            self?.dismissAlert()
        }
    }

    private func stopAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

import Foundation
import OSLog

private let logger = Logger(subsystem: "YearAgoPhotoViewer", category: "watchdog")

/// Logs when the main thread stops responding for more than `threshold`.
///
/// A background timer posts a ping to the main queue every 100 ms. If a
/// ping waits longer than the threshold, the stall is logged when it starts
/// and again, with its length, when it ends. Logs use levels macOS keeps
/// on disk, so a hang leaves a trace even without a debugger. To see what
/// blocked the thread, run `sample "Year Ago Photo Viewer" 10` during it.
final class MainThreadWatchdog: @unchecked Sendable {
    // Safe: `timer` is only touched in init; `state` is behind a lock.
    static let threshold: TimeInterval = 0.25

    private struct State {
        var pingSentAt: Date?
        var stallReported = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let timer: DispatchSourceTimer

    init() {
        let queue = DispatchQueue(label: "YearAgoPhotoViewer.watchdog", qos: .utility)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(100), leeway: .milliseconds(20))
        timer.setEventHandler { [state] in Self.tick(state) }
        timer.resume()
    }

    deinit {
        timer.cancel()
    }

    private static func tick(_ state: OSAllocatedUnfairLock<State>) {
        let now = Date()
        enum Action { case ping, reportStall, none }
        let action: Action = state.withLock { state in
            guard let sentAt = state.pingSentAt else {
                state.pingSentAt = now
                return .ping
            }
            if !state.stallReported, now.timeIntervalSince(sentAt) > threshold {
                state.stallReported = true
                return .reportStall
            }
            return .none
        }

        switch action {
        case .ping:
            DispatchQueue.main.async {
                let answered = Date()
                let (sentAt, wasStalled) = state.withLock { state in
                    defer {
                        state.pingSentAt = nil
                        state.stallReported = false
                    }
                    return (state.pingSentAt ?? answered, state.stallReported)
                }
                if wasStalled {
                    let seconds = answered.timeIntervalSince(sentAt)
                    logger.error("Main thread was blocked for \(String(format: "%.2f", seconds), privacy: .public) s")
                }
            }
        case .reportStall:
            logger.error("Main thread not responding (over \(Int(threshold * 1000), privacy: .public) ms)")
        case .none:
            break
        }
    }
}

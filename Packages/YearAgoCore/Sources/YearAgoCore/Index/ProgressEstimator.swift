import Foundation

/// Estimates time left from recent progress. See plan section 3.2.
///
/// No estimate until at least `minimumFraction` is done and
/// `minimumElapsed` has passed: early rates are noisy. The rate comes from
/// the last `window` seconds, so it adapts when a stage speeds up.
public struct ProgressEstimator: Sendable {
    public var minimumFraction: Double
    public var minimumElapsed: TimeInterval
    public var window: TimeInterval

    private var start: Date?
    private var samples: [(time: Date, fraction: Double)] = []

    public init(minimumFraction: Double = 0.1, minimumElapsed: TimeInterval = 20, window: TimeInterval = 30) {
        self.minimumFraction = minimumFraction
        self.minimumElapsed = minimumElapsed
        self.window = window
    }

    /// Records progress (0…1) at a moment.
    public mutating func record(_ fraction: Double, at time: Date) {
        if start == nil { start = time }
        samples.append((time, fraction))
        // Keep one sample older than the window, so the rate spans it fully.
        while samples.count > 2, time.timeIntervalSince(samples[1].time) > window {
            samples.removeFirst()
        }
    }

    /// Seconds left, or nil when there isn't enough data yet.
    public func remaining(at now: Date) -> TimeInterval? {
        guard let start, let latest = samples.last, let oldest = samples.first,
              latest.fraction >= minimumFraction,
              now.timeIntervalSince(start) >= minimumElapsed
        else { return nil }
        if latest.fraction >= 1 { return 0 }
        let span = latest.time.timeIntervalSince(oldest.time)
        let gained = latest.fraction - oldest.fraction
        guard span > 0, gained > 0 else { return nil }
        let rate = gained / span
        return max(0, (1 - latest.fraction) / rate - now.timeIntervalSince(latest.time))
    }

    /// "less than a minute", "about 1 minute", "about 12 minutes",
    /// "about 1 hour 10 minutes".
    public static func describe(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "less than a minute" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return minutes == 1 ? "about 1 minute" : "about \(minutes) minutes" }
        // Over an hour, round to the nearest 5 minutes.
        let rounded = Int((Double(minutes) / 5).rounded()) * 5
        let hours = rounded / 60, rest = rounded % 60
        let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        return rest == 0 ? "about \(hourText)" : "about \(hourText) \(rest) minutes"
    }
}

import Foundation

/// Progress of one sync (or the duplicate check), for the UI.
/// See docs/indexing-ux-plan.md section 3.2.
public struct ScanProgress: Equatable, Sendable {
    public enum Stage: Equatable, Hashable, Sendable {
        /// Waiting for the Photos library to open. macOS can take minutes
        /// the first time, e.g. after a macOS upgrade or on a slow drive.
        case opening
        /// Walking a folder. `total` is nil: the count isn't known yet.
        case finding
        /// Reading dates and sizes, written to the index in batches.
        case reading
        /// Fetching original file names from the Photos library.
        case naming
        /// Pairing, duplicate groups, and visibility.
        case organizing
        /// Hashing same-size files to find duplicates.
        case hashing
    }

    public var stage: Stage
    /// Items done in this stage.
    public var completed: Int
    /// Items in this stage, or nil when not known yet.
    public var total: Int?
    /// Progress of the whole sync, 0…1. Never goes down within a sync.
    public var fraction: Double

    public init(stage: Stage, completed: Int, total: Int? = nil, fraction: Double = 0) {
        self.stage = stage
        self.completed = completed
        self.total = total
        self.fraction = fraction
    }

    /// The whole-sync progress as a whole percentage, 0…100.
    public var percent: Int { Int((fraction * 100).rounded(.down)) }

    /// True while the current stage has no measurable total (opening,
    /// walking a folder without an estimate, organizing).
    public var isIndeterminate: Bool { total == nil }
}

/// Splits a sync's 0…1 progress among its stages, by expected cost.
public struct ProgressPlan: Equatable, Sendable {
    /// Stages in the order they run, with their share of the whole.
    public let stages: [(stage: ScanProgress.Stage, weight: Double)]

    public init(_ stages: [(stage: ScanProgress.Stage, weight: Double)]) {
        let sum = stages.reduce(0) { $0 + $1.weight }
        self.stages = stages.map { ($0.stage, sum > 0 ? $0.weight / sum : 0) }
    }

    public static func == (lhs: ProgressPlan, rhs: ProgressPlan) -> Bool {
        lhs.stages.map(\.stage) == rhs.stages.map(\.stage) && lhs.stages.map(\.weight) == rhs.stages.map(\.weight)
    }

    /// A folder sync: walking, reading new and changed files, organizing.
    public static let folder = ProgressPlan([(.finding, 10), (.reading, 85), (.organizing, 5)])

    /// A Photos library sync. Fetching file names is slow, so when it
    /// happens it gets as much of the bar as reading.
    public static func library(fetchesNames: Bool) -> ProgressPlan {
        fetchesNames
            ? ProgressPlan([(.opening, 5), (.reading, 45), (.naming, 45), (.organizing, 5)])
            : ProgressPlan([(.opening, 5), (.reading, 90), (.organizing, 5)])
    }

    /// The duplicate check.
    public static let duplicates = ProgressPlan([(.hashing, 1)])

    /// Whole-sync progress when `stage` is `ratio` (0…1) done. A stage not
    /// in the plan returns 0, so it never moves the bar (the throttle keeps
    /// the highest value reported so far).
    public func fraction(_ stage: ScanProgress.Stage, ratio: Double) -> Double {
        var start = 0.0
        for entry in stages {
            if entry.stage == stage {
                return min(1, start + entry.weight * min(max(ratio, 0), 1))
            }
            start += entry.weight
        }
        return 0
    }
}

/// Forwards progress at most once per `interval`, so a fast sync can't
/// flood the UI. Stage changes and the end of a stage always go through.
public final class ProgressThrottle: @unchecked Sendable {
    // Safe: mutable state is only touched under `lock`.
    private let lock = NSLock()
    private let interval: TimeInterval
    private let now: @Sendable () -> Date
    private let forward: @Sendable (ScanProgress) -> Void
    private var lastSent: Date?
    private var lastStage: ScanProgress.Stage?
    private var highest = 0.0

    public init(interval: TimeInterval = 0.25,
                now: @escaping @Sendable () -> Date = { Date() },
                forward: @escaping @Sendable (ScanProgress) -> Void) {
        self.interval = interval
        self.now = now
        self.forward = forward
    }

    public func send(_ progress: ScanProgress) {
        var progress = progress
        let shouldSend: Bool = lock.withLock {
            // Never let the bar move backwards.
            highest = max(highest, progress.fraction)
            progress.fraction = highest
            let time = now()
            let stageChanged = progress.stage != lastStage
            let stageDone = progress.total.map { progress.completed >= $0 } ?? false
            let due = lastSent.map { time.timeIntervalSince($0) >= interval } ?? true
            guard stageChanged || stageDone || due else { return false }
            lastSent = time
            lastStage = progress.stage
            return true
        }
        if shouldSend {
            forward(progress)
        }
    }
}

/// Reports a sync's progress: computes the whole-sync fraction from the
/// plan, then throttles.
struct ProgressReporter: Sendable {
    let plan: ProgressPlan
    let throttle: ProgressThrottle

    init(plan: ProgressPlan, onProgress: @escaping @Sendable (ScanProgress) -> Void) {
        self.plan = plan
        self.throttle = ProgressThrottle(forward: onProgress)
    }

    /// A stage with a known total, or with no total at all.
    func report(_ stage: ScanProgress.Stage, _ completed: Int = 0, of total: Int? = nil) {
        let ratio = total.map { $0 > 0 ? Double(completed) / Double($0) : 1 } ?? 0
        throttle.send(ScanProgress(stage: stage, completed: completed, total: total,
                                   fraction: plan.fraction(stage, ratio: ratio)))
    }

    /// Walking a folder: the total isn't known, but the last index's count
    /// is a good estimate for the bar.
    func finding(_ found: Int, estimate: Int) {
        let ratio = estimate > 0 ? Double(found) / Double(estimate) : 0
        throttle.send(ScanProgress(stage: .finding, completed: found, total: nil,
                                   fraction: plan.fraction(.finding, ratio: ratio)))
    }
}

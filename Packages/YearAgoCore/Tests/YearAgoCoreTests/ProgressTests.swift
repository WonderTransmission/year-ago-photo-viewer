import Foundation
import Testing
@testable import YearAgoCore

@Suite struct ProgressPlanTests {
    @Test func folderPlanSplitsTheBar() {
        let plan = ProgressPlan.folder
        #expect(plan.fraction(.finding, ratio: 0) == 0)
        #expect(abs(plan.fraction(.finding, ratio: 1) - 0.10) < 1e-9)
        #expect(abs(plan.fraction(.reading, ratio: 0.5) - 0.525) < 1e-9)
        #expect(abs(plan.fraction(.organizing, ratio: 0) - 0.95) < 1e-9)
        #expect(plan.fraction(.organizing, ratio: 1) == 1)
    }

    @Test func libraryPlanMakesRoomForFileNamesOnlyWhenNeeded() {
        let quick = ProgressPlan.library(fetchesNames: false)
        let named = ProgressPlan.library(fetchesNames: true)
        #expect(abs(quick.fraction(.reading, ratio: 1) - 0.95) < 1e-9)
        #expect(abs(named.fraction(.reading, ratio: 1) - 0.50) < 1e-9)
        #expect(abs(named.fraction(.naming, ratio: 1) - 0.95) < 1e-9)
        // A stage the plan doesn't have never moves the bar.
        #expect(quick.fraction(.naming, ratio: 0.5) == 0)
    }

    @Test func ratiosAreClamped() {
        #expect(ProgressPlan.duplicates.fraction(.hashing, ratio: 7) == 1)
        #expect(ProgressPlan.duplicates.fraction(.hashing, ratio: -1) == 0)
    }

    @Test func percentAndIndeterminate() {
        let progress = ScanProgress(stage: .reading, completed: 1, total: 3, fraction: 0.428)
        #expect(progress.percent == 42)
        #expect(!progress.isIndeterminate)
        #expect(ScanProgress(stage: .opening, completed: 0).isIndeterminate)
    }
}

@Suite struct ProgressThrottleTests {
    /// A controllable clock and an event log.
    private final class Harness: @unchecked Sendable {
        let lock = NSLock()
        var time = Date(timeIntervalSince1970: 0)
        var sent: [ScanProgress] = []
        func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
        var now: Date { lock.withLock { time } }
        func record(_ p: ScanProgress) { lock.withLock { sent.append(p) } }
    }

    @Test func dropsUpdatesFasterThanTheInterval() {
        let h = Harness()
        let throttle = ProgressThrottle(interval: 0.25, now: { h.now }, forward: { h.record($0) })
        for i in 1...100 {
            throttle.send(ScanProgress(stage: .reading, completed: i, total: 1000, fraction: Double(i) / 1000))
            h.advance(0.01)   // 100 updates a second
        }
        // One second of updates: the first, then about one per 0.25 s.
        #expect((4...5).contains(h.sent.count))
    }

    @Test func stageChangesAndStageEndsAlwaysGoThrough() {
        let h = Harness()
        let throttle = ProgressThrottle(interval: 10, now: { h.now }, forward: { h.record($0) })
        throttle.send(ScanProgress(stage: .reading, completed: 0, total: 2))
        throttle.send(ScanProgress(stage: .reading, completed: 1, total: 2))   // dropped
        throttle.send(ScanProgress(stage: .reading, completed: 2, total: 2))   // stage done
        throttle.send(ScanProgress(stage: .organizing, completed: 0))         // new stage
        #expect(h.sent.map(\.completed) == [0, 2, 0])
    }

    @Test func neverMovesBackwards() {
        let h = Harness()
        let throttle = ProgressThrottle(interval: 0, now: { h.now }, forward: { h.record($0) })
        throttle.send(ScanProgress(stage: .reading, completed: 5, total: 10, fraction: 0.5))
        throttle.send(ScanProgress(stage: .reading, completed: 4, total: 10, fraction: 0.4))
        #expect(h.sent.map(\.fraction) == [0.5, 0.5])
    }
}

@Suite struct ProgressEstimatorTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func noEstimateUntilEnoughProgressAndTime() {
        var estimator = ProgressEstimator()
        estimator.record(0.0, at: start)
        estimator.record(0.05, at: start + 30)   // too little progress
        #expect(estimator.remaining(at: start + 30) == nil)

        var early = ProgressEstimator()
        early.record(0.0, at: start)
        early.record(0.5, at: start + 10)        // too little time
        #expect(early.remaining(at: start + 10) == nil)
    }

    @Test func steadyRateGivesTheRemainingTime() throws {
        var estimator = ProgressEstimator()
        for second in stride(from: 0, through: 60, by: 5) {
            estimator.record(Double(second) / 200, at: start + Double(second))   // 0.5% a second
        }
        // 30% done at 60 s; 70% left at 0.5%/s = 140 s.
        let left = try #require(estimator.remaining(at: start + 60))
        #expect(abs(left - 140) < 0.5)
    }

    @Test func usesTheRecentRate() throws {
        var estimator = ProgressEstimator(window: 30)
        // Slow for the first minute, then four times faster.
        for second in stride(from: 0, through: 60, by: 5) {
            estimator.record(Double(second) * 0.002, at: start + Double(second))
        }
        for second in stride(from: 65, through: 120, by: 5) {
            estimator.record(0.12 + Double(second - 60) * 0.008, at: start + Double(second))
        }
        // At 120 s: 0.6 done, recent rate 0.008/s → 50 s left.
        let left = try #require(estimator.remaining(at: start + 120))
        #expect(abs(left - 50) < 1)
    }

    @Test func doneMeansZero() {
        var estimator = ProgressEstimator()
        estimator.record(0, at: start)
        estimator.record(1, at: start + 25)
        #expect(estimator.remaining(at: start + 25) == 0)
    }

    // Seconds: 10, 75, 12 min, 60 min, 70 min, 128 min, 178 min.
    @Test(arguments: zip(
        [10.0, 75.0, 720.0, 3600.0, 4200.0, 7680.0, 10680.0],
        ["less than a minute", "about 1 minute", "about 12 minutes", "about 1 hour",
         "about 1 hour 10 minutes", "about 2 hours 10 minutes", "about 3 hours"]))
    func describesDurations(seconds: Double, text: String) {
        #expect(ProgressEstimator.describe(seconds) == text)
    }
}

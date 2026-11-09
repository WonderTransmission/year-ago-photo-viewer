/// A date range in a past year: the photos shown for "N years ago".
public struct DateWindow: Equatable, Sendable {
    /// N: how many years back. 1 means last year.
    public var yearsAgo: Int
    /// W: the window length in weeks.
    public var weeks: Int
    /// First and last second of the window, inclusive.
    public var range: ClosedRange<LocalDateTime>

    public init(yearsAgo: Int, weeks: Int, range: ClosedRange<LocalDateTime>) {
        self.yearsAgo = yearsAgo
        self.weeks = weeks
        self.range = range
    }
}

/// Computes viewing windows. See proposal section 4.1.
///
/// For N years ago and W weeks, the window runs from the start of
/// (today − N years − W weeks) to the end of (today − N years).
public struct WindowCalculator: Sendable {
    /// Window lengths the user can choose.
    public static let allowedWeeks = 1...6

    /// Upper bound on how far back `maxYearsAgo` searches.
    static let yearSearchLimit = 1_000

    public init() {}

    /// The day N years before `today`. 29 Feb maps to 28 Feb in non-leap years.
    /// Returns the start of that day.
    public func anniversary(of today: LocalDateTime, yearsAgo: Int) -> LocalDateTime {
        today.startOfDay.adding(.year, -yearsAgo)
    }

    /// The window for `yearsAgo` (N ≥ 1). `weeks` is clamped to 1...6.
    public func window(today: LocalDateTime, yearsAgo: Int, weeks: Int) -> DateWindow {
        precondition(yearsAgo >= 1, "yearsAgo must be at least 1")
        let weeks = min(max(weeks, Self.allowedWeeks.lowerBound), Self.allowedWeeks.upperBound)
        let anchor = anniversary(of: today, yearsAgo: yearsAgo)
        let start = anchor.adding(.day, -7 * weeks)
        return DateWindow(yearsAgo: yearsAgo, weeks: weeks, range: start...anchor.endOfDay)
    }

    /// The largest N whose anniversary day ends on or after `oldest`.
    /// This is the "age" of the oldest photo in whole years.
    /// Returns 0 when `oldest` is more recent than last year's anniversary.
    public func maxYearsAgo(oldest: LocalDateTime, today: LocalDateTime) -> Int {
        var years = 0
        while years < Self.yearSearchLimit,
              anniversary(of: today, yearsAgo: years + 1).endOfDay >= oldest {
            years += 1
        }
        return years
    }
}

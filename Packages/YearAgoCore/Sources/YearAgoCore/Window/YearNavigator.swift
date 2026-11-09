/// Which past years the viewer offers, and how to move between them.
/// See proposal sections 4.2, 4.2.1, and 4.3.
///
/// "Next year" means one year further back (N + 1); "previous year" means
/// one year more recent (N − 1).
public struct YearNavigator: Equatable, Sendable {
    /// Photo counts per year: `photoCounts[0]` is N = 1. Its length is the
    /// age of the oldest photo in whole years.
    public let photoCounts: [Int]
    public let showEmptyYears: Bool

    public init(photoCounts: [Int], showEmptyYears: Bool) {
        self.photoCounts = photoCounts
        self.showEmptyYears = showEmptyYears
    }

    /// Counts each year's window in `timeline`.
    public static func build(
        timeline: PhotoTimeline,
        today: LocalDateTime,
        weeks: Int,
        showEmptyYears: Bool,
        calculator: WindowCalculator = WindowCalculator()
    ) -> YearNavigator {
        let maxYears = timeline.oldest.map { calculator.maxYearsAgo(oldest: $0, today: today) } ?? 0
        let counts = (0..<maxYears).map { offset in
            timeline.count(in: calculator.window(today: today, yearsAgo: offset + 1, weeks: weeks).range)
        }
        return YearNavigator(photoCounts: counts, showEmptyYears: showEmptyYears)
    }

    /// The oldest N the source reaches; 0 if it has nothing older than a year.
    public var maxYearsAgo: Int { photoCounts.count }

    /// True when at least one year has photos in its window.
    public var hasAnyPhotos: Bool { photoCounts.contains { $0 > 0 } }

    /// Photos in year N's window; 0 for years outside the source.
    public func count(yearsAgo: Int) -> Int {
        photoCounts.indices.contains(yearsAgo - 1) ? photoCounts[yearsAgo - 1] : 0
    }

    /// The years to offer, in order (1, 2, 3, …). Never empty: with no
    /// photos at all it is `[1]`, so the empty panel still has a year.
    public var years: [Int] {
        let all = Array(1...max(maxYearsAgo, 1))
        let visible = showEmptyYears ? all : all.filter { count(yearsAgo: $0) > 0 }
        return visible.isEmpty ? [1] : visible
    }

    /// Where the viewer opens: N = 1, or the nearest year with photos when
    /// empty years are hidden.
    public var initialYear: Int { years[0] }

    /// The next year further back, or nil at the oldest.
    public func next(after yearsAgo: Int) -> Int? {
        years.first { $0 > yearsAgo }
    }

    /// The next more recent year, or nil at the newest.
    public func previous(before yearsAgo: Int) -> Int? {
        years.last { $0 < yearsAgo }
    }

    /// `yearsAgo` if it is offered, otherwise the closest offered year.
    /// Ties go to the more recent year.
    public func nearest(to yearsAgo: Int) -> Int {
        years.min { lhs, rhs in
            let (dl, dr) = (abs(lhs - yearsAgo), abs(rhs - yearsAgo))
            return dl != dr ? dl < dr : lhs < rhs
        } ?? 1
    }
}

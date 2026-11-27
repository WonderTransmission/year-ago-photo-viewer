/// Which way the viewer travels through the years. See
/// docs/oldest-first-navigation-implementation-plan.md.
public enum YearDirection: String, CaseIterable, Codable, Sendable {
    /// Start at the most recent year and go back in time (the default).
    case newestFirst
    /// Start at the oldest year and go forward in time.
    case oldestFirst
}

/// Calendar-based and direction-aware moves. "Earlier" means an older
/// calendar year (more years ago); "later" means a more recent one.
extension YearNavigator {
    /// The next older offered year, or nil at the oldest.
    public func earlier(than yearsAgo: Int) -> Int? {
        next(after: yearsAgo)
    }

    /// The next more recent offered year, or nil at the most recent.
    public func later(than yearsAgo: Int) -> Int? {
        previous(before: yearsAgo)
    }

    /// One year onward in the direction of travel.
    public func forward(from yearsAgo: Int, direction: YearDirection) -> Int? {
        direction == .newestFirst ? earlier(than: yearsAgo) : later(than: yearsAgo)
    }

    /// One year back against the direction of travel.
    public func back(from yearsAgo: Int, direction: YearDirection) -> Int? {
        direction == .newestFirst ? later(than: yearsAgo) : earlier(than: yearsAgo)
    }

    /// The next year with photos onward in the direction of travel,
    /// skipping empty years. For arrow keys that carry on past a year's end.
    public func forwardWithPhotos(from yearsAgo: Int, direction: YearDirection) -> Int? {
        direction == .newestFirst ? yearsWithPhotos.first { $0 > yearsAgo }
                                  : yearsWithPhotos.last { $0 < yearsAgo }
    }

    /// The previous year with photos against the direction of travel,
    /// skipping empty years.
    public func backWithPhotos(from yearsAgo: Int, direction: YearDirection) -> Int? {
        direction == .newestFirst ? yearsWithPhotos.last { $0 < yearsAgo }
                                  : yearsWithPhotos.first { $0 > yearsAgo }
    }

    /// Years with photos in their window, most recent first. Unlike
    /// `years`, never includes empty years.
    public var yearsWithPhotos: [Int] {
        (1...max(maxYearsAgo, 1)).filter { count(yearsAgo: $0) > 0 }
    }

    /// The oldest year with photos, or nil if none has any.
    public var oldestWithPhotos: Int? { yearsWithPhotos.last }

    /// The most recent year with photos, or nil if none has any.
    public var newestWithPhotos: Int? { yearsWithPhotos.first }

    /// Where travel starts: the most recent year with photos, or the
    /// oldest. Nil if no year has photos.
    public func start(direction: YearDirection) -> Int? {
        direction == .newestFirst ? newestWithPhotos : oldestWithPhotos
    }

    /// Where travel ends: the opposite end from `start(direction:)`.
    public func end(direction: YearDirection) -> Int? {
        direction == .newestFirst ? oldestWithPhotos : newestWithPhotos
    }

    /// Where the viewer opens. Newest first behaves as before
    /// (`initialYear`); oldest first opens at the oldest year with photos.
    public func initialYear(direction: YearDirection) -> Int {
        direction == .newestFirst ? initialYear : (oldestWithPhotos ?? initialYear)
    }

    /// The offered years in travel order, for the year menu.
    public func ordered(direction: YearDirection) -> [Int] {
        direction == .newestFirst ? years : years.reversed()
    }
}

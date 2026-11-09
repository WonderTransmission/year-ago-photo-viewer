/// One past year's window and its photos, for at-a-glance views: the menu
/// bar item and the widget. See proposal sections 5.2 and 5.3.
public struct OnThisDay: Equatable, Sendable {
    public var window: DateWindow
    public var photos: [PhotoItem]

    public init(window: DateWindow, photos: [PhotoItem]) {
        self.window = window
        self.photos = photos
    }

    public var yearsAgo: Int { window.yearsAgo }

    /// The first `count` years the viewer offers, in order, each with its
    /// photos.
    ///
    /// With empty years shown this is N = 1, 2, 3…, some possibly empty.
    /// With them hidden it is the nearest years that have photos. Either
    /// way the list starts with the viewer's initial year, and is never
    /// empty when `count` ≥ 1.
    public static func years(
        count: Int,
        timeline: PhotoTimeline,
        navigator: YearNavigator,
        today: LocalDateTime,
        weeks: Int,
        calculator: WindowCalculator = WindowCalculator()
    ) -> [OnThisDay] {
        navigator.years.prefix(max(count, 0)).map { yearsAgo in
            let window = calculator.window(today: today, yearsAgo: yearsAgo, weeks: weeks)
            return OnThisDay(window: window, photos: timeline.photos(in: window.range))
        }
    }

    /// Up to `limit` photos spread evenly across the window, oldest first.
    /// Gives a varied selection rather than the first few of one day.
    public func spread(limit: Int) -> [PhotoItem] {
        guard limit > 0, photos.count > limit else { return Array(photos.prefix(max(limit, 0))) }
        if limit == 1 { return [photos[photos.count / 2]] }
        let step = Double(photos.count - 1) / Double(limit - 1)
        return (0..<limit).map { photos[Int((Double($0) * step).rounded())] }
    }
}

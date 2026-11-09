import Foundation

/// What the widget shows, written by the app into the shared App Group
/// folder. The widget reads only this file and the images it names.
/// See implementation plan M10 and proposal section 5.3.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let fileName = "snapshot.json"

    /// The calendar day the snapshot was made for.
    public var day: Day
    /// True when the app has at least one source.
    public var hasSources: Bool
    /// The viewer's first few years, in order (up to three).
    public var years: [Year]

    public init(day: Day, hasSources: Bool, years: [Year]) {
        self.day = day
        self.hasSources = hasSources
        self.years = years
    }

    public struct Day: Codable, Equatable, Sendable {
        public var year: Int
        public var month: Int
        public var day: Int

        public init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        /// The day `date` falls on in `calendar`.
        public init(_ date: Date, calendar: Calendar = .current) {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
        }

        /// Noon on this day, for display.
        public func date(calendar: Calendar = .current) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        }
    }

    public struct Year: Codable, Equatable, Sendable {
        public var yearsAgo: Int
        /// The calendar year shown, e.g. 2025.
        public var calendarYear: Int
        /// The window's dates, already formatted, e.g. "Nov 1 – 8, 2025".
        public var rangeText: String
        /// All photos in the window, not just those in `photos`.
        public var photoCount: Int
        /// Up to six photos, spread across the window.
        public var photos: [Photo]

        public init(yearsAgo: Int, calendarYear: Int, rangeText: String, photoCount: Int, photos: [Photo]) {
            self.yearsAgo = yearsAgo
            self.calendarYear = calendarYear
            self.rangeText = rangeText
            self.photoCount = photoCount
            self.photos = photos
        }
    }

    public struct Photo: Codable, Equatable, Sendable {
        /// The viewer's photo ID, for deep links.
        public var id: String
        /// A JPEG thumbnail's file name in the shared folder.
        public var imageFile: String
        /// The photo's date, already formatted.
        public var dateText: String

        public init(id: String, imageFile: String, dateText: String) {
            self.id = id
            self.imageFile = imageFile
            self.dateText = dateText
        }
    }

    /// True when the snapshot was made for the day `date` falls on.
    public func isCurrent(on date: Date, calendar: Calendar = .current) -> Bool {
        day == Day(date, calendar: calendar)
    }

    /// Every image file the snapshot refers to.
    public var imageFiles: Set<String> {
        Set(years.flatMap { $0.photos.map(\.imageFile) })
    }

    // MARK: Reading and writing

    public static func read(from folder: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes atomically, so the widget never reads a half-written file.
    public func write(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// `yearago://photo?id=<photo id>&years=<N>` links from the widget into the app.
public enum WidgetDeepLink {
    public static let scheme = "yearago"

    public static func url(photoID: String, yearsAgo: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "photo"
        components.queryItems = [
            URLQueryItem(name: "id", value: photoID),
            URLQueryItem(name: "years", value: String(yearsAgo)),
        ]
        return components.url!
    }

    /// A link that just opens the app at year N.
    public static func url(yearsAgo: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "year"
        components.queryItems = [URLQueryItem(name: "years", value: String(yearsAgo))]
        return components.url!
    }

    /// The photo ID (if any) and year in a deep link, or nil if `url` is not one.
    public static func parse(_ url: URL) -> (photoID: String?, yearsAgo: Int)? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let years = components.queryItems?.first(where: { $0.name == "years" })?.value.flatMap(Int.init),
              years >= 1
        else { return nil }
        let id = components.queryItems?.first(where: { $0.name == "id" })?.value
        switch components.host {
        case "photo": return id.map { ($0, years) }
        case "year": return (nil, years)
        default: return nil
        }
    }
}

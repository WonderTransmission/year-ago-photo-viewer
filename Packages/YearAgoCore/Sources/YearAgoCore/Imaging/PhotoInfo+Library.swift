import Foundation

/// What PhotoKit knows about an asset without reading its file. The app
/// fills this from a `PHAsset`; keeping it plain makes it testable here.
public struct LibraryAssetDetails: Equatable, Sendable {
    /// Where Photos says the photo was taken, with fixes made in Photos.
    public struct Location: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        /// Metres above sea level, if known.
        public var altitude: Double?
        /// Degrees from true north the camera moved toward, if known.
        public var course: Double?
        /// Metres per second, if known.
        public var speed: Double?
        /// Horizontal accuracy in metres, if known.
        public var accuracy: Double?

        public init(latitude: Double, longitude: Double, altitude: Double? = nil,
                    course: Double? = nil, speed: Double? = nil, accuracy: Double? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.course = course
            self.speed = speed
            self.accuracy = accuracy
        }
    }

    public var created: Date?
    public var modified: Date?
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Kinds such as "Live Photo" or "Screenshot", in display order.
    public var kinds: [String]
    public var isFavorite: Bool
    /// The original file name, if the index has it.
    public var fileName: String?
    public var location: Location?

    public init(created: Date?, modified: Date?, pixelWidth: Int, pixelHeight: Int,
                kinds: [String] = [], isFavorite: Bool = false, fileName: String? = nil,
                location: Location? = nil) {
        self.created = created
        self.modified = modified
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kinds = kinds
        self.isFavorite = isFavorite
        self.fileName = fileName
        self.location = location
    }
}

extension PhotoInfo {
    /// The closing note for Photos library items.
    public static let libraryNote = "Full camera details aren't available for Photos library items."

    /// Basic info for a Photos library item (plan decision: no full EXIF).
    /// Dates show in `timeZone`, with its offset.
    public static func libraryItem(_ details: LibraryAssetDetails, timeZone: TimeZone = .current) -> PhotoInfo {
        var image: [Row] = []
        if let name = details.fileName { image.append(Row("File name", name)) }
        if details.pixelWidth > 0, details.pixelHeight > 0 {
            image.append(Row("Size", "\(details.pixelWidth) × \(details.pixelHeight) pixels"))
        }
        if !details.kinds.isEmpty { image.append(Row("Kind", details.kinds.joined(separator: ", "))) }
        if details.isFavorite { image.append(Row("Favorite", "Yes")) }

        var dates: [Row] = []
        if let created = details.created { dates.append(Row("Taken", format(created, timeZone))) }
        if let modified = details.modified { dates.append(Row("Modified", format(modified, timeZone))) }

        var location: [Row] = []
        let coordinate = details.location.flatMap { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        if let coordinate, let place = details.location {
            location.append(Row("Coordinates", coordinate.formatted))
            if let altitude = place.altitude {
                location.append(Row("Altitude", "\(Format.decimal(altitude, digits: 1)) m"))
            }
            if let course = place.course {
                location.append(Row("Direction", "\(Format.decimal(course))° (true north)"))
            }
            if let speed = place.speed {
                location.append(Row("Speed", "\(Format.decimal(speed * 3.6, digits: 1)) km/h"))
            }
            if let accuracy = place.accuracy {
                location.append(Row("Accuracy", "± \(Format.decimal(accuracy, digits: 1)) m"))
            }
        }

        return PhotoInfo(sections: [Section("Image", image), Section("Dates", dates), Section("Location", location)],
                         coordinate: coordinate, note: libraryNote)
    }

    /// "2025-11-03 10:00:00 +01:00", matching how file dates show.
    static func format(_ date: Date, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss xxx"
        return formatter.string(from: date)
    }
}

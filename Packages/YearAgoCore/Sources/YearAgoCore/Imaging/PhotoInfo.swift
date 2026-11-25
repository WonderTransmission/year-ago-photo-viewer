import Foundation

/// Everything the Photo Info popover shows about one photo: labelled
/// values in sections, and the location if there is one.
public struct PhotoInfo: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var label: String
        public var value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public var title: String
        public var rows: [Row]
        public var id: String { title }

        public init(_ title: String, _ rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    public var sections: [Section]
    /// Where the photo was taken, if known.
    public var coordinate: Coordinate?
    /// Values left out because they're binary data, such as maker notes.
    public var skippedBinaryCount: Int
    /// A closing remark, e.g. that some details aren't available.
    public var note: String?

    public init(sections: [Section], coordinate: Coordinate? = nil,
                skippedBinaryCount: Int = 0, note: String? = nil) {
        self.sections = sections.filter { !$0.rows.isEmpty }
        self.coordinate = coordinate
        self.skippedBinaryCount = skippedBinaryCount
        self.note = note
    }

    /// The section with `title`, if present.
    public func section(_ title: String) -> Section? {
        sections.first { $0.title == title }
    }

    /// The value of the first row labelled `label` in any section.
    public func value(_ label: String) -> String? {
        sections.lazy.flatMap(\.rows).first { $0.label == label }?.value
    }

    /// Every row as "Label: Value" lines under section titles, for Copy All.
    public var plainText: String {
        sections.map { section in
            ([section.title] + section.rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

/// A latitude and longitude in signed decimal degrees.
public struct Coordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    /// Nil for out-of-range values, and for 0, 0, which cameras write when
    /// they have no fix.
    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude),
              latitude != 0 || longitude != 0
        else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "48.85837° N, 2.29448° E".
    public var formatted: String {
        func part(_ value: Double, _ positive: String, _ negative: String) -> String {
            String(format: "%.5f° %@", abs(value), value < 0 ? negative : positive)
        }
        return "\(part(latitude, "N", "S")), \(part(longitude, "E", "W"))"
    }

    /// A URL that opens the Maps app at this point, with a pin labelled
    /// `label`. Opening it hands the location to Maps; this app makes no
    /// network request.
    public func mapsURL(label: String) -> URL {
        var components = URLComponents()
        components.scheme = "maps"
        components.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)),
            URLQueryItem(name: "q", value: label),
        ]
        return components.url!
    }
}

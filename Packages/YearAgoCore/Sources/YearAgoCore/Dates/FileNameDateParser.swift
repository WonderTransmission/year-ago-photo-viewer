import Foundation

/// Extracts a date and time from a photo's file name.
///
/// Patterns are tried in order. Each is anchored to the start of the name,
/// so a date buried mid-name is ignored. Impossible dates are rejected.
///
/// Not `Sendable`: `Regex` is not. Give each task its own parser.
public struct FileNameDateParser {
    /// A named regular expression with these named groups:
    /// `y`, `mo`, `d`, `h`, `mi`, `s`, and optionally `ampm`.
    public struct Pattern: Sendable {
        public let name: String
        public let source: String

        public init(name: String, source: String) {
            self.name = name
            self.source = source
        }
    }

    public static let defaultPatterns: [Pattern] = [
        // "Screen Shot 2022-03-16 at 1.50.15 PM", "Screenshot 2022-03-16 at 13.50.15".
        // macOS 14+ puts a narrow no-break space before AM/PM; \s matches it.
        Pattern(name: "macOS screenshot", source: #"^Screen ?[Ss]hot (?<y>\d{4})-(?<mo>\d{2})-(?<d>\d{2}) at (?<h>\d{1,2})\.(?<mi>\d{2})\.(?<s>\d{2})(?:\s*(?<ampm>[AaPp][Mm]))?"#),
        // "IMG_20220316_135015", "PXL_20220316_135015123", "MVIMG_20220316_135015".
        Pattern(name: "Android camera", source: #"^(?:IMG|PXL|MVIMG)_(?<y>\d{4})(?<mo>\d{2})(?<d>\d{2})_(?<h>\d{2})(?<mi>\d{2})(?<s>\d{2})"#),
        // "2022-03-16 13.50.15" (Dropbox camera uploads).
        Pattern(name: "Dropbox", source: #"^(?<y>\d{4})-(?<mo>\d{2})-(?<d>\d{2}) (?<h>\d{2})\.(?<mi>\d{2})\.(?<s>\d{2})"#),
        // "20220316_135015" (Samsung and others).
        Pattern(name: "Samsung", source: #"^(?<y>\d{4})(?<mo>\d{2})(?<d>\d{2})_(?<h>\d{2})(?<mi>\d{2})(?<s>\d{2})(?!\d)"#),
    ]

    private let compiled: [(name: String, regex: Regex<AnyRegexOutput>)]

    /// - Throws: if a pattern is not a valid regular expression.
    public init(patterns: [Pattern]) throws {
        compiled = try patterns.map { ($0.name, try Regex($0.source)) }
    }

    /// A new parser using `defaultPatterns`.
    public static func standard() -> FileNameDateParser {
        do {
            return try FileNameDateParser(patterns: defaultPatterns)
        } catch {
            preconditionFailure("Built-in file name pattern is invalid: \(error)")
        }
    }

    /// Returns the date in `fileName`, or nil if no pattern yields a valid date.
    /// Pass a file name, not a path.
    public func date(fromFileName fileName: String) -> LocalDateTime? {
        for (_, regex) in compiled {
            guard let match = fileName.firstMatch(of: regex) else { continue }
            if let date = Self.date(from: match.output) {
                return date
            }
        }
        return nil
    }

    private static func date(from output: AnyRegexOutput) -> LocalDateTime? {
        func int(_ name: String) -> Int? {
            output[name]?.substring.flatMap { Int($0) }
        }
        guard let year = int("y"), let month = int("mo"), let day = int("d"),
              var hour = int("h"), let minute = int("mi"), let second = int("s")
        else { return nil }

        if let marker = output["ampm"]?.substring?.uppercased() {
            guard (1...12).contains(hour) else { return nil }
            switch (marker, hour) {
            case ("AM", 12): hour = 0
            case ("PM", 12): break
            case ("PM", _): hour += 12
            default: break
            }
        }

        // Years before photography are almost certainly not dates.
        guard year >= 1900 else { return nil }
        return LocalDateTime(year: year, month: month, day: day,
                             hour: hour, minute: minute, second: second)
    }
}

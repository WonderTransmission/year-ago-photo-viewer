import Foundation

/// A wall-clock date and time with no time zone ("floating" time).
///
/// Stored as whole seconds since 1970-01-01 00:00:00, read as if in UTC.
/// EXIF dates and file-name dates carry no time zone, so the app keeps every
/// photo date in this form. File-system and Photos timestamps are converted
/// using the Mac's time zone when they are read.
public struct LocalDateTime: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var seconds: Int64

    public init(seconds: Int64) {
        self.seconds = seconds
    }

    /// Creates a value from calendar fields. Returns nil for impossible
    /// dates or times, such as month 13, 30 February, or hour 24.
    public init?(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        guard (1...9999).contains(year),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second)
        else { return nil }

        let components = DateComponents(year: year, month: month, day: day,
                                        hour: hour, minute: minute, second: second)
        // Calendar silently rolls 30 Feb over to 2 Mar, so confirm the day survived.
        guard let date = Self.calendar.date(from: components),
              Self.calendar.component(.day, from: date) == day
        else { return nil }

        self.seconds = Int64(date.timeIntervalSince1970)
    }

    /// Converts an absolute instant to the wall-clock time in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let offset = timeZone.secondsFromGMT(for: date)
        let utcSeconds = Int64(date.timeIntervalSince1970.rounded(.down))
        self.seconds = utcSeconds + Int64(offset)
    }

    /// The calendar fields of this value.
    public var components: DateComponents {
        Self.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: floatingDate)
    }

    /// Midnight at the start of this value's day.
    public var startOfDay: LocalDateTime {
        LocalDateTime(Self.calendar.startOfDay(for: floatingDate))
    }

    /// The last second of this value's day.
    public var endOfDay: LocalDateTime {
        LocalDateTime(seconds: startOfDay.seconds + 86_399)
    }

    /// Adds calendar units. Month and year steps clamp to the end of the
    /// month, so 29 Feb minus one year is 28 Feb.
    public func adding(_ component: Calendar.Component, _ value: Int) -> LocalDateTime {
        guard let date = Self.calendar.date(byAdding: component, value: value, to: floatingDate) else {
            preconditionFailure("Date arithmetic overflowed: \(self) + \(value) \(component)")
        }
        return LocalDateTime(date)
    }

    public var description: String {
        let c = components
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        lhs.seconds < rhs.seconds
    }

    // MARK: - Internals

    /// Gregorian calendar fixed to UTC. All floating-time arithmetic uses it.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// This value as a `Date` in UTC. Only meaningful with `calendar`.
    private var floatingDate: Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private init(_ floatingDate: Date) {
        self.seconds = Int64(floatingDate.timeIntervalSince1970.rounded(.down))
    }
}

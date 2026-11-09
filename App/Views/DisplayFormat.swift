import Foundation
import YearAgoCore

/// User-facing text for dates and counts.
///
/// Photo dates are wall-clock values with no time zone, so they are
/// formatted as UTC dates whose fields equal the wall-clock fields.
enum DisplayFormat {
    /// "1 year ago", "3 years ago".
    static func yearsAgo(_ years: Int) -> String {
        years == 1 ? "1 year ago" : "\(years) years ago"
    }

    /// The window's dates, e.g. "Nov 1 – 8, 2025" (locale-dependent).
    static func range(_ window: DateWindow) -> String {
        let start = window.range.lowerBound.dateForDisplayInUTC
        let end = window.range.upperBound.dateForDisplayInUTC
        let style = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)
        return (start..<end).formatted(style)
    }

    /// A photo's date and time, e.g. "Wed, Nov 5, 2025 at 2:32 PM".
    static func photoDate(_ date: LocalDateTime) -> String {
        let style = Date.FormatStyle(date: .complete, time: .shortened, timeZone: .gmt)
        return date.dateForDisplayInUTC.formatted(style)
    }

    /// "12 of 37", "37 photos", or "No photos".
    static func position(_ stepper: PhotoStepper) -> String {
        if let index = stepper.currentIndex {
            return "\(index + 1) of \(stepper.count)"
        }
        switch stepper.count {
        case 0: return "No photos"
        case 1: return "1 photo"
        default: return "\(stepper.count) photos"
        }
    }
}

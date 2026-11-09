import Foundation

/// A file's file-system timestamps, as wall-clock times.
public struct FileDates: Equatable, Sendable {
    public var modified: LocalDateTime?
    public var created: LocalDateTime?

    public init(modified: LocalDateTime?, created: LocalDateTime?) {
        self.modified = modified
        self.created = created
    }
}

/// Reads modified and created dates from the file system.
public enum FileDateReader {
    /// Returns the file's dates converted to wall-clock time in `timeZone`.
    /// Missing values are nil, as is everything if the file cannot be read.
    public static func dates(at url: URL, timeZone: TimeZone = .current) -> FileDates {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return FileDates(
            modified: values?.contentModificationDate.map { LocalDateTime($0, in: timeZone) },
            created: values?.creationDate.map { LocalDateTime($0, in: timeZone) }
        )
    }
}

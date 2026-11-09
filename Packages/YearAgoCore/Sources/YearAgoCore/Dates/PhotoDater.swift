import Foundation

/// Reads one kind of date from photo files.
///
/// Not `Sendable`, because the file-name parser is not. Create one per task.
public struct PhotoDater {
    public let source: DateSourceKind
    public let timeZone: TimeZone
    private let fileNameParser: FileNameDateParser?

    public init(source: DateSourceKind, timeZone: TimeZone = .current) {
        self.source = source
        self.timeZone = timeZone
        self.fileNameParser = source == .fileName ? FileNameDateParser.standard() : nil
    }

    /// The file's date from this dater's source, or nil if it has none.
    public func date(for url: URL) -> LocalDateTime? {
        switch source {
        case .fileName:
            fileNameParser?.date(fromFileName: url.lastPathComponent)
        case .modified:
            FileDateReader.dates(at: url, timeZone: timeZone).modified
        case .created:
            FileDateReader.dates(at: url, timeZone: timeZone).created
        case .exif:
            ExifDateReader.captureDate(at: url)
        }
    }
}

import Foundation

/// A dated photo ready to show.
public struct PhotoItem: Identifiable, Hashable, Sendable {
    /// Stable within one source: the path relative to the source folder.
    public var id: String { relativePath }
    public var url: URL
    public var relativePath: String
    public var kind: MediaKind
    /// The date from the source's chosen date source.
    public var date: LocalDateTime

    public init(url: URL, relativePath: String, kind: MediaKind, date: LocalDateTime) {
        self.url = url
        self.relativePath = relativePath
        self.kind = kind
        self.date = date
    }

    public var fileName: String { url.lastPathComponent }
}

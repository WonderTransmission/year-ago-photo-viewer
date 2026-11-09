import Foundation

/// A dated photo ready to show.
public struct PhotoItem: Identifiable, Hashable, Sendable {
    /// Unique across sources: "<source id>:<relative path>".
    public var id: String { "\(sourceID):\(relativePath)" }
    /// The photo source this photo comes from.
    public var sourceID: Int64
    public var url: URL
    /// Path relative to the source folder.
    public var relativePath: String
    public var kind: MediaKind
    /// The date from the source's chosen date source.
    public var date: LocalDateTime

    public init(sourceID: Int64 = 0, url: URL, relativePath: String, kind: MediaKind, date: LocalDateTime) {
        self.sourceID = sourceID
        self.url = url
        self.relativePath = relativePath
        self.kind = kind
        self.date = date
    }

    public var fileName: String { url.lastPathComponent }
}

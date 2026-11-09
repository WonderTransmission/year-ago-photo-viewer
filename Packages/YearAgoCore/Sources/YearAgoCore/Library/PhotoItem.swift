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
    /// True for a JPEG/HEIC shown in place of its RAW partner.
    public var hasRawPartner: Bool

    public init(sourceID: Int64 = 0, url: URL, relativePath: String, kind: MediaKind,
                date: LocalDateTime, hasRawPartner: Bool = false) {
        self.sourceID = sourceID
        self.url = url
        self.relativePath = relativePath
        self.kind = kind
        self.date = date
        self.hasRawPartner = hasRawPartner
    }

    public var fileName: String { url.lastPathComponent }

    /// "RAW+JPEG", "RAW+HEIC", "RAW", or nil for an ordinary image.
    public var rawBadge: String? {
        if kind == .raw { return "RAW" }
        guard hasRawPartner else { return nil }
        let ext = url.pathExtension.lowercased()
        return ext == "heic" || ext == "heif" ? "RAW+HEIC" : "RAW+JPEG"
    }
}

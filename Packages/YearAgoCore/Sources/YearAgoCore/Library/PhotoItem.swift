import Foundation

/// A dated photo ready to show.
public struct PhotoItem: Identifiable, Hashable, Sendable {
    /// Unique across sources: "<source id>:<relative path or asset ID>".
    public var id: String { "\(sourceID):\(relativePath)" }
    /// The photo source this photo comes from.
    public var sourceID: Int64
    /// The file, or for a Photos library item a placeholder URL (see
    /// `libraryURL(for:)`). Use `assetIdentifier` to load library items.
    public var url: URL
    /// Path relative to the source folder, or the library asset ID.
    public var relativePath: String
    public var kind: MediaKind
    /// The date from the source's chosen date source.
    public var date: LocalDateTime
    /// True for a JPEG/HEIC shown in place of its RAW partner.
    public var hasRawPartner: Bool
    /// The PhotoKit local identifier, for Photos library items.
    public var assetIdentifier: String?
    /// The file name recorded in the index, if any. Library items only
    /// have one once their original file names have been fetched.
    public var storedFileName: String?

    public init(sourceID: Int64 = 0, url: URL, relativePath: String, kind: MediaKind,
                date: LocalDateTime, hasRawPartner: Bool = false,
                assetIdentifier: String? = nil, storedFileName: String? = nil) {
        self.sourceID = sourceID
        self.url = url
        self.relativePath = relativePath
        self.kind = kind
        self.date = date
        self.hasRawPartner = hasRawPartner
        self.assetIdentifier = assetIdentifier
        self.storedFileName = storedFileName
    }

    /// True for photos from the Photos library.
    public var isLibraryAsset: Bool { assetIdentifier != nil }

    /// The name to show: the file name, or "Photos item" for library items
    /// whose name is not known.
    public var fileName: String {
        if let storedFileName { return storedFileName }
        return isLibraryAsset ? "Photos item" : url.lastPathComponent
    }

    /// "RAW+JPEG", "RAW+HEIC", "RAW", or nil for an ordinary image.
    public var rawBadge: String? {
        if kind == .raw { return "RAW" }
        guard hasRawPartner else { return nil }
        let ext = url.pathExtension.lowercased()
        return ext == "heic" || ext == "heif" ? "RAW+HEIC" : "RAW+JPEG"
    }

    /// A placeholder URL for a library asset, so every item has a URL.
    public static func libraryURL(for assetIdentifier: String) -> URL {
        var components = URLComponents()
        components.scheme = "x-photos-asset"
        components.path = assetIdentifier
        return components.url ?? URL(string: "x-photos-asset:unknown")!
    }
}

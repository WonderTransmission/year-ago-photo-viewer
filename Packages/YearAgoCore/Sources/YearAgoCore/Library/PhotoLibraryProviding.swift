import Foundation

/// One image in the Photos library, as the index needs it.
public struct LibraryAsset: Equatable, Sendable {
    public var localIdentifier: String
    public var creationDate: Date?
    public var modificationDate: Date?
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(localIdentifier: String, creationDate: Date?, modificationDate: Date?,
                pixelWidth: Int, pixelHeight: Int) {
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Read access to the Photos library. The app implements it with PhotoKit;
/// tests use a fake. Keeps PhotoKit out of the core package.
public protocol PhotoLibraryProviding: Sendable {
    /// Every image asset (videos excluded). Live Photos count as images.
    func imageAssets() async throws -> [LibraryAsset]

    /// Original file names, such as "IMG_1234.HEIC", by local identifier.
    /// Slow on large libraries: the index asks only when a source uses the
    /// File name date, and caches the answers.
    func originalFileNames(for localIdentifiers: [String]) async -> [String: String]
}

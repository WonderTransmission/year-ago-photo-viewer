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
    /// Opens the library and returns its image assets (videos excluded;
    /// Live Photos count as images) as a lazy list. The count is known at
    /// once, so progress can show a real percentage from the start.
    ///
    /// The first call can take minutes while macOS opens the library.
    func openImageAssets() async throws -> any LibraryAssetList

    /// Original file names, such as "IMG_1234.HEIC", by local identifier.
    /// Slow on large libraries: the index asks only when a source uses the
    /// File name date, and caches the answers.
    func originalFileNames(for localIdentifiers: [String]) async -> [String: String]
}

/// The library's image assets, read in ranges.
public protocol LibraryAssetList: Sendable {
    var count: Int { get }
    /// The assets at `range`, which must lie within `0..<count`.
    func assets(in range: Range<Int>) async throws -> [LibraryAsset]
}

/// A list backed by an array, for fakes and tests.
public struct ArrayAssetList: LibraryAssetList {
    public let all: [LibraryAsset]

    public init(_ all: [LibraryAsset]) {
        self.all = all
    }

    public var count: Int { all.count }

    public func assets(in range: Range<Int>) async throws -> [LibraryAsset] {
        Array(all[range])
    }
}

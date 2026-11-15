import Foundation

/// Reads the original files inside a Photos library package
/// (`*.photoslibrary`), without Photos or PhotoKit.
///
/// Only the folders that hold originals are read. The rest of the package
/// holds thumbnails, edited renders, and caches, which would show as
/// duplicates. The package is never written to.
public enum PhotosLibraryPackage {
    public static let pathExtension = "photoslibrary"

    /// Folders, relative to the package, that can hold originals:
    /// the library's own photos (macOS 10.15 and later), its Shared Library
    /// photos, and the own photos of older libraries.
    public static let originalsFolders = ["originals", "scopes/collectionshare/originals", "Masters"]

    /// The originals folders that exist in `package`. Empty when `package`
    /// isn't a Photos library or can't be read.
    public static func existingOriginalsFolders(in package: URL) -> [String] {
        originalsFolders.filter { folder in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: package.appending(path: folder).path,
                                                  isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Every image and RAW file in the package's originals folders.
    /// Relative paths start at the package, e.g. "originals/0/<UUID>.heic".
    /// Never throws; see `FolderScanner.scan`.
    public static func scan(
        _ package: URL,
        progressInterval: Int = 500,
        isCancelled: () -> Bool = { false },
        onProgress: (Int) -> Void = { _ in }
    ) -> [ScannedFile] {
        var results: [ScannedFile] = []
        for folder in existingOriginalsFolders(in: package) {
            if isCancelled() { break }
            let before = results.count
            let files = FolderScanner.scan(package.appending(path: folder), progressInterval: progressInterval,
                                           isCancelled: isCancelled) { onProgress(before + $0) }
            results += files.map { file in
                var file = file
                file.relativePath = folder + "/" + file.relativePath
                return file
            }
        }
        return results
    }

    /// Up to `limit` asset IDs, read from original file names. Photos names
    /// each original after its asset's UUID, so these match PhotoKit's local
    /// identifiers when the package is the system library. Stops early.
    public static func sampleAssetIDs(in package: URL, limit: Int = 5) -> [String] {
        var ids: [String] = []
        for folder in existingOriginalsFolders(in: package) {
            guard let enumerator = FileManager.default.enumerator(
                at: package.appending(path: folder), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
            else { continue }
            for case let url as URL in enumerator {
                if let id = assetID(fromFileName: url.lastPathComponent) {
                    ids.append(id)
                    if ids.count >= limit { return ids }
                }
            }
        }
        return ids
    }

    /// The asset UUID an original's file name starts with, upper-cased, or
    /// nil. "<UUID>.heic" and "<UUID>_3.mov" both give the UUID.
    static func assetID(fromFileName name: String) -> String? {
        guard name.count >= 36 else { return nil }
        let candidate = String(name.prefix(36))
        guard UUID(uuidString: candidate) != nil else { return nil }
        let rest = name.dropFirst(36)
        guard rest.isEmpty || rest.hasPrefix(".") || rest.hasPrefix("_") else { return nil }
        return candidate.uppercased()
    }

    /// PhotoKit's local identifier for an asset UUID.
    public static func localIdentifier(forAssetID id: String) -> String {
        "\(id)/L0/001"
    }
}

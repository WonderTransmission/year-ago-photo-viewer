import Foundation

/// A displayable file found by `FolderScanner`.
public struct ScannedFile: Hashable, Sendable {
    public var url: URL
    /// Path relative to the scanned folder, using "/" separators.
    public var relativePath: String
    public var kind: MediaKind
    public var byteSize: Int64

    public init(url: URL, relativePath: String, kind: MediaKind, byteSize: Int64) {
        self.url = url
        self.relativePath = relativePath
        self.kind = kind
        self.byteSize = byteSize
    }
}

/// Walks a folder tree and lists the images and RAW files in it.
public enum FolderScanner {
    /// Returns every image and RAW file under `root`, in no particular order.
    ///
    /// Skips hidden files, package contents (such as a `.photoslibrary`),
    /// videos, sidecars, and unreadable entries. Never throws: an unreadable
    /// subfolder is skipped and the walk goes on.
    public static func scan(_ root: URL) -> [ScannedFile] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        let rootComponents = root.pathComponents
        var results: [ScannedFile] = []
        for case let url as URL in enumerator {
            let kind = MediaKind.classify(pathExtension: url.pathExtension)
            guard kind.isDisplayable,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }

            let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            let relative = components.count > rootComponents.count
                ? components.dropFirst(rootComponents.count).joined(separator: "/")
                : url.lastPathComponent
            results.append(ScannedFile(url: url, relativePath: relative, kind: kind,
                                       byteSize: Int64(values.fileSize ?? 0)))
        }
        return results
    }
}

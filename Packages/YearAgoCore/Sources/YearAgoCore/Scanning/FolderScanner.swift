import Foundation

/// A displayable file found by `FolderScanner`.
public struct ScannedFile: Hashable, Sendable {
    public var url: URL
    /// Path relative to the scanned folder, using "/" separators.
    public var relativePath: String
    public var kind: MediaKind
    public var byteSize: Int64
    /// File-system modification and creation instants.
    public var modified: Date?
    public var created: Date?

    public init(url: URL, relativePath: String, kind: MediaKind, byteSize: Int64,
                modified: Date? = nil, created: Date? = nil) {
        self.url = url
        self.relativePath = relativePath
        self.kind = kind
        self.byteSize = byteSize
        self.modified = modified
        self.created = created
    }

    /// Modification time in whole milliseconds, for change detection.
    public var modifiedMilliseconds: Int64? {
        modified.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
    }
}

/// Walks a folder tree and lists the images and RAW files in it.
public enum FolderScanner {
    /// Returns every image and RAW file under `root`, in no particular order.
    ///
    /// Skips hidden files, package contents (such as a `.photoslibrary`),
    /// videos, sidecars, and unreadable entries. Never throws: an unreadable
    /// subfolder is skipped and the walk goes on.
    ///
    /// - Parameters:
    ///   - onProgress: called every `progressInterval` files found.
    ///   - isCancelled: checked per entry; the walk ends early when true.
    ///     Callers must then treat the result as incomplete.
    public static func scan(
        _ root: URL,
        progressInterval: Int = 500,
        isCancelled: () -> Bool = { false },
        onProgress: (Int) -> Void = { _ in }
    ) -> [ScannedFile] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey,
                                      .contentModificationDateKey, .creationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        // Child paths start with the root's real path (e.g. /private/var/…),
        // which `resolvingSymlinksInPath()` does not give (it strips /private).
        // Trimming a known prefix is far cheaper than resolving every file.
        let prefixes = [realPath(root.path), root.path].map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        let keySet = Set(keys)
        var results: [ScannedFile] = []
        for case let url as URL in enumerator {
            if isCancelled() { break }
            let kind = MediaKind.classify(pathExtension: url.pathExtension)
            guard kind.isDisplayable,
                  let values = try? url.resourceValues(forKeys: keySet),
                  values.isRegularFile == true
            else { continue }

            let path = url.path
            guard let prefix = prefixes.first(where: { path.hasPrefix($0) }) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            results.append(ScannedFile(url: url, relativePath: relative, kind: kind,
                                       byteSize: Int64(values.fileSize ?? 0),
                                       modified: values.contentModificationDate,
                                       created: values.creationDate))
            if results.count % progressInterval == 0 {
                onProgress(results.count)
            }
        }
        return results
    }

    /// The canonical path with every symlink resolved, via realpath(3).
    /// Falls back to `path` if it cannot be resolved.
    public static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

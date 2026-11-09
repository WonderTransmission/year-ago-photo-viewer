import Foundation

/// Sandbox access to folder sources through security-scoped bookmarks.
///
/// Bookmarks are stored in the index, one per source. This class creates
/// and resolves them and tracks which folders are being accessed.
@MainActor
final class FolderAccess {
    private static let bookmarkOptions: URL.BookmarkCreationOptions =
        [.withSecurityScope, .securityScopeAllowOnlyReadAccess]

    /// The pre-M5 single-folder bookmark, kept in user defaults.
    private static let legacyBookmarkKey = "folderBookmark"

    private let defaults: UserDefaults
    private var accessed: [Int64: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Starts access to a folder the user just picked and returns a
    /// bookmark for it. Call `track` once the source has an ID.
    func bookmarkForPickedFolder(_ url: URL) throws -> Data {
        _ = url.startAccessingSecurityScopedResource()
        return try url.bookmarkData(options: Self.bookmarkOptions,
                                    includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Records that `url` is being accessed for source `id`.
    func track(_ url: URL, for id: Int64) {
        if let previous = accessed[id], previous != url {
            previous.stopAccessingSecurityScopedResource()
        }
        accessed[id] = url
    }

    /// Resolves a source's bookmark and starts access.
    ///
    /// Never mounts volumes or shows UI. Returns nil if the folder cannot be
    /// reached. `refreshed` is a new bookmark when the old one was stale.
    func open(bookmark: Data, for id: Int64) -> (url: URL, refreshed: Data?)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource()
        else { return nil }
        track(url, for: id)
        let refreshed = isStale
            ? try? url.bookmarkData(options: Self.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            : nil
        return (url, refreshed)
    }

    /// Ends access for one source.
    func stop(_ id: Int64) {
        accessed.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    }

    /// The single-folder bookmark saved by versions before M5, if any.
    /// Reading it removes it.
    func takeLegacyBookmark() -> Data? {
        guard let data = defaults.data(forKey: Self.legacyBookmarkKey) else { return nil }
        defaults.removeObject(forKey: Self.legacyBookmarkKey)
        return data
    }
}

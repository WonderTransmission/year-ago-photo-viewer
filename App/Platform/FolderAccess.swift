import Foundation

/// Keeps sandbox access to the chosen folder across launches, using a
/// read-only security-scoped bookmark stored in user defaults.
@MainActor
final class FolderAccess {
    private let defaults: UserDefaults
    private let bookmarkKey = "folderBookmark"
    private var accessedURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Starts access to a folder the user just picked and remembers it.
    func adopt(_ url: URL) throws -> URL {
        stop()
        let started = url.startAccessingSecurityScopedResource()
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
        accessedURL = started ? url : nil
        return url
    }

    /// Resolves the remembered folder and starts access to it.
    /// Returns nil if there is none, or it can no longer be reached.
    func restore() -> URL? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource()
        else { return nil }

        accessedURL = url
        if isStale, let fresh = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// Ends access to the current folder, if any.
    func stop() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}

import Foundation

/// Scans a folder and dates every photo in it, in memory.
///
/// M4 replaces this with a persistent index. Until then each launch rescans.
public enum FolderPhotoLoader {
    /// Files per concurrent dating task.
    static let chunkSize = 256

    /// Scans `folder` and dates each photo with `dateSource`. Photos without
    /// that date are left out. Runs off the main actor.
    @concurrent
    public static func load(
        folder: URL,
        dateSource: DateSourceKind,
        timeZone: TimeZone = .current
    ) async -> PhotoTimeline {
        let files = FolderScanner.scan(folder)
        let chunks = stride(from: 0, to: files.count, by: chunkSize).map {
            Array(files[$0..<min($0 + chunkSize, files.count)])
        }

        let items = await withTaskGroup(of: [PhotoItem].self) { group in
            for chunk in chunks {
                group.addTask {
                    guard !Task.isCancelled else { return [] }
                    // Each task gets its own dater: the file-name parser is not Sendable.
                    let dater = PhotoDater(source: dateSource, timeZone: timeZone)
                    return chunk.compactMap { file in
                        dater.date(for: file.url).map {
                            PhotoItem(url: file.url, relativePath: file.relativePath,
                                      kind: file.kind, date: $0)
                        }
                    }
                }
            }
            var all: [PhotoItem] = []
            all.reserveCapacity(files.count)
            for await part in group { all.append(contentsOf: part) }
            return all
        }
        return PhotoTimeline(items)
    }
}

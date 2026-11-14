import Foundation
import Testing
@testable import YearAgoCore

/// Plan step 4.6: stopping, resuming, and incremental library changes.
@Suite struct StopResumeTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func assets(_ count: Int, startingAt day: LocalDateTime = local(2025, 10, 1)) -> [LibraryAsset] {
        let start = day.date(in: utc)
        return (0..<count).map { i in
            let date = start.addingTimeInterval(Double(i) * 3600)
            return LibraryAsset(localIdentifier: "a\(i)", creationDate: date, modificationDate: date,
                                pixelWidth: 100, pixelHeight: 100)
        }
    }

    /// Lets a library hook cancel the task that is running the sync.
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: Task<SyncResult, Error>?
        func set(_ task: Task<SyncResult, Error>) { lock.withLock { self.task = task } }
        func cancel() { lock.withLock { task }?.cancel() }
    }

    /// Serves assets from an array, and runs a hook before each batch.
    private struct Library: PhotoLibraryProviding {
        let all: [LibraryAsset]
        var openDelay: Duration = .zero
        var beforeBatch: @Sendable (Range<Int>) async -> Void = { _ in }

        func openImageAssets() async throws -> any LibraryAssetList {
            // Like PhotoKit, opening can't be interrupted: ignore cancellation.
            if openDelay > .zero { try? await Task.sleep(for: openDelay) }
            return List(all: all, beforeBatch: beforeBatch)
        }
        func originalFileNames(for localIdentifiers: [String]) async -> [String: String] {
            Dictionary(uniqueKeysWithValues: localIdentifiers.map { ($0, "IMG_20250101_000000.jpg") })
        }

        struct List: LibraryAssetList {
            let all: [LibraryAsset]
            let beforeBatch: @Sendable (Range<Int>) async -> Void
            var count: Int { all.count }
            func assets(in range: Range<Int>) async throws -> [LibraryAsset] {
                await beforeBatch(range)
                return Array(all[range])
            }
        }
    }

    @Test func stoppingALibrarySyncKeepsAndShowsWhatWasRead() async throws {
        let all = assets(2000)
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let box = TaskBox()
        // Stop while the third batch of 500 is being read: that batch
        // finishes and is kept; the fourth is never read.
        let library = Library(all: all) { range in
            if range.lowerBound == 1000 { box.cancel() }
        }
        let task = Task { try await index.syncLibrary(sourceID: source.id, library: library) }
        box.set(task)
        await #expect(throws: CancellationError.self) { _ = try await task.value }

        #expect(try await index.fileCount(sourceID: source.id) == 1500)
        #expect(try await index.loadTimeline(roots: [:]).photos.count == 1500)   // visible, not hidden
        #expect(try await index.sources().first?.knownTotal == 2000)

        // Resume: only the rest is read, and the lock was released.
        let resumed = try await index.syncLibrary(sourceID: source.id, library: Library(all: all))
        #expect(resumed.read == 500)
        #expect(try await index.fileCount(sourceID: source.id) == 2000)
    }

    @Test func aStoppedFolderWalkDeletesNothing() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        for i in 0..<50 {
            try Data([0xFF]).write(to: root.appendingPathComponent(String(format: "IMG_20251101_1000%02d.jpg", i)))
        }
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addFolderSource(rootPath: FolderScanner.realPath(root.path), name: "f",
                                                     bookmark: nil, dateSource: .fileName)
        _ = try await index.sync(sourceID: source.id, root: root)

        let task = Task { try await index.sync(sourceID: source.id, root: root) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try await index.fileCount(sourceID: source.id) == 50)
        #expect(try await index.sources().first?.knownTotal == 50)
    }

    @Test func aStuckLibraryOpenDoesNotBlockOtherSyncs() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try Data([0xFF]).write(to: root.appendingPathComponent("IMG_20251101_100000.jpg"))
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let photos = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let folder = try await index.addFolderSource(rootPath: FolderScanner.realPath(root.path), name: "f",
                                                     bookmark: nil, dateSource: .fileName)

        // The library takes 1 s to open; the user stops it after 50 ms.
        let library = Library(all: assets(10), openDelay: .seconds(1))
        let libraryTask = Task { try await index.syncLibrary(sourceID: photos.id, library: library) }
        try await Task.sleep(for: .milliseconds(50))
        libraryTask.cancel()

        // The folder syncs at once, while the open is still finishing.
        let result = try await index.sync(sourceID: folder.id, root: root)
        #expect(result.read == 1)
        await #expect(throws: CancellationError.self) { _ = try await libraryTask.value }
        #expect(try await index.fileCount(sourceID: photos.id) == 0)
    }

    @Test func theStoppedFlagIsSaved() async throws {
        let store = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(store) }
        let file = store.appendingPathComponent("Index.sqlite")
        do {
            let index = try PhotoIndex(fileURL: file, timeZone: utc)
            let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
            try await index.setStopped(true, forSource: source.id)
        }
        let reopened = try PhotoIndex(fileURL: file, timeZone: utc)
        #expect(try await reopened.sources().first?.isStopped == true)
        let id = try #require(try await reopened.sources().first?.id)
        try await reopened.setStopped(false, forSource: id)
        #expect(try await reopened.sources().first?.isStopped == false)
    }

    @Test func libraryChangesApplyWithoutAResync() async throws {
        let all = assets(3, startingAt: local(2025, 11, 2))
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: source.id, library: Library(all: all))

        // The user redates a0, deletes a1, and imports a new photo.
        var redated = all[0]
        redated.creationDate = local(2025, 11, 6, 12).date(in: utc)
        redated.modificationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let added = LibraryAsset(localIdentifier: "new", creationDate: local(2025, 11, 4).date(in: utc),
                                 modificationDate: nil, pixelWidth: 100, pixelHeight: 100)
        let changed = try await index.applyLibraryChanges(sourceID: source.id, upserted: [redated, added],
                                                          removed: ["a1"], library: Library(all: []))
        #expect(changed == 3)

        let photos = try await index.loadTimeline(roots: [:]).photos
        #expect(photos.map(\.relativePath) == ["a2", "new", "a0"])
        #expect(photos.last?.date == local(2025, 11, 6, 12))
    }

    @Test func libraryChangesFetchNamesWhenDatedByFileName() async throws {
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .fileName)
        let added = LibraryAsset(localIdentifier: "new", creationDate: nil, modificationDate: nil,
                                 pixelWidth: 100, pixelHeight: 100)
        try await index.applyLibraryChanges(sourceID: source.id, upserted: [added], removed: [],
                                            library: Library(all: []))
        #expect(try await index.loadTimeline(roots: [:]).photos.map(\.date) == [local(2025, 1, 1)])
    }
}

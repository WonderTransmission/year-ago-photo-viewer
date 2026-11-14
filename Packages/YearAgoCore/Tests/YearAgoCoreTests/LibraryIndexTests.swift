import Foundation
import ImageIO
import Testing
@testable import YearAgoCore

/// A scripted Photos library.
private final class FakeLibrary: PhotoLibraryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var assets: [LibraryAsset]
    private let names: [String: String]
    private var nameRequests = 0

    init(_ assets: [LibraryAsset], names: [String: String] = [:]) {
        self.assets = assets
        self.names = names
    }

    func setAssets(_ assets: [LibraryAsset]) {
        lock.withLock { self.assets = assets }
    }

    var fileNameRequests: Int { lock.withLock { nameRequests } }

    func imageAssets() async throws -> [LibraryAsset] {
        lock.withLock { assets }
    }

    func originalFileNames(for localIdentifiers: [String]) async -> [String: String] {
        lock.withLock {
            nameRequests += 1
            return names.filter { localIdentifiers.contains($0.key) }
        }
    }
}

@Suite struct LibraryIndexTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ value: LocalDateTime) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value.seconds))
    }

    private func asset(_ id: String, _ created: LocalDateTime, modified: LocalDateTime = local(2025, 12, 1),
                       width: Int = 4032, height: Int = 3024) -> LibraryAsset {
        LibraryAsset(localIdentifier: id, creationDate: date(created), modificationDate: date(modified),
                     pixelWidth: width, pixelHeight: height)
    }

    @Test func indexesAssetsByCreationDate() async throws {
        let library = FakeLibrary([
            asset("A/L0/001", local(2025, 11, 3, 9)),
            asset("B/L0/001", local(2025, 11, 1, 18)),
        ])
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let result = try await index.syncLibrary(sourceID: source.id, library: library)
        #expect(result == SyncResult(scanned: 2, read: 2, removed: 0))

        let photos = try await index.loadTimeline(roots: [:]).photos
        #expect(photos.map(\.assetIdentifier) == ["B/L0/001", "A/L0/001"])
        #expect(photos.map(\.date) == [local(2025, 11, 1, 18), local(2025, 11, 3, 9)])
        #expect(photos.allSatisfy { $0.isLibraryAsset })
        #expect(photos.first?.fileName == "Photos item")
        #expect(library.fileNameRequests == 0)   // EXIF source: names never fetched
    }

    @Test func addingTheLibraryTwiceReturnsTheSameSource() async throws {
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let first = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let again = try await index.addPhotosLibrarySource(name: "Other", dateSource: .fileName)
        #expect(first.id == again.id)
        #expect(try await index.sources().count == 1)
    }

    @Test func removingTheLibraryDeletesItsRowsAndReAddingReadsEverythingAgain() async throws {
        let library = FakeLibrary((0..<500).map { asset("a\($0)", local(2025, 11, 3)) })
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let first = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: first.id, library: library)
        #expect(try await index.fileCount(sourceID: first.id) == 500)

        try await index.removeSource(first.id)
        #expect(try await index.fileCount(sourceID: first.id) == 0)
        #expect(try await index.sources().isEmpty)
        #expect(try await index.loadTimeline(roots: [:]).photos.isEmpty)

        // Note: SQLite may reuse the removed source's ID (see indexing-ux-plan 2.2).
        let second = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let result = try await index.syncLibrary(sourceID: second.id, library: library)
        #expect(result.read == 500)   // every asset read again: nothing was left behind
    }

    @Test func burstShotsInTheLibraryAllShow() async throws {
        // Same capture second, same pixel size: a burst, not duplicates.
        let library = FakeLibrary((1...5).map { asset("burst-\($0)", local(2025, 11, 3, 9, 30)) })
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: source.id, library: library)
        #expect(try await index.loadTimeline(roots: [:]).photos.count == 5)
    }

    @Test func anEmptyLibraryAfterIndexingIsUnavailableAndKeepsItsRows() async throws {
        let library = FakeLibrary([asset("a", local(2025, 11, 3)), asset("b", local(2025, 11, 4))])
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: source.id, library: library)

        library.setAssets([])   // e.g. the library's drive was disconnected
        await #expect(throws: PhotoIndexError.self) {
            _ = try await index.syncLibrary(sourceID: source.id, library: library)
        }
        #expect(try await index.fileCount(sourceID: source.id) == 2)
    }

    @Test func anEmptyLibraryOnFirstSyncIsFine() async throws {
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let result = try await index.syncLibrary(sourceID: source.id, library: FakeLibrary([]))
        #expect(result == SyncResult(scanned: 0, read: 0, removed: 0))
    }

    @Test func progressStartsWithOpeningTheLibrary() async throws {
        let library = FakeLibrary([asset("a", local(2025, 11, 3))])
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let stages = StageLog()
        _ = try await index.syncLibrary(sourceID: source.id, library: library) { stages.append($0.stage) }
        #expect(stages.values.first == .opening)
        #expect(stages.values.contains(.reading))
    }

    @Test func resyncAppliesEditsAndDeletions() async throws {
        let library = FakeLibrary([
            asset("keep", local(2025, 11, 3)),
            asset("edit", local(2025, 11, 4)),
            asset("delete", local(2025, 11, 5)),
        ])
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: source.id, library: library)

        // The user changes a photo's date in Photos and deletes another.
        library.setAssets([
            asset("keep", local(2025, 11, 3)),
            asset("edit", local(2025, 11, 7), modified: local(2025, 12, 5)),
            asset("new", local(2025, 11, 2)),
        ])
        let result = try await index.syncLibrary(sourceID: source.id, library: library)
        #expect(result == SyncResult(scanned: 3, read: 2, removed: 1))
        let photos = try await index.loadTimeline(roots: [:]).photos
        #expect(photos.map(\.assetIdentifier) == ["new", "keep", "edit"])
    }

    @Test func fileNameDatesFetchNamesOnceAndCacheThem() async throws {
        let library = FakeLibrary(
            [asset("shot", local(2025, 6, 1)), asset("photo", local(2025, 6, 2))],
            names: ["shot": "Screenshot 2025-11-04 at 08.15.00.png", "photo": "IMG_0001.HEIC"])
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .fileName)
        _ = try await index.syncLibrary(sourceID: source.id, library: library)

        let photos = try await index.loadTimeline(roots: [:]).photos
        #expect(photos.map(\.fileName) == ["Screenshot 2025-11-04 at 08.15.00.png"])
        #expect(photos.first?.date == local(2025, 11, 4, 8, 15))
        #expect(library.fileNameRequests == 1)

        _ = try await index.syncLibrary(sourceID: source.id, library: library)
        #expect(library.fileNameRequests == 1)   // cached
    }

    @Test func switchingToFileNameThenResyncingFetchesNames() async throws {
        let library = FakeLibrary([asset("shot", local(2025, 6, 1))],
                                  names: ["shot": "Screenshot 2025-11-04 at 08.15.00.png"])
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: source.id, library: library)
        #expect(library.fileNameRequests == 0)

        try await index.setDateSource(.fileName, forSource: source.id)
        _ = try await index.syncLibrary(sourceID: source.id, library: library)
        #expect(try await index.loadTimeline(roots: [:]).photos.map(\.date) == [local(2025, 11, 4, 8, 15)])
    }

    @Test func libraryPhotoAndItsExportedCopyShowOnce() async throws {
        let folder = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(folder) }
        // An export of the library photo: same capture second, same pixel
        // size (here rotated: width and height swapped).
        try Fixtures.writeImage(to: folder.appendingPathComponent("IMG_0001.jpg"), width: 30, height: 40,
                                exif: [kCGImagePropertyExifDateTimeOriginal: "2025:11:03 09:00:00"])
        try Fixtures.writeImage(to: folder.appendingPathComponent("other.jpg"), width: 30, height: 40,
                                exif: [kCGImagePropertyExifDateTimeOriginal: "2025:11:03 09:00:01"])

        let library = FakeLibrary([asset("lib-1", local(2025, 11, 3, 9), width: 40, height: 30)])
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let photosSource = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: photosSource.id, library: library)
        let folderSource = try await index.addFolderSource(rootPath: FolderScanner.realPath(folder.path),
                                                           name: "Exports", bookmark: nil, dateSource: .exif)
        _ = try await index.sync(sourceID: folderSource.id, root: folder)

        let roots = [folderSource.id: folder]
        let photos = try await index.loadTimeline(roots: roots).photos
        // Same date: the tie goes to the shorter path, the library item.
        #expect(photos.count == 2)
        #expect(photos.first?.assetIdentifier == "lib-1")
        #expect(photos.last?.fileName == "other.jpg")

        // Hiding the library shows the exported copy instead.
        try await index.setEnabled(false, forSource: photosSource.id)
        #expect(try await index.loadTimeline(roots: roots).photos.map(\.fileName) == ["IMG_0001.jpg", "other.jpg"])
    }
}

/// Thread-safe collector for progress stages.
private final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ScanProgress.Stage] = []

    func append(_ stage: ScanProgress.Stage) {
        lock.withLock { stored.append(stage) }
    }

    var values: [ScanProgress.Stage] { lock.withLock { stored } }
}

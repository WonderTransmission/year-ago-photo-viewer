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

    func openImageAssets() async throws -> any LibraryAssetList {
        ArrayAssetList(lock.withLock { assets })
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

/// A library whose list runs a hook before each batch, so a test can look
/// at the index mid-sync.
private struct HookedLibrary: PhotoLibraryProviding {
    let all: [LibraryAsset]
    let beforeBatch: @Sendable (Range<Int>) async -> Void

    func openImageAssets() async throws -> any LibraryAssetList {
        HookedList(all: all, beforeBatch: beforeBatch)
    }

    func originalFileNames(for localIdentifiers: [String]) async -> [String: String] { [:] }

    struct HookedList: LibraryAssetList {
        let all: [LibraryAsset]
        let beforeBatch: @Sendable (Range<Int>) async -> Void
        var count: Int { all.count }
        func assets(in range: Range<Int>) async throws -> [LibraryAsset] {
            await beforeBatch(range)
            return Array(all[range])
        }
    }
}

/// Thread-safe collector for any values.
private final class Collected<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []
    func append(_ value: Value) { lock.withLock { stored.append(value) } }
    var values: [Value] { lock.withLock { stored } }
}

@Suite struct LibraryProgressTests {
    @Test func largeLibraryProgressRisesSteadilyAndRowsArriveEarly() async throws {
        let total = 200_000
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let assets = (0..<total).map { i in
            LibraryAsset(localIdentifier: "a\(i)", creationDate: base.addingTimeInterval(Double(i) * 60),
                         modificationDate: base, pixelWidth: 4032, pixelHeight: 3024)
        }
        let index = try PhotoIndex(fileURL: nil, timeZone: TimeZone(identifier: "UTC")!)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)

        let rowCounts = Collected<Int>()
        let library = HookedLibrary(all: assets) { range in
            // Halfway through, the first half must already be in the index.
            if range.lowerBound == total / 2 {
                rowCounts.append((try? await index.fileCount(sourceID: source.id)) ?? -1)
            }
        }
        let events = Collected<ScanProgress>()
        let result = try await index.syncLibrary(sourceID: source.id, library: library) { events.append($0) }

        #expect(result.read == total)
        #expect(rowCounts.values == [total / 2])

        let progress = events.values
        #expect(progress.first?.stage == .opening)
        #expect(progress.last?.fraction == 1)
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.fraction <= $1.fraction })
        let reading = progress.filter { $0.stage == .reading }
        #expect(reading.first?.total == total)          // the total is known from the start
        #expect(reading.count > 2)                        // it rises in steps…
        #expect(reading.count < total / ProgressTestsLimits.batch)   // …but is throttled
    }
}

private enum ProgressTestsLimits {
    static let batch = 500
}

/// Counts how often the date-filtered fetch is used.
private final class CountingLibrary: PhotoLibraryProviding, @unchecked Sendable {
    let all: [LibraryAsset]
    private let lock = NSLock()
    private var filtered = 0
    init(_ all: [LibraryAsset]) { self.all = all }
    var filteredFetches: Int { lock.withLock { filtered } }

    func openImageAssets() async throws -> any LibraryAssetList { ArrayAssetList(all) }
    func openImageAssets(createdIn ranges: [ClosedRange<Date>]) async throws -> any LibraryAssetList {
        lock.withLock { filtered += 1 }
        return ArrayAssetList(all.filter { a in ranges.contains { $0.contains(a.creationDate!) } })
    }
    func originalFileNames(for localIdentifiers: [String]) async -> [String: String] { [:] }
}

/// Counts calls from a @Sendable callback.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@Suite struct ThisWeekFirstTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// 2,000 assets one per hour from 1 Oct 2025; 1–8 Nov 2025 holds 192.
    private func assets() -> [LibraryAsset] {
        let start = local(2025, 10, 1).date(in: utc)
        return (0..<2000).map { i in
            let date = start.addingTimeInterval(Double(i) * 3600)
            return LibraryAsset(localIdentifier: "a\(i)", creationDate: date, modificationDate: date,
                                pixelWidth: 100, pixelHeight: 100)
        }
    }
    private let window = local(2025, 11, 1)...local(2025, 11, 8, 23, 59, 59)

    @Test func thisWeeksPhotosAreVisibleBeforeTheRestIsRead() async throws {
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let seenAtFirstBatch = Collected<Int>()
        let library = HookedLibrary(all: assets()) { range in
            // The first batch of the full read (not the filtered fetch).
            if range == 0..<500 {
                let visible = (try? await index.loadTimeline(roots: [:]).photos(in: window).count) ?? -1
                seenAtFirstBatch.append(visible)
            }
        }
        let published = CallCounter()
        let result = try await index.syncLibrary(sourceID: source.id, library: library,
                                                 priorityWindows: [window],
                                                 onPhotosAvailable: { published.increment() })
        #expect(seenAtFirstBatch.values == [192])
        #expect(published.count >= 1)
        #expect(result.read == 2000)   // the priority rows count once
        #expect(try await index.fileCount(sourceID: source.id) == 2000)
    }

    @Test func rescansSkipThePriorityPass() async throws {
        let library = CountingLibrary(assets())
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        _ = try await index.syncLibrary(sourceID: source.id, library: library, priorityWindows: [window])
        #expect(library.filteredFetches == 1)
        let again = try await index.syncLibrary(sourceID: source.id, library: library, priorityWindows: [window])
        #expect(library.filteredFetches == 1)
        #expect(again.read == 0)
    }

    @Test func librarySyncPublishesAsItGoes() async throws {
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        await index.setFillInInterval(0)
        let source = try await index.addPhotosLibrarySource(name: "Photos", dateSource: .exif)
        let published = CallCounter()
        _ = try await index.syncLibrary(sourceID: source.id, library: CountingLibrary(assets()),
                                        onPhotosAvailable: { published.increment() })
        #expect(published.count == 4)   // after each of the 4 batches of 500
    }

    @Test func folderSyncPublishesAsItGoes() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        for i in 0..<300 {
            try Data([0xFF, UInt8(i % 256)]).write(to: root.appendingPathComponent(
                String(format: "IMG_20251101_10%02d%02d.jpg", i / 60, i % 60)))
        }
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        await index.setFillInInterval(0)
        let source = try await index.addFolderSource(rootPath: FolderScanner.realPath(root.path), name: "f",
                                                     bookmark: nil, dateSource: .fileName)
        let published = CallCounter()
        _ = try await index.sync(sourceID: source.id, root: root, onPhotosAvailable: { published.increment() })
        #expect(published.count >= 2)   // 300 files are read in 3 concurrent chunks
        #expect(try await index.loadTimeline(roots: [source.id: root]).photos.count == 300)
    }
}

import Foundation
import ImageIO
import Testing
@testable import YearAgoCore

@Suite struct PhotoIndexTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func exif(_ value: String) -> [CFString: Any] {
        [kCGImagePropertyExifDateTimeOriginal: value]
    }

    /// Writes a JPEG with an EXIF date and a fixed modification time.
    private func photo(_ root: URL, _ path: String, exif value: String?,
                       modified: LocalDateTime = local(2025, 12, 1)) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Fixtures.writeImage(to: url, exif: value.map(exif) ?? [:])
        try setModified(url, modified)
    }

    private func setModified(_ url: URL, _ date: LocalDateTime) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(date.seconds))],
            ofItemAtPath: url.path)
    }

    private func makeIndex(file: URL? = nil, timeZone: TimeZone? = nil) throws -> PhotoIndex {
        try PhotoIndex(fileURL: file, timeZone: timeZone ?? utc)
    }

    @Test func initialSyncIndexesEveryFileAndDatesByExif() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try photo(root, "a.jpg", exif: "2025:11:02 09:00:00")
        try photo(root, "sub/b.jpg", exif: "2025:11:05 10:00:00")
        try photo(root, "undated.jpg", exif: nil)

        let index = try makeIndex()
        let source = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .exif)
        let result = try await index.sync(sourceID: source.id, root: root)
        #expect(result == SyncResult(scanned: 3, read: 3, removed: 0))
        #expect(try await index.fileCount(sourceID: source.id) == 3)

        let timeline = try await index.loadTimeline(roots: [source.id: root])
        #expect(timeline.photos.map(\.relativePath) == ["a.jpg", "sub/b.jpg"])
        #expect(timeline.photos.map(\.date) == [local(2025, 11, 2, 9), local(2025, 11, 5, 10)])
        #expect(timeline.photos[1].url.path.hasSuffix("/sub/b.jpg"))
    }

    @Test func unchangedRescanReadsNothing() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try photo(root, "a.jpg", exif: "2025:11:02 09:00:00")
        try photo(root, "b.jpg", exif: "2025:11:03 09:00:00")

        let index = try makeIndex()
        let source = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .exif)
        _ = try await index.sync(sourceID: source.id, root: root)
        let again = try await index.sync(sourceID: source.id, root: root)
        #expect(again == SyncResult(scanned: 2, read: 0, removed: 0))
    }

    @Test func addChangeAndDeleteAreApplied() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try photo(root, "keep.jpg", exif: "2025:11:01 09:00:00")
        try photo(root, "change.jpg", exif: "2025:11:02 09:00:00")
        try photo(root, "delete.jpg", exif: "2025:11:03 09:00:00")

        let index = try makeIndex()
        let source = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .exif)
        _ = try await index.sync(sourceID: source.id, root: root)

        try photo(root, "change.jpg", exif: "2025:11:07 18:00:00", modified: local(2025, 12, 2))
        try FileManager.default.removeItem(at: root.appendingPathComponent("delete.jpg"))
        try photo(root, "new.jpg", exif: "2025:11:04 09:00:00")

        let result = try await index.sync(sourceID: source.id, root: root)
        #expect(result == SyncResult(scanned: 3, read: 2, removed: 1))
        let timeline = try await index.loadTimeline(roots: [source.id: root])
        #expect(timeline.photos.map(\.relativePath) == ["keep.jpg", "new.jpg", "change.jpg"])
        #expect(timeline.photos.last?.date == local(2025, 11, 7, 18))
    }

    @Test func switchingDateSourceNeedsNoRescan() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try photo(root, "Screenshot 2024-11-03 at 08.15.00.png", exif: nil, modified: local(2025, 1, 2, 3))
        try photo(root, "IMG_0001.jpg", exif: "2023:11:04 12:00:00", modified: local(2025, 1, 5))

        let index = try makeIndex()
        let source = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .exif)
        _ = try await index.sync(sourceID: source.id, root: root)
        var timeline = try await index.loadTimeline(roots: [source.id: root])
        #expect(timeline.photos.map(\.date) == [local(2023, 11, 4, 12)])

        try await index.setDateSource(.fileName, forSource: source.id)
        timeline = try await index.loadTimeline(roots: [source.id: root])
        #expect(timeline.photos.map(\.date) == [local(2024, 11, 3, 8, 15)])

        try await index.setDateSource(.modified, forSource: source.id)
        timeline = try await index.loadTimeline(roots: [source.id: root])
        #expect(timeline.photos.map(\.date) == [local(2025, 1, 2, 3), local(2025, 1, 5)])

        let source2 = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .exif)
        #expect(source2.id == source.id)
        #expect(source2.dateSource == .modified)
    }

    @Test func persistsAcrossReopen() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        let store = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root); Fixtures.cleanUp(store) }
        try photo(root, "a.jpg", exif: "2025:11:02 09:00:00")
        let file = store.appendingPathComponent("nested/Index.sqlite")

        var sourceID: Int64
        do {
            let index = try makeIndex(file: file)
            sourceID = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .exif).id
            _ = try await index.sync(sourceID: sourceID, root: root)
        }

        let reopened = try makeIndex(file: file)
        let timeline = try await reopened.loadTimeline(roots: [sourceID: root])
        #expect(timeline.photos.map(\.relativePath) == ["a.jpg"])
        let result = try await reopened.sync(sourceID: sourceID, root: root)
        #expect(result.read == 0)
    }

    @Test func timeZoneChangeForcesReread() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        let store = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root); Fixtures.cleanUp(store) }
        try photo(root, "a.jpg", exif: nil, modified: local(2025, 11, 3, 12))
        let file = store.appendingPathComponent("Index.sqlite")

        var sourceID: Int64
        do {
            let index = try makeIndex(file: file)
            sourceID = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .modified).id
            _ = try await index.sync(sourceID: sourceID, root: root)
        }

        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let moved = try makeIndex(file: file, timeZone: tokyo)
        let result = try await moved.sync(sourceID: sourceID, root: root)
        #expect(result.read == 1)
        let timeline = try await moved.loadTimeline(roots: [sourceID: root])
        #expect(timeline.photos.map(\.date) == [local(2025, 11, 3, 21)])
    }

    @Test func removeOtherSourcesDeletesTheirPhotos() async throws {
        let rootA = try Fixtures.makeTemporaryDirectory()
        let rootB = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(rootA); Fixtures.cleanUp(rootB) }
        try photo(rootA, "a.jpg", exif: "2025:11:02 09:00:00")
        try photo(rootB, "b.jpg", exif: "2025:11:02 09:00:00")

        let index = try makeIndex()
        let a = try await index.folderSource(rootPath: rootA.path, name: "A", defaultDateSource: .exif)
        let b = try await index.folderSource(rootPath: rootB.path, name: "B", defaultDateSource: .exif)
        _ = try await index.sync(sourceID: a.id, root: rootA)
        _ = try await index.sync(sourceID: b.id, root: rootB)

        try await index.removeSources(except: b.id)
        #expect(try await index.fileCount(sourceID: a.id) == 0)
        #expect(try await index.fileCount(sourceID: b.id) == 1)
    }

    @Test func reportsProgress() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        for i in 0..<5 {
            try photo(root, "p\(i).jpg", exif: "2025:11:02 09:00:0\(i)")
        }
        let index = try makeIndex()
        let source = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .exif)
        let log = ProgressLog()
        _ = try await index.sync(sourceID: source.id, root: root) { log.append($0) }
        let events = log.events
        #expect(events.first == ScanProgress(stage: .finding, completed: 0))
        #expect(events.last == ScanProgress(stage: .reading, completed: 5, total: 5))
    }

    /// Opt-in: set YAPV_SCALE_TEST=1. Builds 100,000 tiny files and times a
    /// full index and a no-change rescan.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YAPV_SCALE_TEST"] == "1"))
    func scale100k() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        let count = 100_000
        for folder in 0..<100 {
            let dir = root.appendingPathComponent(String(format: "%03d", folder))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<(count / 100) {
                let n = folder * 1000 + i
                let name = String(format: "IMG_2025%02d%02d_%02d%02d%02d.jpg",
                                  n % 12 + 1, n % 28 + 1, n % 24, n % 60, (n / 60) % 60)
                try Data([0xFF, 0xD8]).write(to: dir.appendingPathComponent(name))
            }
        }
        let index = try makeIndex()
        let source = try await index.folderSource(rootPath: root.path, name: "root", defaultDateSource: .fileName)

        let clock = ContinuousClock()
        var first: SyncResult?
        let full = try await clock.measure { first = try await index.sync(sourceID: source.id, root: root) }
        var second: SyncResult?
        let rescan = try await clock.measure { second = try await index.sync(sourceID: source.id, root: root) }
        let load = try await clock.measure { _ = try await index.loadTimeline(roots: [source.id: root]) }
        print("SCALE: full index \(full), no-change rescan \(rescan), load timeline \(load)")
        #expect(first?.read == count)
        #expect(second?.read == 0)
    }
}

/// Thread-safe collector for progress callbacks.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanProgress] = []

    func append(_ event: ScanProgress) {
        lock.withLock { storage.append(event) }
    }

    var events: [ScanProgress] {
        lock.withLock { storage }
    }
}

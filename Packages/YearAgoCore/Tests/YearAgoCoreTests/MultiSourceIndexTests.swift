import Foundation
import ImageIO
import Testing
@testable import YearAgoCore

/// M5: several sources at once, per-source date settings, offline and
/// disabled sources, and nested folders.
@Suite struct MultiSourceIndexTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func photo(_ root: URL, _ path: String, exif: String?,
                       modified: LocalDateTime = local(2025, 12, 1)) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Fixtures.writeImage(to: url, exif: exif.map { [kCGImagePropertyExifDateTimeOriginal: $0] } ?? [:])
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(modified.seconds))],
            ofItemAtPath: url.path)
    }

    private func add(_ index: PhotoIndex, _ root: URL, _ name: String,
                     _ dateSource: DateSourceKind) async throws -> SourceRecord {
        let source = try await index.addFolderSource(rootPath: FolderScanner.realPath(root.path), name: name,
                                                     bookmark: nil, dateSource: dateSource)
        _ = try await index.sync(sourceID: source.id, root: root)
        return source
    }

    @Test func sourcesMergeEachWithItsOwnDateSetting() async throws {
        let camera = try Fixtures.makeTemporaryDirectory()
        let screenshots = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(camera); Fixtures.cleanUp(screenshots) }
        try photo(camera, "IMG_0001.jpg", exif: "2025:11:03 10:00:00")
        try photo(screenshots, "Screenshot 2025-11-02 at 08.00.00.png", exif: nil)

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let a = try await add(index, camera, "Camera", .exif)
        let b = try await add(index, screenshots, "Screenshots", .fileName)

        let timeline = try await index.loadTimeline(roots: [a.id: camera, b.id: screenshots])
        #expect(timeline.photos.map(\.fileName) == ["Screenshot 2025-11-02 at 08.00.00.png", "IMG_0001.jpg"])
        #expect(timeline.photos.map(\.sourceID) == [b.id, a.id])
        #expect(Set(timeline.photos.map(\.id)).count == 2)
    }

    @Test func disablingASourceHidesItsPhotosUntilReenabled() async throws {
        let rootA = try Fixtures.makeTemporaryDirectory()
        let rootB = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(rootA); Fixtures.cleanUp(rootB) }
        try photo(rootA, "a.jpg", exif: "2025:11:03 10:00:00")
        try photo(rootB, "b.jpg", exif: "2025:11:04 10:00:00")

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let a = try await add(index, rootA, "A", .exif)
        let b = try await add(index, rootB, "B", .exif)
        let roots = [a.id: rootA, b.id: rootB]

        try await index.setEnabled(false, forSource: a.id)
        #expect(try await index.loadTimeline(roots: roots).photos.map(\.fileName) == ["b.jpg"])
        #expect(try await index.sourceStats()[a.id] == SourceStats(files: 1, visible: 0))

        try await index.setEnabled(true, forSource: a.id)
        #expect(try await index.loadTimeline(roots: roots).photos.map(\.fileName) == ["a.jpg", "b.jpg"])
    }

    @Test func missingRootThrowsAndKeepsRows() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try photo(root, "a.jpg", exif: "2025:11:03 10:00:00")
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, "Drive", .exif)

        let unplugged = root.appendingPathComponent("not-mounted")
        await #expect(throws: PhotoIndexError.self) {
            _ = try await index.sync(sourceID: source.id, root: unplugged)
        }
        #expect(try await index.fileCount(sourceID: source.id) == 1)
    }

    @Test func offlineSourceHidesPhotosAndKeepsRows() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try photo(root, "a.jpg", exif: "2025:11:03 10:00:00")
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, "Drive", .exif)

        try await index.setOnline(false, forSource: source.id)
        #expect(try await index.loadTimeline(roots: [source.id: root]).photos.isEmpty)
        #expect(try await index.sources().first?.isOnline == false)
        #expect(try await index.fileCount(sourceID: source.id) == 1)

        try await index.setOnline(true, forSource: source.id)
        #expect(try await index.loadTimeline(roots: [source.id: root]).photos.count == 1)
    }

    @Test func nestedFolderSourcesCountEachFileOnce() async throws {
        let outer = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(outer) }
        try photo(outer, "top.jpg", exif: "2025:11:01 10:00:00")
        try photo(outer, "trip/inner.jpg", exif: "2025:11:03 10:00:00", modified: local(2025, 11, 2))
        let inner = outer.appendingPathComponent("trip")

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let o = try await add(index, outer, "All", .exif)
        let i = try await add(index, inner, "Trip", .modified)
        let roots = [o.id: outer, i.id: inner]

        var photos = try await index.loadTimeline(roots: roots).photos
        #expect(photos.map(\.fileName) == ["top.jpg", "inner.jpg"])
        // Earliest date wins: the Trip source dates inner.jpg by its
        // modified date (2 Nov), earlier than its EXIF date (3 Nov).
        #expect(photos.last?.sourceID == i.id)
        #expect(photos.last?.date == local(2025, 11, 2))

        // With the inner source disabled, the outer copy shows instead.
        try await index.setEnabled(false, forSource: i.id)
        photos = try await index.loadTimeline(roots: roots).photos
        #expect(photos.map(\.fileName) == ["top.jpg", "inner.jpg"])
        #expect(photos.last?.sourceID == o.id)
    }

    @Test func addingTheSameFolderTwiceReturnsTheExistingSource() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let first = try await index.addFolderSource(rootPath: root.path, name: "A", bookmark: nil, dateSource: .exif)
        let again = try await index.addFolderSource(rootPath: root.path, name: "B", bookmark: Data([1, 2]), dateSource: .modified)
        #expect(again.id == first.id)
        #expect(again.name == "A")
        #expect(again.bookmark == Data([1, 2]))
        #expect(try await index.sources().count == 1)
    }

    @Test func renameReorderAndApplyDateSourceToAll() async throws {
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let a = try await index.addFolderSource(rootPath: "/a", name: "A", bookmark: nil, dateSource: .exif)
        let b = try await index.addFolderSource(rootPath: "/b", name: "B", bookmark: nil, dateSource: .fileName)
        let c = try await index.addFolderSource(rootPath: "/c", name: "C", bookmark: nil, dateSource: .created)
        #expect(try await index.sources().map(\.id) == [a.id, b.id, c.id])

        try await index.reorderSources([c.id, a.id])
        #expect(try await index.sources().map(\.id) == [c.id, a.id, b.id])

        try await index.renameSource(b.id, to: "Screenshots")
        #expect(try await index.sources().last?.name == "Screenshots")

        try await index.setDateSourceForAll(.modified)
        #expect(try await index.sources().allSatisfy { $0.dateSource == .modified })
    }
}

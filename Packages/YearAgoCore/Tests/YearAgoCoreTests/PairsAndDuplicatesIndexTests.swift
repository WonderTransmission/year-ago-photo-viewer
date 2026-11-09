import Foundation
import ImageIO
import Testing
@testable import YearAgoCore

/// M6: RAW+JPEG pairs and duplicate hiding, through the index.
@Suite struct PairsAndDuplicatesIndexTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// Writes raw bytes with a fixed modification time.
    private func bytes(_ root: URL, _ path: String, _ data: Data,
                       modified: LocalDateTime = local(2025, 12, 1)) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(modified.seconds))],
            ofItemAtPath: url.path)
    }

    /// Writes an image, optionally with an EXIF date. The extension decides
    /// how the index classifies it; ImageIO reads the content either way.
    private func image(_ root: URL, _ path: String, exif: String?, width: Int = 8) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Fixtures.writeImage(to: url, width: width,
                                exif: exif.map { [kCGImagePropertyExifDateTimeOriginal: $0] } ?? [:])
    }

    private func add(_ index: PhotoIndex, _ root: URL, _ dateSource: DateSourceKind) async throws -> SourceRecord {
        let source = try await index.addFolderSource(rootPath: FolderScanner.realPath(root.path),
                                                     name: root.lastPathComponent, bookmark: nil,
                                                     dateSource: dateSource)
        _ = try await index.sync(sourceID: source.id, root: root)
        return source
    }

    // MARK: Pairs

    @Test func rawJpegPairShowsTheJpegWithABadge() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try image(root, "IMG_1234.CR2", exif: "2025:11:03 10:00:00")
        try image(root, "IMG_1234.JPG", exif: "2025:11:03 10:00:00")
        try image(root, "IMG_9999.CR2", exif: "2025:11:04 10:00:00")   // lone RAW

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, .exif)
        let photos = try await index.loadTimeline(roots: [source.id: root]).photos
        #expect(photos.map(\.fileName) == ["IMG_1234.JPG", "IMG_9999.CR2"])
        #expect(photos.map(\.rawBadge) == ["RAW+JPEG", "RAW"])
    }

    @Test func jpegWithoutTheDateUsesItsRawsDate() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try image(root, "IMG_1.NEF", exif: "2025:11:05 07:00:00")
        try image(root, "IMG_1.jpg", exif: nil)

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, .exif)
        let photos = try await index.loadTimeline(roots: [source.id: root]).photos
        #expect(photos.map(\.fileName) == ["IMG_1.jpg"])
        #expect(photos.first?.date == local(2025, 11, 5, 7))
    }

    @Test func deletingTheJpegUnhidesTheRaw() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try image(root, "IMG_1.ARW", exif: "2025:11:05 07:00:00")
        try image(root, "IMG_1.JPG", exif: "2025:11:05 07:00:00")
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, .exif)

        try FileManager.default.removeItem(at: root.appendingPathComponent("IMG_1.JPG"))
        _ = try await index.sync(sourceID: source.id, root: root)
        let photos = try await index.loadTimeline(roots: [source.id: root]).photos
        #expect(photos.map(\.fileName) == ["IMG_1.ARW"])
    }

    // MARK: Duplicates

    @Test func identicalCopiesShowOnceAndTheEarliestDateWins() async throws {
        let main = try Fixtures.makeTemporaryDirectory()
        let backup = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(main); Fixtures.cleanUp(backup) }
        let content = Data(repeating: 0xAB, count: 500)
        try bytes(main, "IMG_0001.jpg", content, modified: local(2024, 11, 3, 9))
        try bytes(backup, "old-phone/IMG_0001.jpg", content, modified: local(2025, 11, 3, 9))

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let a = try await add(index, main, .modified)
        let b = try await add(index, backup, .modified)
        let roots = [a.id: main, b.id: backup]
        #expect(try await index.loadTimeline(roots: roots).photos.count == 2)  // not hashed yet

        let hashed = try await index.findDuplicates(roots: roots)
        #expect(hashed == 2)
        let photos = try await index.loadTimeline(roots: roots).photos
        #expect(photos.count == 1)
        #expect(photos.first?.sourceID == a.id)
        #expect(photos.first?.date == local(2024, 11, 3, 9))

        // Hide the original's source: the backup copy takes over, at its own date.
        try await index.setEnabled(false, forSource: a.id)
        let fallback = try await index.loadTimeline(roots: roots).photos
        #expect(fallback.map(\.sourceID) == [b.id])
        #expect(fallback.first?.date == local(2025, 11, 3, 9))
    }

    @Test func tiesGoToTheShortestPathThenAlphabetical() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        let content = Data(repeating: 0x11, count: 300)
        let date = local(2025, 11, 3)
        try bytes(root, "backup/b.jpg", content, modified: date)
        try bytes(root, "b.jpg", content, modified: date)
        try bytes(root, "a.jpg", content, modified: date)

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, .modified)
        try await index.findDuplicates(roots: [source.id: root])
        let photos = try await index.loadTimeline(roots: [source.id: root]).photos
        #expect(photos.map(\.relativePath) == ["a.jpg"])
    }

    @Test func sameSizeDifferentContentBothShow() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try bytes(root, "IMG_20251101_100000.jpg", Data(repeating: 1, count: 200))
        try bytes(root, "IMG_20251102_100000.jpg", Data(repeating: 2, count: 200))
        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, .fileName)
        try await index.findDuplicates(roots: [source.id: root])
        #expect(try await index.loadTimeline(roots: [source.id: root]).photos.count == 2)
    }

    @Test func anUndatedCopyNeverWins() async throws {
        let dated = try Fixtures.makeTemporaryDirectory()
        let undated = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dated); Fixtures.cleanUp(undated) }
        let content = Data(repeating: 9, count: 100)
        try bytes(dated, "IMG_20251101_100000.jpg", content)
        try bytes(undated, "a.jpg", content)   // shorter path, but no file-name date

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let a = try await add(index, dated, .fileName)
        let b = try await add(index, undated, .fileName)
        let roots = [a.id: dated, b.id: undated]
        try await index.findDuplicates(roots: roots)
        #expect(try await index.loadTimeline(roots: roots).photos.map(\.sourceID) == [a.id])

        try await index.setEnabled(false, forSource: a.id)
        #expect(try await index.loadTimeline(roots: roots).photos.isEmpty)
    }

    @Test func onlySharedSizesAreHashedAndOnlyOnce() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try bytes(root, "IMG_20251101_100000.jpg", Data(repeating: 1, count: 200))
        try bytes(root, "IMG_20251102_100000.jpg", Data(repeating: 2, count: 200))
        try bytes(root, "IMG_20251103_100000.jpg", Data(repeating: 3, count: 999))   // unique size

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await add(index, root, .fileName)
        let roots = [source.id: root]
        #expect(try await index.findDuplicates(roots: roots) == 2)
        #expect(try await index.findDuplicates(roots: roots) == 0)

        // A changed file loses its hash and is hashed again.
        try bytes(root, "IMG_20251101_100000.jpg", Data(repeating: 4, count: 200), modified: local(2025, 12, 2))
        _ = try await index.sync(sourceID: source.id, root: root)
        #expect(try await index.findDuplicates(roots: roots) == 1)
    }
}

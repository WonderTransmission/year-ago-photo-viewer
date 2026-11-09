import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import YearAgoCore

@Suite struct FolderPhotoLoaderTests {
    private func exif(_ value: String) -> [CFString: Any] {
        [kCGImagePropertyExifDateTimeOriginal: value]
    }

    @Test func datesByExifAndDropsUndated() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try Fixtures.writeImage(to: root.appendingPathComponent("b.jpg"), exif: exif("2025:11:05 10:00:00"))
        try Fixtures.writeImage(to: root.appendingPathComponent("sub/a.jpg"), exif: exif("2025:11:02 09:00:00"))
        try Fixtures.writeImage(to: root.appendingPathComponent("undated.png"), type: .png)

        let timeline = await FolderPhotoLoader.load(folder: root, dateSource: .exif)
        #expect(timeline.photos.map(\.relativePath) == ["sub/a.jpg", "b.jpg"])
        #expect(timeline.photos.map(\.date) == [local(2025, 11, 2, 9), local(2025, 11, 5, 10)])
    }

    @Test func datesByFileName() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try Fixtures.writeImage(to: root.appendingPathComponent("Screenshot 2025-11-04 at 08.15.00.png"), type: .png)
        try Fixtures.writeImage(to: root.appendingPathComponent("random.png"), type: .png)

        let timeline = await FolderPhotoLoader.load(folder: root, dateSource: .fileName)
        #expect(timeline.photos.map(\.date) == [local(2025, 11, 4, 8, 15)])
    }

    @Test func manyFilesAcrossChunks() async throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        let count = FolderPhotoLoader.chunkSize * 2 + 7
        for i in 0..<count {
            let name = String(format: "IMG_20251101_00%02d%02d.jpg", i / 60, i % 60)
            try Data([0xFF]).write(to: root.appendingPathComponent(name))
        }
        let timeline = await FolderPhotoLoader.load(folder: root, dateSource: .fileName)
        #expect(timeline.photos.count == count)
    }
}

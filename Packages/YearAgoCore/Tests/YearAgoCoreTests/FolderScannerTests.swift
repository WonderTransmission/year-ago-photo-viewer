import Foundation
import Testing
@testable import YearAgoCore

@Suite struct FolderScannerTests {
    /// Creates an empty file, making parent folders as needed.
    private func touch(_ root: URL, _ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0x00, 0x01]).write(to: url)
    }

    @Test func findsImagesAndRawsRecursively() throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try touch(root, "a.jpg")
        try touch(root, "2019/b.HEIC")
        try touch(root, "2019/trip/c.CR2")
        try touch(root, "2019/trip/c.JPG")

        let found = FolderScanner.scan(root)
        let byPath = Dictionary(uniqueKeysWithValues: found.map { ($0.relativePath, $0.kind) })
        #expect(byPath == [
            "a.jpg": .image,
            "2019/b.HEIC": .image,
            "2019/trip/c.CR2": .raw,
            "2019/trip/c.JPG": .image,
        ])
        #expect(found.allSatisfy { $0.byteSize == 2 })
    }

    @Test func skipsVideosSidecarsAndOtherFiles() throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try touch(root, "IMG_0001.HEIC")
        try touch(root, "IMG_0001.MOV")   // Live Photo video half
        try touch(root, "IMG_0002.AAE")
        try touch(root, "IMG_0003.xmp")
        try touch(root, "notes.txt")

        #expect(FolderScanner.scan(root).map(\.relativePath) == ["IMG_0001.HEIC"])
    }

    @Test func skipsHiddenFilesAndFolders() throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try touch(root, "visible.jpg")
        try touch(root, ".hidden.jpg")
        try touch(root, ".thumbnails/x.jpg")

        #expect(FolderScanner.scan(root).map(\.relativePath) == ["visible.jpg"])
    }

    @Test func skipsPackageContents() throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        try touch(root, "keep.jpg")
        try touch(root, "Photos Library.photoslibrary/originals/0/x.jpg")

        #expect(FolderScanner.scan(root).map(\.relativePath) == ["keep.jpg"])
    }

    @Test func missingFolderIsEmpty() throws {
        let root = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(root) }
        #expect(FolderScanner.scan(root.appendingPathComponent("nope")).isEmpty)
    }
}

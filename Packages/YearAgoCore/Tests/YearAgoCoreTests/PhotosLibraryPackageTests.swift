import Foundation
import ImageIO
import Testing
@testable import YearAgoCore

/// Plan "other Photos libraries" step 4.2: a `.photoslibrary` package read
/// as files. Every package here is built at run time from generated images.
@Suite struct PhotosLibraryPackageTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// A fake package in a fresh temporary directory. Remove its parent
    /// with `Fixtures.cleanUp`.
    private func makePackage() throws -> URL {
        let package = try Fixtures.makeTemporaryDirectory().appendingPathComponent("Test.photoslibrary")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("database"),
                                                withIntermediateDirectories: true)
        return package
    }

    /// Writes a generated image (or, for non-image extensions, a stub file).
    private func write(_ package: URL, _ path: String, exif: String? = "2025:11:03 10:00:00") throws {
        let url = package.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if ["jpeg", "jpg"].contains(url.pathExtension) {
            try Fixtures.writeImage(to: url, exif: exif.map { [kCGImagePropertyExifDateTimeOriginal: $0] } ?? [:])
        } else {
            try Data([0x00, 0x01]).write(to: url)
        }
    }

    private func addAndSync(_ index: PhotoIndex, _ package: URL,
                            dateSource: DateSourceKind = .exif) async throws -> SourceRecord {
        let source = try await index.addFolderSource(rootPath: FolderScanner.realPath(package.path),
                                                     name: "Test", bookmark: nil, dateSource: dateSource,
                                                     kind: .libraryPackage)
        _ = try await index.sync(sourceID: source.id, root: package)
        return source
    }

    // MARK: Scanning

    @Test func scansOnlyOriginalsFolders() throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        let own = UUID().uuidString, shared = UUID().uuidString, old = UUID().uuidString
        try write(package, "originals/A/\(own).jpeg")
        try write(package, "originals/A/\(own)_3.mov")                     // Live Photo video
        try write(package, "scopes/collectionshare/originals/B/\(shared).jpeg")
        try write(package, "Masters/2019/01/02/\(old).jpg")
        // Derived copies, which must not show as extra photos.
        try write(package, "resources/renders/A/\(own)_1_201_a.jpeg")
        try write(package, "resources/derivatives/A/\(own)_1_105_c.jpeg")
        try write(package, "scopes/cloudsharing/data/123/x.jpeg")
        try write(package, "database/Photos.sqlite")

        let found = PhotosLibraryPackage.scan(package).map(\.relativePath).sorted()
        #expect(found == [
            "Masters/2019/01/02/\(old).jpg",
            "originals/A/\(own).jpeg",
            "scopes/collectionshare/originals/B/\(shared).jpeg",
        ])
    }

    @Test func listsOnlyOriginalsFoldersThatExist() throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        #expect(PhotosLibraryPackage.existingOriginalsFolders(in: package).isEmpty)
        try write(package, "originals/0/\(UUID().uuidString).jpeg")
        #expect(PhotosLibraryPackage.existingOriginalsFolders(in: package) == ["originals"])
    }

    @Test func readsAssetIDsFromFileNames() {
        let id = UUID().uuidString
        #expect(PhotosLibraryPackage.assetID(fromFileName: "\(id).heic") == id)
        #expect(PhotosLibraryPackage.assetID(fromFileName: "\(id)_3.mov") == id)
        #expect(PhotosLibraryPackage.assetID(fromFileName: "\(id.lowercased()).jpeg") == id)
        #expect(PhotosLibraryPackage.assetID(fromFileName: "IMG_0001.jpeg") == nil)
        #expect(PhotosLibraryPackage.assetID(fromFileName: "\(id)x.jpeg") == nil)
        #expect(PhotosLibraryPackage.localIdentifier(forAssetID: id) == "\(id)/L0/001")
    }

    @Test func samplesAssetIDsUpToTheLimit() throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        let ids = (0..<4).map { _ in UUID().uuidString }
        for id in ids {
            try write(package, "originals/\(id.prefix(1))/\(id).jpeg")
        }
        try write(package, "originals/0/not-a-uuid.jpeg")

        let sample = PhotosLibraryPackage.sampleAssetIDs(in: package, limit: 3)
        #expect(sample.count == 3)
        #expect(Set(sample).isSubset(of: Set(ids)))
        #expect(Set(PhotosLibraryPackage.sampleAssetIDs(in: package)) == Set(ids))
    }

    // MARK: Edited copies

    @Test func findsTheEditedRenderNextToTheOriginal() throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        let edited = UUID().uuidString, plain = UUID().uuidString, shared = UUID().uuidString
        try write(package, "originals/A/\(edited).jpeg")
        try write(package, "resources/renders/A/\(edited)_1_201_a.jpeg")
        try write(package, "resources/renders/A/\(edited)_2_0_a.mov")         // Live Photo video render
        try write(package, "originals/A/\(plain).jpeg")
        try write(package, "scopes/collectionshare/originals/B/\(shared).jpeg")
        try write(package, "scopes/collectionshare/resources/renders/B/\(shared)_1_201_a.jpeg")

        func render(_ path: String) -> String? {
            PhotosLibraryPackage.editedRender(forOriginal: path, in: package)?.path
                .replacingOccurrences(of: package.path + "/", with: "")
        }
        #expect(render("originals/A/\(edited).jpeg") == "resources/renders/A/\(edited)_1_201_a.jpeg")
        #expect(render("originals/A/\(plain).jpeg") == nil)
        #expect(render("scopes/collectionshare/originals/B/\(shared).jpeg")
                == "scopes/collectionshare/resources/renders/B/\(shared)_1_201_a.jpeg")
        #expect(render("originals/Z/\(UUID().uuidString).jpeg") == nil)      // no renders folder
        #expect(render("Masters/2019/01/02/\(edited).jpeg") == nil)
        #expect(render("originals/A/IMG_0001.jpeg") == nil)
    }

    @Test func prefersTheStandardRenderName() throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        let id = UUID().uuidString
        try write(package, "originals/A/\(id).heic")
        try write(package, "resources/renders/A/\(id)_1_100_x.jpeg")
        #expect(PhotosLibraryPackage.editedRender(forOriginal: "originals/A/\(id).heic", in: package)?
            .lastPathComponent == "\(id)_1_100_x.jpeg")
        try write(package, "resources/renders/A/\(id)_1_201_a.jpeg")
        #expect(PhotosLibraryPackage.editedRender(forOriginal: "originals/A/\(id).heic", in: package)?
            .lastPathComponent == "\(id)_1_201_a.jpeg")
    }

    @Test func timelinePhotosShowTheirEditedCopyUntilReverted() async throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        let id = UUID().uuidString
        try write(package, "originals/A/\(id).jpeg")
        let render = package.appending(path: "resources/renders/A/\(id)_1_201_a.jpeg")
        try write(package, "resources/renders/A/\(id)_1_201_a.jpeg")

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await addAndSync(index, package)
        let photo = try #require(try await index.loadTimeline(roots: [source.id: package]).photos.first)
        #expect(photo.libraryPackage == package)
        #expect(photo.displayURL() == render)

        // Reverting the edit removes the render: the original shows again.
        try FileManager.default.removeItem(at: render)
        #expect(photo.displayURL() == photo.url)
    }

    @Test func folderPhotosShowTheirOwnFile() {
        let photo = PhotoItem(url: URL(fileURLWithPath: "/tmp/x/originals/A/a.jpeg"),
                              relativePath: "originals/A/a.jpeg", kind: .image, date: local(2025, 11, 3))
        #expect(photo.displayURL() == photo.url)
    }

    // MARK: Index

    @Test func indexesPackagePhotosWithPathsFromThePackage() async throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        let id = UUID().uuidString
        try write(package, "originals/A/\(id).jpeg", exif: "2025:11:03 10:00:00")
        try write(package, "resources/derivatives/A/\(id)_1_105_c.jpeg", exif: "2025:11:03 10:00:00")

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await addAndSync(index, package)
        #expect(try await index.sources().map(\.kind) == [.libraryPackage])

        let photos = try await index.loadTimeline(roots: [source.id: package]).photos
        #expect(photos.map(\.relativePath) == ["originals/A/\(id).jpeg"])
        #expect(photos.first?.url == package.appending(path: "originals/A/\(id).jpeg"))
        #expect(photos.first?.date == local(2025, 11, 3, 10))
        #expect(photos.first?.assetIdentifier == nil)
    }

    @Test func removedOriginalsLeaveTheIndex() async throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        let keep = UUID().uuidString, drop = UUID().uuidString
        try write(package, "originals/A/\(keep).jpeg")
        try write(package, "originals/B/\(drop).jpeg")

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await addAndSync(index, package)
        try FileManager.default.removeItem(at: package.appending(path: "originals/B/\(drop).jpeg"))
        let result = try await index.sync(sourceID: source.id, root: package)
        #expect(result.removed == 1)
        #expect(try await index.fileCount(sourceID: source.id) == 1)
    }

    @Test func packageWithoutOriginalsIsUnavailableAndKeepsItsIndex() async throws {
        let package = try makePackage()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()) }
        try write(package, "originals/A/\(UUID().uuidString).jpeg")

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await addAndSync(index, package)
        try FileManager.default.removeItem(at: package.appending(path: "originals"))
        await #expect(throws: PhotoIndexError.rootUnavailable) {
            try await index.sync(sourceID: source.id, root: package)
        }
        #expect(try await index.fileCount(sourceID: source.id) == 1)
    }

    // MARK: Date settings

    @Test func packagesNeverUseTheFileNameDate() async throws {
        let package = try makePackage()
        let folder = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(package.deletingLastPathComponent()); Fixtures.cleanUp(folder) }
        try write(package, "originals/A/\(UUID().uuidString).jpeg")

        let index = try PhotoIndex(fileURL: nil, timeZone: utc)
        let source = try await addAndSync(index, package, dateSource: .fileName)
        #expect(source.dateSource == .exif)

        try await index.setDateSource(.fileName, forSource: source.id)
        #expect(try await index.sources().first?.dateSource == .exif)

        let other = try await index.addFolderSource(rootPath: FolderScanner.realPath(folder.path), name: "Folder",
                                                    bookmark: nil, dateSource: .exif)
        try await index.setDateSourceForAll(.fileName)
        let byID = Dictionary(uniqueKeysWithValues: try await index.sources().map { ($0.id, $0.dateSource) })
        #expect(byID == [source.id: .exif, other.id: .fileName])

        try await index.setDateSourceForAll(.modified)
        #expect(try await index.sources().allSatisfy { $0.dateSource == .modified })
    }

    @Test func kindsOfferTheirDateSources() {
        #expect(SourceRecord.Kind.folder.dateSources == DateSourceKind.allCases)
        #expect(!SourceRecord.Kind.libraryPackage.dateSources.contains(.fileName))
        #expect(SourceRecord.Kind.libraryPackage.dateSource(preferring: .fileName) == .exif)
        #expect(SourceRecord.Kind.libraryPackage.dateSource(preferring: .created) == .created)
        #expect(!SourceRecord.Kind.photos.isFileBased)
        #expect(SourceRecord.Kind.libraryPackage.isFileBased)
    }
}

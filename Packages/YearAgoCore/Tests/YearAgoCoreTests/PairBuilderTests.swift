import Foundation
import Testing
@testable import YearAgoCore

@Suite struct PairBuilderTests {
    private func file(_ id: Int64, _ locator: String) -> PairBuilder.File {
        PairBuilder.File(id: id, locator: locator,
                         isRaw: MediaKind.classify(pathExtension: (locator as NSString).pathExtension) == .raw)
    }

    @Test func pairsRawWithJpegIgnoringCase() {
        let pairs = PairBuilder.pairs(in: [file(1, "trip/IMG_1234.CR2"), file(2, "trip/img_1234.jpg")])
        #expect(pairs == [1: 2])
    }

    @Test func pairsRawWithHeic() {
        #expect(PairBuilder.pairs(in: [file(1, "DSC_0001.NEF"), file(2, "DSC_0001.HEIC")]) == [1: 2])
    }

    @Test func loneRawHasNoPartner() {
        #expect(PairBuilder.pairs(in: [file(1, "IMG_1.CR3"), file(2, "IMG_2.JPG")]).isEmpty)
    }

    @Test func differentFoldersDoNotPair() {
        #expect(PairBuilder.pairs(in: [file(1, "a/IMG_1.CR2"), file(2, "b/IMG_1.JPG")]).isEmpty)
    }

    @Test func pngIsNotAPartner() {
        #expect(PairBuilder.pairs(in: [file(1, "IMG_1.DNG"), file(2, "IMG_1.PNG")]).isEmpty)
    }

    @Test func severalRawsShareOnePartnerAndFirstPartnerWins() {
        let pairs = PairBuilder.pairs(in: [
            file(1, "IMG_1.CR2"), file(2, "IMG_1.DNG"), file(3, "IMG_1.JPG"), file(4, "IMG_1.HEIC"),
        ])
        // "IMG_1.HEIC" sorts before "IMG_1.JPG".
        #expect(pairs == [1: 4, 2: 4])
    }

    @Test func stemKeyHandlesDotsInFolderNames() {
        #expect(PairBuilder.stemKey("v1.2/IMG_1.CR2") == "v1.2/img_1")
        #expect(PairBuilder.stemKey("v1.2/README") == "v1.2/readme")
        #expect(PairBuilder.pathExtension("v1.2/README") == "")
    }
}

@Suite struct UnionFindTests {
    @Test func groupsUseSmallestID() {
        var unionFind = UnionFind()
        unionFind.union(5, 3)
        unionFind.union(3, 9)
        unionFind.union(20, 21)
        #expect(unionFind.groups() == [3: 3, 5: 3, 9: 3, 20: 20, 21: 20])
    }

    @Test func unlinkedIDsAreLeftOut() {
        var unionFind = UnionFind()
        #expect(unionFind.find(7) == 7)
        #expect(unionFind.groups().isEmpty)
    }
}

@Suite struct ContentHasherTests {
    @Test func knownDigest() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: url)
        let hex = ContentHasher.sha256(of: url)?.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func spansChunks() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("b")
        var bytes = Data(repeating: 7, count: ContentHasher.chunkSize * 2 + 5)
        try bytes.write(to: a)
        bytes[bytes.count - 1] = 8
        try bytes.write(to: b)
        #expect(ContentHasher.sha256(of: a) != ContentHasher.sha256(of: b))
    }

    @Test func missingFileIsNil() {
        #expect(ContentHasher.sha256(of: URL(fileURLWithPath: "/nonexistent/file")) == nil)
    }
}

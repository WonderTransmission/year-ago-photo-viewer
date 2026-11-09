import Foundation
import ImageIO
import Testing
@testable import YearAgoCore

@Suite struct ImageLoaderTests {
    @Test func boundsLongestSide() async throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("big.jpg")
        try Fixtures.writeImage(to: url, width: 400, height: 300)

        let image = try #require(await ImageLoader().image(at: url, maxPixelSize: 100))
        #expect(max(image.width, image.height) == 100)
        #expect(image.width == 100 && image.height == 75)
    }

    @Test func appliesExifOrientation() async throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("rotated.jpg")
        // Orientation 6: stored landscape, displayed portrait.
        try Fixtures.writeImage(to: url, width: 40, height: 20,
                                tiff: [kCGImagePropertyTIFFOrientation: 6])
        let image = try #require(ImageLoader.decode(url, maxPixelSize: 100))
        #expect(image.width == 20 && image.height == 40)
    }

    @Test func undecodableFileIsNil() async throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: url)
        #expect(await ImageLoader().image(at: url, maxPixelSize: 100) == nil)
    }
}

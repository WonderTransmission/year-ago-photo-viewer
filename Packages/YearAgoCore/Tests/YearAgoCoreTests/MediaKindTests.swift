import Testing
@testable import YearAgoCore

@Suite struct MediaKindTests {
    @Test(arguments: ["jpg", "JPG", "jpeg", "heic", "HEIC", "heif", "png", "tif", "tiff", "gif", "webp"])
    func images(ext: String) {
        #expect(MediaKind.classify(pathExtension: ext) == .image)
    }

    @Test(arguments: ["cr2", "CR2", "cr3", "nef", "arw", "raf", "orf", "dng", "rw2", "pef"])
    func raws(ext: String) {
        #expect(MediaKind.classify(pathExtension: ext) == .raw)
    }

    @Test(arguments: ["mov", "MOV", "mp4", "m4v", "avi"])
    func videos(ext: String) {
        #expect(MediaKind.classify(pathExtension: ext) == .video)
    }

    @Test(arguments: ["xmp", "XMP", "aae", "AAE"])
    func sidecars(ext: String) {
        #expect(MediaKind.classify(pathExtension: ext) == .sidecar)
    }

    @Test(arguments: ["", "txt", "pdf", "zip", "notarealextension"])
    func others(ext: String) {
        #expect(MediaKind.classify(pathExtension: ext) == .other)
    }

    @Test func onlyImagesAndRawsAreDisplayable() {
        #expect(MediaKind.image.isDisplayable)
        #expect(MediaKind.raw.isDisplayable)
        #expect(!MediaKind.video.isDisplayable)
        #expect(!MediaKind.sidecar.isDisplayable)
        #expect(!MediaKind.other.isDisplayable)
    }
}

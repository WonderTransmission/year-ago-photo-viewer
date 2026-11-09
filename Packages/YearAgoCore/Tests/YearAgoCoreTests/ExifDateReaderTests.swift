import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import YearAgoCore

@Suite struct ExifDateReaderTests {
    @Test func readsDateTimeOriginal() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("a.jpg")
        try Fixtures.writeImage(to: url, exif: [
            kCGImagePropertyExifDateTimeOriginal: "2021:07:04 18:30:12",
            kCGImagePropertyExifDateTimeDigitized: "2021:07:05 09:00:00",
        ])
        #expect(ExifDateReader.captureDate(at: url) == local(2021, 7, 4, 18, 30, 12))
    }

    @Test func fallsBackToDateTimeDigitized() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("b.jpg")
        try Fixtures.writeImage(to: url, exif: [
            kCGImagePropertyExifDateTimeDigitized: "2021:07:05 09:00:00",
        ])
        #expect(ExifDateReader.captureDate(at: url) == local(2021, 7, 5, 9))
    }

    @Test func fallsBackToTIFFDateTime() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        // ImageIO's JPEG writer drops a lone TIFF DateTime, so use a TIFF file.
        let url = dir.appendingPathComponent("c.tiff")
        try Fixtures.writeImage(to: url, type: .tiff, tiff: [
            kCGImagePropertyTIFFDateTime: "2019:12:31 23:59:59",
        ])
        #expect(ExifDateReader.captureDate(at: url) == local(2019, 12, 31, 23, 59, 59))
    }

    @Test func skipsZeroedDateAndUsesNextField() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("d.jpg")
        try Fixtures.writeImage(to: url, exif: [
            kCGImagePropertyExifDateTimeOriginal: "0000:00:00 00:00:00",
            kCGImagePropertyExifDateTimeDigitized: "2020:02:29 12:00:00",
        ])
        #expect(ExifDateReader.captureDate(at: url) == local(2020, 2, 29, 12))
    }

    @Test func imageWithoutDatesReturnsNil() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("e.png")
        try Fixtures.writeImage(to: url, type: .png)
        #expect(ExifDateReader.captureDate(at: url) == nil)
    }

    @Test func heicWithDate() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("f.heic")
        try Fixtures.writeImage(to: url, type: .heic, width: 64, height: 48, exif: [
            kCGImagePropertyExifDateTimeOriginal: "2018:05:06 07:08:09",
        ])
        #expect(ExifDateReader.captureDate(at: url) == local(2018, 5, 6, 7, 8, 9))
    }

    @Test func nonImageAndMissingFilesReturnNil() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let text = dir.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        #expect(ExifDateReader.captureDate(at: text) == nil)
        #expect(ExifDateReader.captureDate(at: dir.appendingPathComponent("missing.jpg")) == nil)
    }

    @Test(arguments: [
        ("2021:07:04 18:30:12", local(2021, 7, 4, 18, 30, 12)),
        ("2021-07-04 18:30:12", local(2021, 7, 4, 18, 30, 12)),
        ("2021:07:04T18:30:12", local(2021, 7, 4, 18, 30, 12)),
        ("2021:07:04 18:30:12.345", local(2021, 7, 4, 18, 30, 12)),
        (" 2021:07:04 18:30:12 ", local(2021, 7, 4, 18, 30, 12)),
    ])
    func parsesDateStrings(text: String, expected: LocalDateTime) {
        #expect(ExifDateReader.parse(text) == expected)
    }

    @Test(arguments: [
        "", "    :  :     :  :  ", "0000:00:00 00:00:00", "2021:13:01 00:00:00",
        "2021:02:29 00:00:00", "2021:07:04", "21:07:04 18:30:12", "2021/07/04 18:30:12",
    ])
    func rejectsBadDateStrings(text: String) {
        #expect(ExifDateReader.parse(text) == nil)
    }
}

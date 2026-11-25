import Foundation
import ImageIO
import Testing
@testable import YearAgoCore

/// Photo info plan step 4.1. All metadata here is made up.
@Suite struct PhotoInfoTests {
    private let exifKey = kCGImagePropertyExifDictionary as String
    private let tiffKey = kCGImagePropertyTIFFDictionary as String
    private let gpsKey = kCGImagePropertyGPSDictionary as String

    /// A typical camera photo's properties, as ImageIO returns them.
    private var cameraProperties: [String: Any] {
        [
            kCGImagePropertyPixelWidth as String: 4032,
            kCGImagePropertyPixelHeight as String: 3024,
            kCGImagePropertyOrientation as String: 6,
            kCGImagePropertyProfileName as String: "Display P3",
            tiffKey: [
                kCGImagePropertyTIFFMake as String: "Examplecam",
                kCGImagePropertyTIFFModel as String: "X100",
                kCGImagePropertyTIFFSoftware as String: "1.0",
                kCGImagePropertyTIFFDateTime as String: "2025:11:04 08:00:00",
            ],
            exifKey: [
                kCGImagePropertyExifExposureTime as String: 0.004,
                kCGImagePropertyExifFNumber as String: 2.8,
                kCGImagePropertyExifISOSpeedRatings as String: [400],
                kCGImagePropertyExifExposureBiasValue as String: -0.7,
                kCGImagePropertyExifExposureProgram as String: 2,
                kCGImagePropertyExifMeteringMode as String: 5,
                kCGImagePropertyExifFlash as String: 16,
                kCGImagePropertyExifWhiteBalance as String: 0,
                kCGImagePropertyExifLensModel as String: "Example 23mm f/2",
                kCGImagePropertyExifFocalLength as String: 23,
                kCGImagePropertyExifFocalLenIn35mmFilm as String: 35,
                kCGImagePropertyExifDateTimeOriginal as String: "2025:11:03 10:00:00",
                kCGImagePropertyExifOffsetTimeOriginal as String: "+01:00",
                kCGImagePropertyExifSceneType as String: 1,
                kCGImagePropertyExifMakerNote as String: Data([1, 2, 3]),
            ],
            gpsKey: [
                kCGImagePropertyGPSLatitude as String: 33.8688,
                kCGImagePropertyGPSLatitudeRef as String: "S",
                kCGImagePropertyGPSLongitude as String: 151.2093,
                kCGImagePropertyGPSLongitudeRef as String: "E",
                kCGImagePropertyGPSAltitude as String: 12.5,
                kCGImagePropertyGPSAltitudeRef as String: 0,
                kCGImagePropertyGPSImgDirection as String: 123.4,
                kCGImagePropertyGPSImgDirectionRef as String: "T",
                kCGImagePropertyGPSHPositioningError as String: 5,
            ],
            "{MakerExample}": ["Inner": ["Deep": 7], "Blob": Data([0])],
        ]
    }

    // MARK: Sections

    @Test func groupsKnownValuesIntoSections() {
        let info = PhotoInfoReader.info(fromProperties: cameraProperties, typeIdentifier: "public.jpeg",
                                        fileSize: 2_500_000)
        #expect(info.sections.map(\.title).prefix(6) == ["Camera", "Exposure", "Lens", "Image", "Dates", "Location"])
        #expect(info.value("Make") == "Examplecam")
        #expect(info.value("Model") == "X100")
        #expect(info.value("Shutter speed") == "1/250 s")
        #expect(info.value("Aperture") == "f/2.8")
        #expect(info.value("ISO") == "400")
        #expect(info.value("Exposure bias") == "−0.7 EV")
        #expect(info.value("Program") == "Normal")
        #expect(info.value("Metering") == "Pattern")
        #expect(info.value("Flash") == "Did not fire")
        #expect(info.value("White balance") == "Auto")
        #expect(info.value("Lens") == "Example 23mm f/2")
        #expect(info.value("Focal length") == "23 mm")
        #expect(info.value("35 mm equivalent") == "35 mm")
        #expect(info.value("Size") == "4032 × 3024 pixels")
        #expect(info.value("Orientation") == "Rotated 90° clockwise")
        #expect(info.value("Color profile") == "Display P3")
        #expect(info.value("File type") != nil)
        #expect(info.value("File size") != nil)
        #expect(info.value("Taken") == "2025-11-03 10:00:00 +01:00")
        #expect(info.value("Modified") == "2025-11-04 08:00:00")
    }

    @Test func locationAppliesReferencesAndDetails() throws {
        let info = PhotoInfoReader.info(fromProperties: cameraProperties)
        let coordinate = try #require(info.coordinate)
        #expect(coordinate.latitude == -33.8688)
        #expect(coordinate.longitude == 151.2093)
        #expect(info.value("Coordinates") == "33.86880° S, 151.20930° E")
        #expect(info.value("Altitude") == "12.5 m")
        #expect(info.value("Direction") == "123.4° (true north)")
        #expect(info.value("Accuracy") == "± 5 m")
    }

    @Test func westernAndBelowSeaLevel() throws {
        let properties: [String: Any] = [gpsKey: [
            kCGImagePropertyGPSLatitude as String: 36.4622,
            kCGImagePropertyGPSLatitudeRef as String: "N",
            kCGImagePropertyGPSLongitude as String: 116.8669,
            kCGImagePropertyGPSLongitudeRef as String: "W",
            kCGImagePropertyGPSAltitude as String: 86,
            kCGImagePropertyGPSAltitudeRef as String: 1,
        ]]
        let info = PhotoInfoReader.info(fromProperties: properties)
        #expect(info.coordinate?.longitude == -116.8669)
        #expect(info.value("Coordinates") == "36.46220° N, 116.86690° W")
        #expect(info.value("Altitude") == "-86 m")
    }

    @Test func labelsColorSpaceAndShowsResolutionOnce() {
        let properties: [String: Any] = [
            exifKey: [kCGImagePropertyExifColorSpace as String: 65535],
            tiffKey: [kCGImagePropertyTIFFXResolution as String: 300,
                      kCGImagePropertyTIFFYResolution as String: 300,
                      kCGImagePropertyTIFFResolutionUnit as String: 2],
        ]
        let info = PhotoInfoReader.info(fromProperties: properties)
        #expect(info.value("Color space") == "Uncalibrated")
        #expect(info.value("Resolution") == "300 × 300 dpi")
        #expect(info.section("More: TIFF") == nil)
        #expect(info.section("More: EXIF") == nil)
        #expect(Format.colorSpace(1) == "sRGB")
    }

    @Test func showsFileDates() throws {
        let created = Date(timeIntervalSince1970: TimeInterval(local(2025, 11, 3, 9).seconds))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let info = PhotoInfoReader.info(fromProperties: [:], fileCreated: created,
                                        fileModified: created.addingTimeInterval(60), timeZone: utc)
        #expect(info.value("File created") == "2025-11-03 09:00:00 +00:00")
        #expect(info.value("File modified") == "2025-11-03 09:01:00 +00:00")
    }

    @Test func insertsRowsFirstOrInANewSection() {
        var info = PhotoInfo(sections: [
            PhotoInfo.Section("Image", [PhotoInfo.Row("Size", "1 × 1 pixels")]),
            PhotoInfo.Section("Location", [PhotoInfo.Row("Coordinates", "x")]),
        ])
        info.insertFirst(PhotoInfo.Row("Date used", "EXIF date"), inSection: "Dates")
        #expect(info.sections.map(\.title) == ["Image", "Dates", "Location"])
        info.insertFirst(PhotoInfo.Row("Note", "first"), inSection: "Dates")
        #expect(info.section("Dates")?.rows.map(\.label) == ["Note", "Date used"])
    }

    @Test func noFixMeansNoLocation() {
        let properties: [String: Any] = [gpsKey: [
            kCGImagePropertyGPSLatitude as String: 0,
            kCGImagePropertyGPSLongitude as String: 0,
        ]]
        let info = PhotoInfoReader.info(fromProperties: properties)
        #expect(info.coordinate == nil)
        #expect(info.section("Location") == nil)
    }

    @Test func remainingValuesGoToMoreSectionsAndBinaryIsCounted() throws {
        let info = PhotoInfoReader.info(fromProperties: cameraProperties)
        let moreExif = try #require(info.section("More: EXIF"))
        #expect(moreExif.rows == [PhotoInfo.Row("Scene Type", "1")])
        let maker = try #require(info.section("More: Example maker notes"))
        #expect(maker.rows == [PhotoInfo.Row("Inner › Deep", "7")])
        // The EXIF maker note and the Blob.
        #expect(info.skippedBinaryCount == 2)
        // Shown values aren't repeated in "More" sections.
        #expect(info.section("More: TIFF") == nil)
        #expect(info.section("More: GPS") == nil)
    }

    @Test func emptyMetadataGivesNoSections() {
        let info = PhotoInfoReader.info(fromProperties: [:])
        #expect(info.sections.isEmpty)
        #expect(info.coordinate == nil)
    }

    @Test func plainTextListsSectionsAndRows() {
        let info = PhotoInfo(sections: [
            PhotoInfo.Section("Camera", [PhotoInfo.Row("Make", "Examplecam")]),
            PhotoInfo.Section("Empty", []),
            PhotoInfo.Section("Lens", [PhotoInfo.Row("Focal length", "23 mm")]),
        ])
        #expect(info.sections.count == 2)
        #expect(info.plainText == "Camera\nMake: Examplecam\n\nLens\nFocal length: 23 mm")
    }

    // MARK: Formatting

    @Test func formatsShutterSpeeds() {
        #expect(Format.shutter(1.0 / 250) == "1/250 s")
        #expect(Format.shutter(1.0 / 3) == "1/3 s")
        #expect(Format.shutter(0.5) == "0.5 s")
        #expect(Format.shutter(2) == "2 s")
        #expect(Format.shutter(1.3) == "1.3 s")
    }

    @Test func formatsBiasFlashAndOrientation() {
        #expect(Format.bias(0) == "0 EV")
        #expect(Format.bias(0.33) == "+0.3 EV")
        #expect(Format.bias(-1) == "−1 EV")
        #expect(Format.flash(1) == "Fired")
        #expect(Format.flash(25) == "Fired")
        #expect(Format.flash(24) == "Did not fire")
        #expect(Format.orientation(1) == "Normal")
        #expect(Format.orientation(8) == "Rotated 270° clockwise")
    }

    @Test func formatsPlainValues() {
        #expect(Format.plain("text") == "text")
        #expect(Format.plain(NSNumber(value: 3)) == "3")
        #expect(Format.plain(NSNumber(value: 0.25)) == "0.25")
        #expect(Format.plain(kCFBooleanTrue as Any) == "Yes")
        #expect(Format.plain([2, 3, 2]) == "2, 3, 2")
        #expect(Format.plain(Array(repeating: 1, count: 100)) == nil)
        #expect(Format.plain(Data([1])) == nil)
    }

    @Test func labelsUnknownKeys() {
        #expect(Format.label(forKey: "ExposureTime") == "Exposure Time")
        #expect(Format.label(forKey: "ISOSpeedRatings") == "ISO Speed Ratings")
        #expect(Format.label(forKey: "SubsecTimeOriginal") == "Subsec Time Original")
        #expect(Format.label(forKey: "PixelXDimension") == "Pixel X Dimension")
        #expect(Format.label(forKey: "_Private") == "Private")
        #expect(Format.dictionaryName("{MakerApple}") == "Apple maker notes")
        #expect(Format.dictionaryName("{PNG}") == "PNG")
    }

    @Test func mapsURLCarriesCoordinateAndLabel() throws {
        let coordinate = try #require(Coordinate(latitude: -33.8688, longitude: 151.2093))
        let url = coordinate.mapsURL(label: "3 Nov 2025")
        #expect(url.scheme == "maps")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "ll" }?.value == "-33.868800,151.209300")
        #expect(items.first { $0.name == "q" }?.value == "3 Nov 2025")
        #expect(Coordinate(latitude: 91, longitude: 0) == nil)
    }

    // MARK: Photos library items

    @Test func libraryItemShowsBasicInfoAndNote() throws {
        let created = Date(timeIntervalSince1970: TimeInterval(local(2025, 11, 3, 9).seconds))
        let details = LibraryAssetDetails(
            created: created, modified: created.addingTimeInterval(3600),
            pixelWidth: 4032, pixelHeight: 3024, kinds: ["Live Photo", "HDR"], isFavorite: true,
            fileName: "IMG_0001.HEIC",
            location: .init(latitude: -33.8688, longitude: 151.2093, altitude: 12.5, course: 90,
                            speed: 2, accuracy: 4.7))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let info = PhotoInfo.libraryItem(details, timeZone: tokyo)

        #expect(info.sections.map(\.title) == ["Image", "Dates", "Location"])
        #expect(info.value("File name") == "IMG_0001.HEIC")
        #expect(info.value("Size") == "4032 × 3024 pixels")
        #expect(info.value("Kind") == "Live Photo, HDR")
        #expect(info.value("Favorite") == "Yes")
        #expect(info.value("Taken") == "2025-11-03 18:00:00 +09:00")
        #expect(info.value("Modified") == "2025-11-03 19:00:00 +09:00")
        #expect(info.value("Coordinates") == "33.86880° S, 151.20930° E")
        #expect(info.value("Altitude") == "12.5 m")
        #expect(info.value("Direction") == "90° (true north)")
        #expect(info.value("Speed") == "7.2 km/h")
        #expect(info.value("Accuracy") == "± 4.7 m")
        #expect(info.coordinate?.latitude == -33.8688)
        #expect(info.note == PhotoInfo.libraryNote)
    }

    @Test func libraryItemWithoutLocationOrExtras() {
        let details = LibraryAssetDetails(created: nil, modified: nil, pixelWidth: 100, pixelHeight: 50)
        let info = PhotoInfo.libraryItem(details)
        #expect(info.sections.map(\.title) == ["Image"])
        #expect(info.value("Kind") == nil)
        #expect(info.value("Favorite") == nil)
        #expect(info.coordinate == nil)
        #expect(info.note == PhotoInfo.libraryNote)
    }

    // MARK: Files

    @Test func readsAGeneratedFile() throws {
        let folder = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(folder) }
        let url = folder.appendingPathComponent("photo.jpg")
        try Fixtures.writeImage(
            to: url, width: 40, height: 30,
            exif: [kCGImagePropertyExifDateTimeOriginal: "2025:11:03 10:00:00",
                   kCGImagePropertyExifFNumber: 4.0],
            tiff: [kCGImagePropertyTIFFMake: "Examplecam"],
            gps: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
                  kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"])

        let info = try #require(PhotoInfoReader.read(at: url))
        #expect(info.value("Make") == "Examplecam")
        #expect(info.value("Aperture") == "f/4")
        #expect(info.value("Size") == "40 × 30 pixels")
        #expect(info.value("Taken") == "2025-11-03 10:00:00")
        // GPS is stored as fractions, so compare with a tolerance.
        let coordinate = try #require(info.coordinate)
        #expect(abs(coordinate.latitude - 51.5) < 1e-6)
        #expect(abs(coordinate.longitude - -0.12) < 1e-6)
        #expect(info.value("File size") != nil)
    }

    @Test func unreadableFileGivesNil() throws {
        let folder = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(folder) }
        let url = folder.appendingPathComponent("notes.jpg")
        try Data("not an image".utf8).write(to: url)
        #expect(PhotoInfoReader.read(at: url) == nil)
        #expect(PhotoInfoReader.read(at: folder.appendingPathComponent("missing.jpg")) == nil)
    }
}

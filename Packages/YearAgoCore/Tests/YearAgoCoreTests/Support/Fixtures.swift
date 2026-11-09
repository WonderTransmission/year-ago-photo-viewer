import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import YearAgoCore

/// Builds test images at run time, so the repo holds no image files.
enum Fixtures {
    /// A fresh, empty temporary directory. Remove it with `cleanUp`.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YearAgoCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a small solid-colour image with the given metadata.
    /// - Parameters:
    ///   - exif: entries for the EXIF dictionary, e.g. DateTimeOriginal.
    ///   - tiff: entries for the TIFF dictionary, e.g. DateTime.
    static func writeImage(
        to url: URL,
        type: UTType = .jpeg,
        width: Int = 8,
        height: Int = 6,
        exif: [CFString: Any] = [:],
        tiff: [CFString: Any] = [:]
    ) throws {
        let image = try solidImage(width: width, height: height)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw FixtureError.cannotCreateDestination(url)
        }
        var properties: [CFString: Any] = [:]
        if !exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif }
        if !tiff.isEmpty { properties[kCGImagePropertyTIFFDictionary] = tiff }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.cannotWrite(url)
        }
    }

    private static func solidImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw FixtureError.cannotCreateImage }
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw FixtureError.cannotCreateImage }
        return image
    }

    enum FixtureError: Error {
        case cannotCreateImage
        case cannotCreateDestination(URL)
        case cannotWrite(URL)
    }
}

/// Shorthand for building expected dates in tests.
func local(_ year: Int, _ month: Int, _ day: Int,
           _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> LocalDateTime {
    guard let value = LocalDateTime(year: year, month: month, day: day,
                                    hour: hour, minute: minute, second: second) else {
        preconditionFailure("Invalid test date \(year)-\(month)-\(day) \(hour):\(minute):\(second)")
    }
    return value
}

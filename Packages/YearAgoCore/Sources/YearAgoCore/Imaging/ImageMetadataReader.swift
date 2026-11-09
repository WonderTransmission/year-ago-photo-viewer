import Foundation
import ImageIO

/// What the index needs from inside an image file.
public struct ImageMetadata: Equatable, Sendable {
    public var captureDate: LocalDateTime?
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(captureDate: LocalDateTime? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        self.captureDate = captureDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Reads capture date and pixel size in one ImageIO call.
public enum ImageMetadataReader {
    /// Returns empty metadata if the file is missing or not a readable image.
    public static func read(at url: URL) -> ImageMetadata {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return ImageMetadata() }
        return ImageMetadata(
            captureDate: ExifDateReader.captureDate(fromProperties: properties),
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int
        )
    }
}

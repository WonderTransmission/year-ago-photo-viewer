import CoreGraphics
import Foundation
import ImageIO

/// Decodes images at a bounded size, off the main actor, with a memory cache.
///
/// Uses ImageIO's thumbnail path for full-size display too. It decodes a
/// 50-megapixel RAW at screen size quickly and applies EXIF orientation.
public final class ImageLoader: @unchecked Sendable {
    // NSCache is thread-safe, which makes the @unchecked Sendable sound.
    private let cache = NSCache<NSString, CGImage>()

    public init(countLimit: Int = 48) {
        cache.countLimit = countLimit
    }

    /// The image at `url`, scaled so its longest side is at most
    /// `maxPixelSize`. Returns nil if the file cannot be decoded.
    @concurrent
    public func image(at url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = "\(maxPixelSize)|\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard !Task.isCancelled, let image = Self.decode(url, maxPixelSize: maxPixelSize) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Synchronous decode, without caching.
    public static func decode(_ url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

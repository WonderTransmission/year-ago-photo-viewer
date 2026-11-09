import AppKit
import Photos
import YearAgoCore

/// The system Photos library, through PhotoKit.
struct PhotoKitLibrary: PhotoLibraryProviding {
    /// True when the app may read the library (full or limited access).
    static var isAuthorized: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }

    /// True when the user has not been asked yet.
    static var isUndetermined: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined
    }

    /// Asks for access if needed. Returns whether the app may read photos.
    static func requestAccess() async -> Bool {
        switch await PHPhotoLibrary.requestAuthorization(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }

    /// Opens System Settings at Privacy & Security › Photos.
    @MainActor
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }

    @concurrent
    func imageAssets() async throws -> [LibraryAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var assets: [LibraryAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(LibraryAsset(
                localIdentifier: asset.localIdentifier,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight))
        }
        return assets
    }

    @concurrent
    func originalFileNames(for localIdentifiers: [String]) async -> [String: String] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var names: [String: String] = [:]
        result.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let original = resources.first { $0.type == .photo }
                ?? resources.first { $0.type == .fullSizePhoto }
                ?? resources.first
            if let original {
                names[asset.localIdentifier] = original.originalFilename
            }
        }
        return names
    }
}

/// Calls a handler whenever the Photos library changes.
final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        handler()
    }
}

/// Loads library images at a bounded size. Live Photos return their still
/// key frame, which is what PhotoKit gives for an image request.
final class LibraryImageLoader: @unchecked Sendable {
    // PHCachingImageManager and NSCache are thread-safe.
    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, CGImage>()

    init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    func image(assetID: String, maxPixelSize: Int) async -> CGImage? {
        let key = "\(maxPixelSize)|\(assetID)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true   // iCloud originals are fetched by the Photos daemon
        options.version = .current
        let size = CGSize(width: maxPixelSize, height: maxPixelSize)
        let image: CGImage? = await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
}

/// Loads any photo: files through ImageIO, library items through PhotoKit.
final class ImageRepository: Sendable {
    private let files: ImageLoader
    private let library: LibraryImageLoader

    init(countLimit: Int) {
        files = ImageLoader(countLimit: countLimit)
        library = LibraryImageLoader(countLimit: countLimit)
    }

    func image(for photo: PhotoItem, maxPixelSize: Int) async -> CGImage? {
        if let assetID = photo.assetIdentifier {
            return await library.image(assetID: assetID, maxPixelSize: maxPixelSize)
        }
        return await files.image(at: photo.url, maxPixelSize: maxPixelSize)
    }
}

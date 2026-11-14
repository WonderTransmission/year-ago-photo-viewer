import AppKit
import Photos
import YearAgoCore

/// What the app needs from a Photos library: indexing (from the core
/// protocol), access, and change notifications.
///
/// Rule: implementations never run on the main thread. The first call into
/// PhotoKit waits for macOS to open the library, which can take many
/// minutes (seen: 20 minutes after a macOS upgrade, on a USB hard drive).
/// Every method here is `@concurrent` so that wait can't freeze the UI.
protocol AppPhotoLibrary: PhotoLibraryProviding {
    /// True when the app may read the library (full or limited access).
    func accessGranted() async -> Bool
    /// Asks for access if needed. Returns whether the app may read photos.
    func requestAccess() async -> Bool
    /// Starts calling `handler` when the library changes. Stop the returned
    /// observation to end it.
    func startObservingChanges(_ handler: @escaping @Sendable () -> Void) async -> LibraryObservation?
}

/// An active change observation. `stop()` runs off the main thread.
protocol LibraryObservation: Sendable {
    func stop() async
}

/// The system Photos library, through PhotoKit.
struct PhotoKitLibrary: AppPhotoLibrary {
    @concurrent
    func accessGranted() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }

    @concurrent
    func requestAccess() async -> Bool {
        switch await PHPhotoLibrary.requestAuthorization(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }

    @concurrent
    func startObservingChanges(_ handler: @escaping @Sendable () -> Void) async -> LibraryObservation? {
        // `register` opens the library: this is the call that blocked the
        // main thread for 20 minutes. Off the main thread it only blocks here.
        let observer = PhotoKitChangeObserver(handler: handler)
        PHPhotoLibrary.shared().register(observer)
        return observer
    }

    /// Opens System Settings at Privacy & Security › Photos.
    @MainActor
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the Photos app, which shows its own progress while macOS
    /// upgrades or prepares a library.
    @MainActor
    static func openPhotosApp() {
        if let photos = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
            NSWorkspace.shared.openApplication(at: photos, configuration: NSWorkspace.OpenConfiguration())
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
private final class PhotoKitChangeObserver: NSObject, PHPhotoLibraryChangeObserver, LibraryObservation,
                                           @unchecked Sendable {
    // Immutable after init; PhotoKit calls `photoLibraryDidChange` on its own queue.
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        super.init()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        handler()
    }

    @concurrent
    func stop() async {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}

/// Loads library images at a bounded size, off the main thread. Live Photos
/// return their still key frame, which is what PhotoKit gives for an image
/// request.
final class LibraryImageLoader: @unchecked Sendable {
    // NSCache is thread-safe. The image manager is fetched per request (and
    // off the main thread), so nothing touches PhotoKit at app launch.
    private let cache = NSCache<NSString, CGImage>()

    init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    @concurrent
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
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                  options: options) { image, _ in
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

    @concurrent
    func image(for photo: PhotoItem, maxPixelSize: Int) async -> CGImage? {
        if let assetID = photo.assetIdentifier {
            return await library.image(assetID: assetID, maxPixelSize: maxPixelSize)
        }
        return await files.image(at: photo.url, maxPixelSize: maxPixelSize)
    }
}

#if DEBUG
/// A stand-in Photos library for testing responsiveness, enabled with
/// `-DebugFakeLibrary <seconds to open>`. Like PhotoKit after a macOS
/// upgrade, every call blocks the calling thread until the library has
/// "opened". If any call runs on the main thread, the window freezes and the
/// main-thread watchdog reports it.
final class SlowFakePhotoLibrary: AppPhotoLibrary, @unchecked Sendable {
    private let lock = NSLock()
    private let openDelay: TimeInterval
    private let assetCount: Int
    private var openedAt: Date?

    init(openDelay: TimeInterval, assetCount: Int = 2_000) {
        self.openDelay = openDelay
        self.assetCount = assetCount
    }

    /// Blocks the calling thread until `openDelay` after the first call.
    private func waitForOpen() {
        let openAt = lock.withLock {
            if openedAt == nil { openedAt = Date().addingTimeInterval(openDelay) }
            return openedAt!
        }
        let remaining = openAt.timeIntervalSinceNow
        if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
    }

    @concurrent func accessGranted() async -> Bool { true }
    @concurrent func requestAccess() async -> Bool { true }

    @concurrent
    func startObservingChanges(_ handler: @escaping @Sendable () -> Void) async -> LibraryObservation? {
        waitForOpen()
        return nil
    }

    @concurrent
    func imageAssets() async throws -> [LibraryAsset] {
        waitForOpen()
        // Spread over the last three years, so every year window has some.
        let now = Date()
        return (0..<assetCount).map { i in
            let date = now.addingTimeInterval(-Double(i) * 3 * 365 * 86_400 / Double(assetCount))
            return LibraryAsset(localIdentifier: "fake-\(i)", creationDate: date, modificationDate: date,
                                pixelWidth: 4032, pixelHeight: 3024)
        }
    }

    @concurrent
    func originalFileNames(for localIdentifiers: [String]) async -> [String: String] {
        waitForOpen()
        return [:]
    }
}
#endif

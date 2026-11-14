import AppKit
import OSLog
import Photos
import YearAgoCore

private let logger = Logger(subsystem: "YearAgoPhotoViewer", category: "photos")

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
    /// Starts calling `handler` when the library's images change, with
    /// exactly what changed when Photos can say. Stop the returned
    /// observation to end it.
    func startObservingChanges(_ handler: @escaping @Sendable (LibraryChange) -> Void) async -> LibraryObservation?
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
    func startObservingChanges(_ handler: @escaping @Sendable (LibraryChange) -> Void) async -> LibraryObservation? {
        // `register` opens the library: this is the call that blocked the
        // main thread for 20 minutes. Off the main thread it only blocks here.
        let observer = PhotoKitChangeObserver(handler: handler)
        PHPhotoLibrary.shared().register(observer)
        // The same query as indexing, so its change details say exactly
        // which images were added, changed, or removed.
        observer.track(PHAsset.fetchAssets(with: Self.imageFetchOptions()))
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
    func openImageAssets() async throws -> any LibraryAssetList {
        // Lazy: the count is known at once and assets load as they're read.
        let result = PHAsset.fetchAssets(with: Self.imageFetchOptions())
        Self.logLibraryComposition(imageCount: result.count)
        return PhotoKitAssetList(result: result)
    }

    @concurrent
    func openImageAssets(createdIn ranges: [ClosedRange<Date>]) async throws -> any LibraryAssetList {
        // Filtered inside Photos, so this is quick even on large libraries.
        let options = Self.imageFetchOptions()
        let dates = ranges.map {
            NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", $0.lowerBound as NSDate, $0.upperBound as NSDate)
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSCompoundPredicate(orPredicateWithSubpredicates: dates),
        ])
        return PhotoKitAssetList(result: PHAsset.fetchAssets(with: options))
    }

    /// Images only, PhotoKit's defaults otherwise (hidden photos and
    /// non-representative burst frames excluded).
    static func imageFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return options
    }

    /// Logs what the image fetch includes, as counts only, to explain any
    /// difference from the count Photos shows (plan section 6). Counting is
    /// quick once the library is open.
    private static func logLibraryComposition(imageCount: Int) {
        func count(_ configure: (PHFetchOptions) -> Void) -> Int {
            let options = imageFetchOptions()
            configure(options)
            return PHAsset.fetchAssets(with: options).count
        }
        func withSubtype(_ subtype: PHAssetMediaSubtype) -> Int {
            count {
                $0.predicate = NSPredicate(format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
                                           PHAssetMediaType.image.rawValue, subtype.rawValue)
            }
        }
        let userLibrary = count { $0.includeAssetSourceTypes = .typeUserLibrary }
        let shared = count { $0.includeAssetSourceTypes = .typeCloudShared }
        let synced = count { $0.includeAssetSourceTypes = .typeiTunesSynced }
        let hidden = count { $0.includeHiddenAssets = true } - imageCount
        let extraBurstFrames = count { $0.includeAllBurstAssets = true } - imageCount
        let screenshots = withSubtype(.photoScreenshot)
        let live = withSubtype(.photoLive)
        let videos = PHAsset.fetchAssets(with: .video, options: nil).count
        logger.notice("Library images fetched: \(imageCount, privacy: .public) (user library \(userLibrary, privacy: .public), shared \(shared, privacy: .public), synced \(synced, privacy: .public)); screenshots \(screenshots, privacy: .public), Live Photos \(live, privacy: .public); not fetched: hidden \(hidden, privacy: .public), extra burst frames \(extraBurstFrames, privacy: .public); videos \(videos, privacy: .public)")
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

/// The library's image assets, backed by a lazy PhotoKit fetch result.
private struct PhotoKitAssetList: LibraryAssetList, @unchecked Sendable {
    // PHFetchResult is immutable and safe to read from any thread.
    let result: PHFetchResult<PHAsset>

    var count: Int { result.count }

    @concurrent
    func assets(in range: Range<Int>) async throws -> [LibraryAsset] {
        result.objects(at: IndexSet(integersIn: range)).map { asset in
            LibraryAsset(localIdentifier: asset.localIdentifier,
                         creationDate: asset.creationDate,
                         modificationDate: asset.modificationDate,
                         pixelWidth: asset.pixelWidth,
                         pixelHeight: asset.pixelHeight)
        }
    }
}

/// Reports changes to the library's images. With a tracked fetch result,
/// PhotoKit's change details give exactly what was added, changed, or
/// removed; otherwise the change is reported as unknown.
private final class PhotoKitChangeObserver: NSObject, PHPhotoLibraryChangeObserver, LibraryObservation,
                                           @unchecked Sendable {
    // Safe: `tracked` is only touched under `lock`; `handler` is immutable.
    private let handler: @Sendable (LibraryChange) -> Void
    private let lock = NSLock()
    private var tracked: PHFetchResult<PHAsset>?

    init(handler: @escaping @Sendable (LibraryChange) -> Void) {
        self.handler = handler
        super.init()
    }

    func track(_ result: PHFetchResult<PHAsset>) {
        lock.withLock { tracked = result }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let change: LibraryChange? = lock.withLock {
            guard let current = tracked else { return .unknown }
            // Nil: nothing changed among the tracked images.
            guard let details = changeInstance.changeDetails(for: current) else { return nil }
            tracked = details.fetchResultAfterChanges
            guard details.hasIncrementalChanges else { return .unknown }
            let upserted = (details.insertedObjects + details.changedObjects).map(Self.asset(from:))
            return .assets(upserted: upserted, removed: details.removedObjects.map(\.localIdentifier))
        }
        if let change { handler(change) }
    }

    private static func asset(from asset: PHAsset) -> LibraryAsset {
        LibraryAsset(localIdentifier: asset.localIdentifier,
                     creationDate: asset.creationDate,
                     modificationDate: asset.modificationDate,
                     pixelWidth: asset.pixelWidth,
                     pixelHeight: asset.pixelHeight)
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

    private let batchDelay: TimeInterval
    /// Generated once, so every fetch sees the same library.
    private let assets: [LibraryAsset]

    /// - Parameter batchDelay: pause per 500-asset batch while reading.
    init(openDelay: TimeInterval, assetCount: Int = 2_000, batchDelay: TimeInterval = 0) {
        self.openDelay = openDelay
        self.assetCount = assetCount
        self.batchDelay = batchDelay
        // Spread over the last three years, so every year window has some.
        let now = Date()
        assets = (0..<assetCount).map { i in
            let date = now.addingTimeInterval(-Double(i) * 3 * 365 * 86_400 / Double(assetCount))
            return LibraryAsset(localIdentifier: "fake-\(i)", creationDate: date, modificationDate: date,
                                pixelWidth: 4032, pixelHeight: 3024)
        }
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
    func startObservingChanges(_ handler: @escaping @Sendable (LibraryChange) -> Void) async -> LibraryObservation? {
        waitForOpen()
        return nil
    }

    @concurrent
    func openImageAssets() async throws -> any LibraryAssetList {
        waitForOpen()
        return SlowList(assets: assets, perBatchDelay: batchDelay)
    }

    /// Reads batches slowly, so progress is visible while testing.
    private struct SlowList: LibraryAssetList {
        let assets: [LibraryAsset]
        let perBatchDelay: TimeInterval
        var count: Int { assets.count }

        @concurrent
        func assets(in range: Range<Int>) async throws -> [LibraryAsset] {
            if perBatchDelay > 0 { try await Task.sleep(for: .seconds(perBatchDelay)) }
            return Array(assets[range])
        }
    }

    @concurrent
    func originalFileNames(for localIdentifiers: [String]) async -> [String: String] {
        waitForOpen()
        return [:]
    }
}
#endif

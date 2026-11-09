import Foundation
import Observation
import OSLog
import YearAgoCore

private let logger = Logger(subsystem: "YearAgoPhotoViewer", category: "viewer")

/// State for the main window: the folder, settings, the year on screen,
/// and the position within that year's photos.
@MainActor
@Observable
final class ViewerModel {
    enum Phase: Equatable {
        case noFolder
        /// First index of a folder: nothing to show yet.
        case scanning
        case ready
        case failed(String)
    }

    /// Longest side, in pixels, for decoding the on-screen photo.
    static let displayPixelSize = 3000
    /// Longest side, in pixels, for filmstrip thumbnails.
    static let thumbnailPixelSize = 160

    // MARK: Settings (persisted)

    /// Window length W, 1–6 weeks.
    var weeks: Int {
        didSet {
            guard weeks != oldValue else { return }
            settings.weeks = weeks
            rebuildNavigator(preferredYear: yearsAgo)
        }
    }

    /// Whether years with no photos in the window are offered.
    var showEmptyYears: Bool {
        didSet {
            guard showEmptyYears != oldValue else { return }
            settings.showEmptyYears = showEmptyYears
            rebuildNavigator(preferredYear: yearsAgo)
        }
    }

    /// Where photo dates come from. The index stores every date kind, so
    /// changing it needs no rescan.
    var dateSource: DateSourceKind {
        didSet {
            guard dateSource != oldValue else { return }
            settings.dateSource = dateSource
            guard let sourceID else { return }
            let dateSource = dateSource
            Task {
                do {
                    try await index.setDateSource(dateSource, forSource: sourceID)
                    try await reloadTimeline(preferredYear: yearsAgo, keepPosition: false)
                } catch {
                    logger.error("Changing date source failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: State

    private(set) var phase: Phase = .noFolder
    private(set) var folderURL: URL?
    /// N: the year on screen.
    private(set) var yearsAgo = 1
    private(set) var window: DateWindow
    private(set) var navigator = YearNavigator(photoCounts: [], showEmptyYears: true)
    /// Photos in the current window, in date order.
    private(set) var photos: [PhotoItem] = []
    private(set) var stepper = PhotoStepper(count: 0)
    /// Non-nil while the folder is being synced with the index.
    private(set) var scanProgress: ScanProgress?
    /// Drives the folder picker. The menu command and toolbar both set it.
    var isChoosingFolder = false

    let imageLoader = ImageLoader()
    let thumbnailLoader = ImageLoader(countLimit: 400)

    private let settings = SettingsStore()
    private let access = FolderAccess()
    private let calculator = WindowCalculator()
    private let index: PhotoIndex
    private let today: LocalDateTime
    private var sourceID: Int64?
    private var timeline = PhotoTimeline.empty
    private var openTask: Task<Void, Never>?
    private var watcher: FolderWatcher?
    private var isSyncing = false
    private var needsResync = false
    /// Increments per sync, so late progress updates from an old sync are ignored.
    private var syncGeneration = 0

    init() {
        today = Self.launchToday()
        weeks = settings.weeks
        showEmptyYears = settings.showEmptyYears
        dateSource = settings.dateSource
        window = calculator.window(today: today, yearsAgo: 1, weeks: settings.weeks)

        let debugFolder = Self.debugFolder()
        index = Self.openIndex(debug: debugFolder != nil)
        if let url = debugFolder ?? access.restore() {
            open(url, preferredYear: nil)
        }
    }

    // MARK: Derived values

    var folderName: String? { folderURL?.lastPathComponent }

    var currentPhoto: PhotoItem? {
        stepper.currentIndex.map { photos[$0] }
    }

    /// The calendar year shown, e.g. 2025 for "1 year ago" in 2026.
    var displayedYear: Int { calendarYear(yearsAgo: yearsAgo) }

    /// The calendar year of N's anniversary date.
    func calendarYear(yearsAgo: Int) -> Int {
        calculator.anniversary(of: today, yearsAgo: yearsAgo).components.year ?? 0
    }

    var nextYear: Int? { navigator.next(after: yearsAgo) }
    var previousYear: Int? { navigator.previous(before: yearsAgo) }

    // MARK: Actions

    func chooseFolder(_ url: URL) {
        do {
            open(try access.adopt(url), preferredYear: nil)
        } catch {
            phase = .failed("Couldn't open “\(url.lastPathComponent)”: \(error.localizedDescription)")
        }
    }

    func nextPhoto() {
        stepper.next()
        prefetch()
    }

    func previousPhoto() {
        stepper.previous()
    }

    func jump(to index: Int) {
        stepper.jump(to: index)
        prefetch()
    }

    func goToNextYear() {
        if let nextYear { goToYear(nextYear) }
    }

    func goToPreviousYear() {
        if let previousYear { goToYear(previousYear) }
    }

    /// Opens year N at its first photo. Ignores years that are not offered.
    func goToYear(_ yearsAgo: Int) {
        guard navigator.years.contains(yearsAgo) else { return }
        self.yearsAgo = yearsAgo
        applyWindow()
    }

    // MARK: Opening and syncing

    /// Shows what the index already knows about `url` at once, then syncs
    /// it with the disk and starts watching it for changes.
    private func open(_ url: URL, preferredYear: Int?) {
        openTask?.cancel()
        watcher = nil
        folderURL = url
        sourceID = nil
        phase = .scanning
        openTask = Task {
            do {
                let source = try await index.folderSource(
                    rootPath: FolderScanner.realPath(url.path),
                    name: url.lastPathComponent, defaultDateSource: dateSource)
                // One folder at a time until M5 adds multiple sources.
                try await index.removeSources(except: source.id)
                if source.dateSource != dateSource {
                    try await index.setDateSource(dateSource, forSource: source.id)
                }
                guard !Task.isCancelled else { return }
                sourceID = source.id
                try await reloadTimeline(preferredYear: preferredYear, keepPosition: false)
                if try await index.fileCount(sourceID: source.id) > 0 {
                    phase = .ready
                }
                startWatching(url)
                await sync()
            } catch {
                phase = .failed("Couldn't index “\(url.lastPathComponent)”: \(error.localizedDescription)")
            }
        }
    }

    /// Resyncs whenever anything under `url` changes.
    private func startWatching(_ url: URL) {
        watcher = FolderWatcher(url: url) { [weak self] in
            Task { @MainActor in await self?.sync() }
        }
    }

    /// Syncs the current folder with the index, then reloads. Calls made
    /// while a sync runs are folded into one follow-up sync.
    private func sync() async {
        guard sourceID != nil else { return }
        guard !isSyncing else {
            needsResync = true
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            scanProgress = nil
        }

        repeat {
            needsResync = false
            guard let sourceID, let folderURL else { return }
            syncGeneration += 1
            let generation = syncGeneration
            let start = ContinuousClock.now
            do {
                let result = try await index.sync(sourceID: sourceID, root: folderURL) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.isSyncing, self.syncGeneration == generation else { return }
                        self.scanProgress = progress
                    }
                }
                logger.info("Sync done in \((ContinuousClock.now - start).description, privacy: .public): \(result.scanned, privacy: .public) files, \(result.read, privacy: .public) read, \(result.removed, privacy: .public) removed")
                guard !Task.isCancelled, sourceID == self.sourceID else { return }
                let isFirstLoad = phase == .scanning
                try await reloadTimeline(preferredYear: isFirstLoad ? nil : yearsAgo, keepPosition: !isFirstLoad)
                phase = .ready
                logger.info("Years offered \(self.navigator.years.description, privacy: .public); counts \(self.navigator.photoCounts.description, privacy: .public)")
            } catch {
                logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        } while needsResync
    }

    /// Reloads photos from the index and rebuilds the year list.
    /// - Parameter keepPosition: stay on the same photo (or end card) if it
    ///   is still in the window.
    private func reloadTimeline(preferredYear: Int?, keepPosition: Bool) async throws {
        guard let sourceID, let folderURL else { return }
        let currentID = currentPhoto?.id
        let wasAtEnd = stepper.isAtEnd
        timeline = try await index.loadTimeline(roots: [sourceID: folderURL])
        rebuildNavigator(preferredYear: preferredYear)
        guard keepPosition else { return }
        if wasAtEnd {
            stepper.moveToEnd()
        } else if let currentID, let position = photos.firstIndex(where: { $0.id == currentID }) {
            stepper.jump(to: position)
        }
    }

    private func rebuildNavigator(preferredYear: Int?) {
        navigator = YearNavigator.build(timeline: timeline, today: today, weeks: weeks,
                                        showEmptyYears: showEmptyYears, calculator: calculator)
        yearsAgo = preferredYear.map { navigator.nearest(to: $0) } ?? navigator.initialYear
        applyWindow()
    }

    private func applyWindow() {
        window = calculator.window(today: today, yearsAgo: yearsAgo, weeks: weeks)
        photos = timeline.photos(in: window.range)
        stepper = PhotoStepper(count: photos.count)
        prefetch()
    }

    /// Decodes the next two photos ahead of time so stepping feels instant.
    private func prefetch() {
        let start = stepper.position + 1
        let upcoming = photos.indices.filter { $0 >= start && $0 < start + 2 }.map { photos[$0].url }
        guard !upcoming.isEmpty else { return }
        let loader = imageLoader
        Task {
            for url in upcoming {
                _ = await loader.image(at: url, maxPixelSize: Self.displayPixelSize)
            }
        }
    }

    // MARK: Launch values

    /// Opens the index in Application Support, or an in-memory index if
    /// that fails. Debug-folder runs use a separate index in temp.
    private static func openIndex(debug: Bool) -> PhotoIndex {
        do {
            let folder = debug
                ? FileManager.default.temporaryDirectory.appendingPathComponent("YearAgoPhotoViewer-debug")
                : try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
                    .appendingPathComponent("YearAgoPhotoViewer")
            return try PhotoIndex(fileURL: folder.appendingPathComponent("Index.sqlite"))
        } catch {
            logger.error("Opening the index failed, using memory: \(error.localizedDescription, privacy: .public)")
            // An in-memory database cannot fail to open in practice.
            return try! PhotoIndex(fileURL: nil)
        }
    }

    private static func launchToday() -> LocalDateTime {
        #if DEBUG
        // e.g. -DebugToday 2026-11-08, for repeatable screenshots.
        if let text = UserDefaults.standard.string(forKey: "DebugToday"),
           let parsed = DebugDayParser.day(text) {
            return parsed
        }
        #endif
        return LocalDateTime(Date(), in: .current)
    }

    private static func debugFolder() -> URL? {
        #if DEBUG
        // e.g. -DebugFolderPath <path>. The sandbox only allows paths
        // inside the app's container, so this is for development only.
        if let path = UserDefaults.standard.string(forKey: "DebugFolderPath") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return nil
    }
}

#if DEBUG
/// Parses "yyyy-MM-dd" for the DebugToday launch argument.
private enum DebugDayParser {
    static func day(_ text: String) -> LocalDateTime? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return LocalDateTime(year: parts[0], month: parts[1], day: parts[2])
    }
}
#endif

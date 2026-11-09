import AppKit
import Foundation
import Observation
import OSLog
import YearAgoCore

private let logger = Logger(subsystem: "YearAgoPhotoViewer", category: "viewer")

/// State for the main window: photo sources, settings, the year on screen,
/// and the position within that year's photos.
@MainActor
@Observable
final class ViewerModel {
    enum Phase: Equatable {
        /// Reading the index at launch.
        case loading
        /// No sources yet: show the welcome screen.
        case noSources
        /// First index: sources exist but nothing is indexed yet.
        case scanning
        case ready
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

    /// The date setting given to newly added sources.
    var defaultDateSource: DateSourceKind {
        didSet { settings.defaultDateSource = defaultDateSource }
    }

    /// Whether the "On This Day" item appears in the menu bar.
    var showMenuBarItem: Bool {
        didSet { settings.showMenuBarItem = showMenuBarItem }
    }

    // MARK: On This Day (menu bar)

    /// The viewer's initial year (1 year ago, or the nearest year with
    /// photos when empty years are hidden) and its photos.
    private(set) var onThisDay: OnThisDay?
    /// The photo the menu bar shows, an index into `onThisDay.photos`.
    private(set) var onThisDayIndex = 0

    var onThisDayPhoto: PhotoItem? {
        guard let photos = onThisDay?.photos, photos.indices.contains(onThisDayIndex) else { return nil }
        return photos[onThisDayIndex]
    }

    /// Shows a different random photo from the same window.
    func shuffleOnThisDay() {
        guard let count = onThisDay?.photos.count, count > 1 else { return }
        var next = onThisDayIndex
        while next == onThisDayIndex {
            next = Int.random(in: 0..<count)
        }
        onThisDayIndex = next
    }

    /// Moves the main viewer to the menu bar's photo.
    func showOnThisDayInViewer() {
        guard let onThisDay else { return }
        goToYear(onThisDay.yearsAgo)
        if let photo = onThisDayPhoto, let index = photos.firstIndex(where: { $0.id == photo.id }) {
            jump(to: index)
        }
    }

    private func refreshOnThisDay() {
        let updated = OnThisDay.years(count: 1, timeline: timeline, navigator: navigator, today: today,
                                      weeks: weeks, calculator: calculator).first
        guard updated != onThisDay else { return }
        let keptID = onThisDayPhoto?.id
        onThisDay = updated
        let photos = updated?.photos ?? []
        onThisDayIndex = photos.firstIndex { $0.id == keptID }
            ?? (photos.isEmpty ? 0 : Int.random(in: 0..<photos.count))
    }

    // MARK: State

    /// Every source, in the user's order.
    private(set) var sources: [SourceRecord] = []
    private(set) var sourceStats: [Int64: SourceStats] = [:]
    /// N: the year on screen.
    private(set) var yearsAgo = 1
    private(set) var window: DateWindow
    private(set) var navigator = YearNavigator(photoCounts: [], showEmptyYears: true)
    /// Photos in the current window, in date order.
    private(set) var photos: [PhotoItem] = []
    private(set) var stepper = PhotoStepper(count: 0)
    /// The source being synced, and its progress.
    private(set) var syncingSourceID: Int64?
    private(set) var scanProgress: ScanProgress?
    /// A problem to show the user, e.g. a folder that could not be added.
    var errorMessage: String?
    /// Drives the folder picker (toolbar, menu, welcome screen).
    var isAddingFolder = false
    /// Drives the Sources panel.
    var isShowingSources = false

    /// Full-size images and filmstrip thumbnails, from files or Photos.
    let images = ImageRepository(countLimit: 48)
    let thumbnails = ImageRepository(countLimit: 400)

    private let settings = SettingsStore()
    private let access = FolderAccess()
    private let calculator = WindowCalculator()
    private let index: PhotoIndex
    /// Today's date. Updated at midnight while the app runs.
    private var today: LocalDateTime
    private let debugFolders: [URL]
    private var timeline = PhotoTimeline.empty
    /// Root URLs of reachable folder sources, by source ID.
    private var roots: [Int64: URL] = [:]
    private var watchers: [Int64: FolderWatcher] = [:]
    private var syncQueue: [Int64] = []
    private var isSyncing = false
    /// Increments per sync, so late progress updates from an old sync are ignored.
    private var syncGeneration = 0
    private var volumeObservers: [NSObjectProtocol] = []
    private let photoLibrary = PhotoKitLibrary()
    private var libraryObserver: LibraryChangeObserver?
    private var librarySyncDelay: Task<Void, Never>?
    /// False until the index has been read once at launch.
    private var hasLoaded = false

    init() {
        let launchDay = Self.launchToday()
        today = launchDay
        weeks = settings.weeks
        showEmptyYears = settings.showEmptyYears
        defaultDateSource = settings.defaultDateSource
        showMenuBarItem = settings.showMenuBarItem
        window = WindowCalculator().window(today: launchDay, yearsAgo: 1, weeks: SettingsStore().weeks)
        debugFolders = Self.debugFolderArguments()
        index = Self.openIndex(debug: !debugFolders.isEmpty)
        observeVolumes()
        observeDayChange()
        Task { await start() }
    }

    // MARK: Derived values

    var phase: Phase {
        if !hasLoaded { return .loading }
        if sources.isEmpty { return .noSources }
        let indexedFiles = sourceStats.values.reduce(0) { $0 + $1.files }
        return indexedFiles == 0 && isSyncing ? .scanning : .ready
    }

    var currentPhoto: PhotoItem? {
        stepper.currentIndex.map { photos[$0] }
    }

    var enabledSourceCount: Int { sources.filter(\.isEnabled).count }

    func source(id: Int64) -> SourceRecord? {
        sources.first { $0.id == id }
    }

    /// The calendar year shown, e.g. 2025 for "1 year ago" in 2026.
    var displayedYear: Int { calendarYear(yearsAgo: yearsAgo) }

    /// The calendar year of N's anniversary date.
    func calendarYear(yearsAgo: Int) -> Int {
        calculator.anniversary(of: today, yearsAgo: yearsAgo).components.year ?? 0
    }

    var nextYear: Int? { navigator.next(after: yearsAgo) }
    var previousYear: Int? { navigator.previous(before: yearsAgo) }

    // MARK: Photo and year navigation

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

    // MARK: Source actions

    /// Adds folders the user picked. A folder that is already a source is
    /// reconnected rather than added twice.
    func addFolders(_ urls: [URL]) {
        Task {
            var added: [Int64] = []
            for url in urls {
                do {
                    let bookmark = try access.bookmarkForPickedFolder(url)
                    let source = try await index.addFolderSource(
                        rootPath: FolderScanner.realPath(url.path), name: url.lastPathComponent,
                        bookmark: bookmark, dateSource: defaultDateSource)
                    access.track(url, for: source.id)
                    connect(source.id, to: url)
                    try await index.setOnline(true, forSource: source.id)
                    added.append(source.id)
                } catch {
                    errorMessage = "Couldn't add “\(url.lastPathComponent)”: \(error.localizedDescription)"
                }
            }
            await refresh(keepPosition: true)
            enqueueSync(added)
        }
    }

    func removeSource(_ id: Int64) {
        disconnect(id)
        access.stop(id)
        perform { try await $0.removeSource(id) }
    }

    func renameSource(_ id: Int64, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != source(id: id)?.name else { return }
        perform { try await $0.renameSource(id, to: trimmed) }
    }

    func setEnabled(_ isEnabled: Bool, forSource id: Int64) {
        perform { try await $0.setEnabled(isEnabled, forSource: id) }
        if isEnabled { enqueueSync([id]) }
    }

    func setDateSource(_ dateSource: DateSourceKind, forSource id: Int64) {
        perform { try await $0.setDateSource(dateSource, forSource: id) }
        // Library file names are fetched only when needed: resync to get them.
        if dateSource == .fileName, source(id: id)?.kind == .photos {
            enqueueSync([id])
        }
    }

    /// Gives every source the default date setting.
    func applyDefaultDateSourceToAll() {
        let dateSource = defaultDateSource
        perform { try await $0.setDateSourceForAll(dateSource) }
        if dateSource == .fileName {
            enqueueSync(sources.filter { $0.kind == .photos }.map(\.id))
        }
    }

    /// True once the Photos library is a source (it can be added once).
    var hasPhotosLibrary: Bool { sources.contains { $0.kind == .photos } }

    /// True when no source can show photos: none enabled, or all offline.
    var hasNoActiveSource: Bool {
        !sources.isEmpty && !sources.contains { $0.isEnabled && $0.isOnline }
    }

    /// "Show in Finder" for files, "Open Photos" for library items.
    var revealTitle: String {
        currentPhoto?.isLibraryAsset == true ? "Open Photos" : "Show in Finder"
    }

    /// Reveals the current photo: selects the file in Finder, or opens the
    /// Photos app for library items (PhotoKit cannot select an asset there).
    func revealCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        if photo.isLibraryAsset {
            if let photosApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
                NSWorkspace.shared.openApplication(at: photosApp, configuration: NSWorkspace.OpenConfiguration())
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([photo.url])
        }
    }

    /// Asks for Photos access, then adds the library as a source.
    func addPhotosLibrary() {
        Task {
            guard await PhotoKitLibrary.requestAccess() else {
                errorMessage = "\(CoreInfo.appName) doesn't have access to Photos. Turn it on in System Settings › Privacy & Security › Photos."
                return
            }
            do {
                let source = try await index.addPhotosLibrarySource(name: "Photos Library",
                                                                    dateSource: defaultDateSource)
                try await index.setOnline(true, forSource: source.id)
                observeLibrary(source.id)
                await refresh(keepPosition: true)
                enqueueSync([source.id])
            } catch {
                errorMessage = "Couldn't add the Photos library: \(error.localizedDescription)"
            }
        }
    }

    /// Reorders sources, as List's onMove reports it.
    func moveSources(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var ids = sources.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        sources.move(fromOffsets: offsets, toOffset: destination)
        let order = ids
        perform { try await $0.reorderSources(order) }
    }

    /// Runs an index change, then reloads sources and photos.
    private func perform(_ change: @escaping @Sendable (PhotoIndex) async throws -> Void) {
        let index = index
        Task {
            do {
                try await change(index)
            } catch {
                errorMessage = error.localizedDescription
            }
            await refresh(keepPosition: true)
        }
    }

    // MARK: Startup and connections

    private func start() async {
        await migrateLegacyBookmark()
        for debugFolder in debugFolders {
            _ = try? await index.addFolderSource(rootPath: FolderScanner.realPath(debugFolder.path),
                                                 name: debugFolder.lastPathComponent, bookmark: nil,
                                                 dateSource: defaultDateSource)
        }
        await refresh(keepPosition: false)
        for source in sources {
            await reconnect(source)
        }
        await refresh(keepPosition: false)
        enqueueSync(sources.map(\.id))
        hasLoaded = true
        #if DEBUG
        // -DebugShowSources YES opens the Sources panel, for screenshots.
        if UserDefaults.standard.bool(forKey: "DebugShowSources") {
            isShowingSources = true
        }
        #endif
    }

    /// Marks a source online or offline. Folders: resolves the bookmark.
    /// The Photos library: checks access, and watches for changes.
    private func reconnect(_ source: SourceRecord) async {
        if source.kind == .photos {
            let authorized = PhotoKitLibrary.isAuthorized
            if authorized {
                observeLibrary(source.id)
            } else {
                libraryObserver = nil
            }
            try? await index.setOnline(authorized, forSource: source.id)
            return
        }
        var url: URL?
        if let debugFolder = debugFolders.first(where: { source.rootPath == FolderScanner.realPath($0.path) }) {
            url = debugFolder
        } else if let bookmark = source.bookmark, let opened = access.open(bookmark: bookmark, for: source.id) {
            url = opened.url
            if let refreshed = opened.refreshed {
                try? await index.setBookmark(refreshed, forSource: source.id)
            }
        }
        let reachable = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if let url, reachable {
            connect(source.id, to: url)
        } else {
            disconnect(source.id)
        }
        try? await index.setOnline(reachable, forSource: source.id)
    }

    private func connect(_ id: Int64, to url: URL) {
        roots[id] = url
        watchers[id] = makeWatcher(id, url)
    }

    private func disconnect(_ id: Int64) {
        roots[id] = nil
        watchers[id] = nil
    }

    private func makeWatcher(_ id: Int64, _ url: URL) -> FolderWatcher {
        FolderWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.enqueueSync([id]) }
        }
    }

    /// Resyncs the library 5 seconds after it stops changing. Photos reports
    /// many small changes, e.g. during iCloud syncing.
    private func observeLibrary(_ id: Int64) {
        guard libraryObserver == nil else { return }
        libraryObserver = LibraryChangeObserver { [weak self] in
            Task { @MainActor in self?.scheduleLibrarySync(id) }
        }
    }

    private func scheduleLibrarySync(_ id: Int64) {
        librarySyncDelay?.cancel()
        librarySyncDelay = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            enqueueSync([id])
        }
    }

    /// Re-checks every folder source when a drive is mounted or unmounted.
    /// At midnight, moves every window forward a day, keeping the year.
    private func observeDayChange() {
        volumeObservers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dayDidChange() }
        })
    }

    private func dayDidChange() {
        let newToday = Self.launchToday()
        guard newToday.startOfDay != today.startOfDay else { return }
        today = newToday
        rebuildNavigator(preferredYear: yearsAgo)
        logger.info("Day changed; windows moved forward")
    }

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshAvailability() }
            })
        }
    }

    private func refreshAvailability() async {
        let wasOnline = Set(sources.filter(\.isOnline).map(\.id))
        for source in sources where source.kind == .folder {
            await reconnect(source)
        }
        await refresh(keepPosition: true)
        let cameBack = sources.filter { $0.isOnline && !wasOnline.contains($0.id) }.map(\.id)
        enqueueSync(cameBack)
    }

    /// Moves the pre-M5 single-folder bookmark onto its source row.
    private func migrateLegacyBookmark() async {
        guard let bookmark = access.takeLegacyBookmark() else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale)
        else { return }
        _ = try? await index.addFolderSource(rootPath: FolderScanner.realPath(url.path),
                                             name: url.lastPathComponent, bookmark: bookmark,
                                             dateSource: defaultDateSource)
    }

    // MARK: Syncing

    /// Queues sources for syncing. Syncs run one at a time.
    private func enqueueSync(_ ids: [Int64]) {
        for id in ids where !syncQueue.contains(id) {
            syncQueue.append(id)
        }
        guard !isSyncing, !syncQueue.isEmpty else { return }
        isSyncing = true
        Task { await runSyncQueue() }
    }

    private func runSyncQueue() async {
        defer {
            isSyncing = false
            syncingSourceID = nil
            scanProgress = nil
        }
        while !syncQueue.isEmpty {
            let id = syncQueue.removeFirst()
            guard let source = source(id: id), source.isEnabled else { continue }
            let root = roots[id]
            if source.kind == .folder, root == nil { continue }
            if source.kind == .photos, !PhotoKitLibrary.isAuthorized {
                try? await index.setOnline(false, forSource: id)
                continue
            }
            syncingSourceID = id
            scanProgress = nil
            syncGeneration += 1
            let generation = syncGeneration
            let start = ContinuousClock.now
            let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.syncGeneration == generation, self.syncingSourceID == id else { return }
                    self.scanProgress = progress
                }
            }
            do {
                let result = if let root {
                    try await index.sync(sourceID: id, root: root, onProgress: onProgress)
                } else {
                    try await index.syncLibrary(sourceID: id, library: photoLibrary, onProgress: onProgress)
                }
                logger.info("Sync of source \(id, privacy: .public) done in \((ContinuousClock.now - start).description, privacy: .public): \(result.scanned, privacy: .public) files, \(result.read, privacy: .public) read, \(result.removed, privacy: .public) removed")
            } catch PhotoIndexError.rootUnavailable {
                logger.info("Source \(id, privacy: .public) is offline")
                disconnect(id)
                try? await index.setOnline(false, forSource: id)
            } catch {
                logger.error("Sync of source \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            syncingSourceID = nil
            await refresh(keepPosition: true)
        }
        await findDuplicates()
        logger.info("Years offered \(self.navigator.years.description, privacy: .public); counts \(self.navigator.photoCounts.description, privacy: .public)")
    }

    /// Hashes same-size files across all reachable sources and hides
    /// duplicates. Runs after each round of syncs.
    private func findDuplicates() async {
        syncGeneration += 1
        let generation = syncGeneration
        let start = ContinuousClock.now
        do {
            let hashed = try await index.findDuplicates(roots: roots) { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.syncGeneration == generation, self.isSyncing else { return }
                    self.scanProgress = progress
                }
            }
            if hashed > 0 {
                logger.info("Duplicate check hashed \(hashed, privacy: .public) files in \((ContinuousClock.now - start).description, privacy: .public)")
            }
        } catch {
            logger.error("Duplicate check failed: \(error.localizedDescription, privacy: .public)")
        }
        scanProgress = nil
        await refresh(keepPosition: true)
    }

    // MARK: Reloading

    /// Reloads sources, counts, and photos from the index.
    /// - Parameter keepPosition: stay on the same year and photo (or end
    ///   card) if possible. The first time photos appear, the viewer opens
    ///   at the initial year instead.
    private func refresh(keepPosition: Bool) async {
        do {
            sources = try await index.sources()
            sourceStats = try await index.sourceStats()
            let hadPhotos = !timeline.photos.isEmpty
            let currentID = currentPhoto?.id
            let wasAtEnd = stepper.isAtEnd
            timeline = try await index.loadTimeline(roots: roots)
            let keep = keepPosition && hadPhotos
            rebuildNavigator(preferredYear: keep ? yearsAgo : nil)
            guard keep else { return }
            if wasAtEnd {
                stepper.moveToEnd()
            } else if let currentID, let position = photos.firstIndex(where: { $0.id == currentID }) {
                stepper.jump(to: position)
            }
        } catch {
            logger.error("Reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rebuildNavigator(preferredYear: Int?) {
        navigator = YearNavigator.build(timeline: timeline, today: today, weeks: weeks,
                                        showEmptyYears: showEmptyYears, calculator: calculator)
        yearsAgo = preferredYear.map { navigator.nearest(to: $0) } ?? navigator.initialYear
        applyWindow()
        refreshOnThisDay()
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
        let upcoming = photos.indices.filter { $0 >= start && $0 < start + 2 }.map { photos[$0] }
        guard !upcoming.isEmpty else { return }
        let images = images
        Task {
            for photo in upcoming {
                _ = await images.image(for: photo, maxPixelSize: Self.displayPixelSize)
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

    private static func debugFolderArguments() -> [URL] {
        #if DEBUG
        // e.g. -DebugFolderPath <path>[:<path>…]. Adds those folders as
        // sources in a separate temp index. The sandbox only allows paths
        // inside the app's container, so this is for development only.
        if let paths = UserDefaults.standard.string(forKey: "DebugFolderPath") {
            return paths.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) }
        }
        #endif
        return []
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

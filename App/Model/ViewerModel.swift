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

    /// Where photo dates come from. Changing it rescans the folder.
    var dateSource: DateSourceKind {
        didSet {
            guard dateSource != oldValue else { return }
            settings.dateSource = dateSource
            if let folderURL { load(folderURL, preferredYear: yearsAgo) }
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
    /// Drives the folder picker. The menu command and toolbar both set it.
    var isChoosingFolder = false

    let imageLoader = ImageLoader()
    let thumbnailLoader = ImageLoader(countLimit: 400)

    private let settings = SettingsStore()
    private let access = FolderAccess()
    private let calculator = WindowCalculator()
    private let today: LocalDateTime
    private var timeline = PhotoTimeline.empty
    private var loadTask: Task<Void, Never>?

    init() {
        today = Self.launchToday()
        weeks = settings.weeks
        showEmptyYears = settings.showEmptyYears
        dateSource = settings.dateSource
        window = calculator.window(today: today, yearsAgo: 1, weeks: settings.weeks)
        if let url = Self.debugFolder() ?? access.restore() {
            load(url, preferredYear: nil)
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
            load(try access.adopt(url), preferredYear: nil)
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

    // MARK: Loading

    /// Scans `url`. Afterwards opens `preferredYear` (or the nearest offered
    /// year), or the initial year when nil.
    private func load(_ url: URL, preferredYear: Int?) {
        folderURL = url
        phase = .scanning
        loadTask?.cancel()
        let source = dateSource
        loadTask = Task {
            let timeline = await FolderPhotoLoader.load(folder: url, dateSource: source)
            guard !Task.isCancelled else { return }
            self.timeline = timeline
            rebuildNavigator(preferredYear: preferredYear)
            phase = .ready
            // Counts and dates only: never log paths or file names.
            logger.info("Scan done: \(timeline.photos.count, privacy: .public) dated photos; years offered \(self.navigator.years.description, privacy: .public); counts \(self.navigator.photoCounts.description, privacy: .public)")
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

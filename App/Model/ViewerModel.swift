import Foundation
import Observation
import OSLog
import YearAgoCore

private let logger = Logger(subsystem: "YearAgoPhotoViewer", category: "viewer")

/// State for the main window: the folder, the current year's photos, and
/// the position within them.
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

    private(set) var phase: Phase = .noFolder
    private(set) var folderURL: URL?
    private(set) var window: DateWindow
    /// Photos in the current window, in date order.
    private(set) var photos: [PhotoItem] = []
    private(set) var stepper = PhotoStepper(count: 0)
    /// Drives the folder picker. The menu command and toolbar both set it.
    var isChoosingFolder = false

    let imageLoader = ImageLoader()

    private let access = FolderAccess()
    private let calculator = WindowCalculator()
    private var timeline = PhotoTimeline.empty
    private var loadTask: Task<Void, Never>?

    // M3 makes these adjustable.
    private let today: LocalDateTime
    private let yearsAgo = 1
    private let weeks = 1
    private let dateSource: DateSourceKind = .exif

    init() {
        today = Self.launchToday()
        window = calculator.window(today: today, yearsAgo: yearsAgo, weeks: weeks)
        if let url = Self.debugFolder() ?? access.restore() {
            load(url)
        }
    }

    var folderName: String? { folderURL?.lastPathComponent }

    var currentPhoto: PhotoItem? {
        stepper.currentIndex.map { photos[$0] }
    }

    /// The year shown, e.g. 2025 for "1 year ago" in 2026.
    var displayedYear: Int {
        window.range.upperBound.components.year ?? 0
    }

    func chooseFolder(_ url: URL) {
        do {
            load(try access.adopt(url))
        } catch {
            phase = .failed("Couldn't open “\(url.lastPathComponent)”: \(error.localizedDescription)")
        }
    }

    func next() {
        stepper.next()
        prefetch()
    }

    func previous() {
        stepper.previous()
    }

    // MARK: - Loading

    private func load(_ url: URL) {
        folderURL = url
        phase = .scanning
        loadTask?.cancel()
        loadTask = Task {
            let timeline = await FolderPhotoLoader.load(folder: url, dateSource: dateSource)
            guard !Task.isCancelled else { return }
            self.timeline = timeline
            applyWindow()
            phase = .ready
            // Counts and dates only: never log paths or file names.
            logger.info("Scan done: \(timeline.photos.count, privacy: .public) dated photos, \(self.photos.count, privacy: .public) in window \(self.window.range.lowerBound.description, privacy: .public) – \(self.window.range.upperBound.description, privacy: .public)")
        }
    }

    private func applyWindow() {
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

    // MARK: - Launch values

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

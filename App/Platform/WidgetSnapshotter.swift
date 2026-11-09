import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers
import WidgetKit
import YearAgoCore
import YearAgoSnapshot

private let logger = Logger(subsystem: "YearAgoPhotoViewer", category: "widget")

/// Writes the widget's snapshot: a JSON manifest and small JPEG thumbnails
/// in the shared App Group folder. The widget reads only these files.
@MainActor
final class WidgetSnapshotter {
    /// Photos kept per year; the large widget shows six.
    static let photosPerYear = 6
    /// Years kept; the medium widget shows three.
    static let years = 3
    /// Longest side of each thumbnail.
    static let thumbnailPixelSize = 600

    private let folder: URL?
    private let images: ImageRepository
    private var lastWritten: WidgetSnapshot?
    private var pending: Task<Void, Never>?

    /// - Parameter folder: where to write; defaults to the App Group folder.
    ///   Nil disables the snapshotter (no App Group, e.g. ad hoc builds).
    init(folder: URL? = SharedContainer.widgetFolder, images: ImageRepository) {
        self.folder = folder
        self.images = images
        lastWritten = folder.flatMap(WidgetSnapshot.read(from:))
        if folder == nil {
            logger.info("No App Group: widget snapshots are off")
        }
    }

    /// Schedules a snapshot after a short pause, so bursts of changes write once.
    func update(days: [OnThisDay], hasSources: Bool, today: LocalDateTime) {
        guard folder != nil else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await write(days: days, hasSources: hasSources, today: today)
        }
    }

    private func write(days: [OnThisDay], hasSources: Bool, today: LocalDateTime) async {
        guard let folder else { return }
        var chosen: [(year: WidgetSnapshot.Year, photos: [PhotoItem])] = []
        for day in days.prefix(Self.years) {
            let photos = day.spread(limit: Self.photosPerYear)
            let year = WidgetSnapshot.Year(
                yearsAgo: day.yearsAgo,
                calendarYear: day.window.range.upperBound.components.year ?? 0,
                rangeText: DisplayFormat.range(day.window),
                photoCount: day.photos.count,
                photos: photos.map { photo in
                    WidgetSnapshot.Photo(id: photo.id, imageFile: Self.imageFileName(for: photo),
                                         dateText: DisplayFormat.shortPhotoDate(photo.date))
                })
            chosen.append((year, photos))
        }
        let parts = today.components
        let snapshot = WidgetSnapshot(
            day: .init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0),
            hasSources: hasSources,
            years: chosen.map(\.year))
        guard snapshot != lastWritten else { return }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (_, photos) in chosen {
                for photo in photos {
                    let url = folder.appendingPathComponent(Self.imageFileName(for: photo))
                    guard !FileManager.default.fileExists(atPath: url.path),
                          let image = await images.image(for: photo, maxPixelSize: Self.thumbnailPixelSize)
                    else { continue }
                    try Self.writeJPEG(image, to: url)
                }
            }
            try snapshot.write(to: folder)
            removeUnusedImages(in: folder, keeping: snapshot.imageFiles)
            lastWritten = snapshot
            WidgetCenter.shared.reloadAllTimelines()
            logger.info("Widget snapshot written: \(snapshot.years.count, privacy: .public) years, \(snapshot.imageFiles.count, privacy: .public) images")
        } catch {
            logger.error("Widget snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A stable, opaque file name per photo, so unchanged photos are not
    /// re-rendered and no file names or paths leak into the shared folder.
    static func imageFileName(for photo: PhotoItem) -> String {
        let digest = SHA256.hash(data: Data(photo.id.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func removeUnusedImages(in folder: URL, keeping keep: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where file.hasSuffix(".jpg") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
}

import AppKit
import SwiftUI
import WidgetKit
import YearAgoSnapshot

/// The "On This Day" widget. It shows a snapshot the app writes into the
/// shared App Group folder; it never reads photos itself.
@main
struct YearAgoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnThisDay", provider: SnapshotProvider()) { entry in
            OnThisDayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("On This Day")
        .description("Photos you took this week in past years.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let folder: URL?

    func image(_ photo: WidgetSnapshot.Photo) -> NSImage? {
        folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent(photo.imageFile)) }
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: nil, folder: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(currentEntry(at: .now))
    }

    /// One entry now and one just after midnight, when the snapshot becomes
    /// stale. The app reloads timelines whenever it writes a new snapshot.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [currentEntry(at: now), currentEntry(at: midnight)], policy: .atEnd))
    }

    private func currentEntry(at date: Date) -> SnapshotEntry {
        let folder = SharedContainer.widgetFolder
        return SnapshotEntry(date: date, snapshot: folder.flatMap(WidgetSnapshot.read(from:)), folder: folder)
    }
}

struct OnThisDayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, snapshot.hasSources, let first = snapshot.years.first {
            switch family {
            case .systemMedium: medium(snapshot)
            case .systemLarge: large(snapshot, first)
            default: small(snapshot, first)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .font(.title)
                Text("Open Year Ago Photo Viewer to add photos.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .widgetURL(WidgetDeepLink.url(yearsAgo: 1))
        }
    }

    // MARK: Sizes

    /// One photo from the first year, filling the widget.
    private func small(_ snapshot: WidgetSnapshot, _ year: WidgetSnapshot.Year) -> some View {
        let photo = year.photos.first
        return PhotoTile(image: photo.flatMap(entry.image), emptyText: "No photos")
            .overlay(alignment: .bottomLeading) {
                Caption(title: yearsAgoText(year.yearsAgo),
                        subtitle: photo?.dateText ?? year.rangeText,
                        stale: staleText(snapshot))
            }
            .widgetURL(photo.map { WidgetDeepLink.url(photoID: $0.id, yearsAgo: year.yearsAgo) }
                       ?? WidgetDeepLink.url(yearsAgo: year.yearsAgo))
    }

    /// One photo from each of the first three years.
    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(title: "On This Day", stale: staleText(snapshot))
            HStack(spacing: 6) {
                ForEach(snapshot.years.prefix(3), id: \.yearsAgo) { year in
                    let photo = year.photos.first
                    Link(destination: photo.map { WidgetDeepLink.url(photoID: $0.id, yearsAgo: year.yearsAgo) }
                         ?? WidgetDeepLink.url(yearsAgo: year.yearsAgo)) {
                        PhotoTile(image: photo.flatMap(entry.image), emptyText: "No photos")
                            .overlay(alignment: .bottomLeading) {
                                Caption(title: String(year.calendarYear), subtitle: nil, stale: nil)
                            }
                    }
                }
            }
        }
    }

    /// A 2 × 3 grid from the first year.
    private func large(_ snapshot: WidgetSnapshot, _ year: WidgetSnapshot.Year) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(title: "\(yearsAgoText(year.yearsAgo)) · \(year.rangeText)", stale: staleText(snapshot))
            if year.photos.isEmpty {
                PhotoTile(image: nil, emptyText: "No photos from \(year.rangeText)")
            } else {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(0..<2, id: \.self) { column in
                                let index = row * 2 + column
                                if index < year.photos.count {
                                    let photo = year.photos[index]
                                    Link(destination: WidgetDeepLink.url(photoID: photo.id, yearsAgo: year.yearsAgo)) {
                                        PhotoTile(image: entry.image(photo), emptyText: "")
                                    }
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                }
            }
            Text(year.photoCount == 1 ? "1 photo" : "\(year.photoCount) photos")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .widgetURL(WidgetDeepLink.url(yearsAgo: year.yearsAgo))
    }

    // MARK: Helpers

    private func yearsAgoText(_ years: Int) -> String {
        years == 1 ? "1 year ago" : "\(years) years ago"
    }

    /// "As of Nov 8" when the snapshot is from an earlier day.
    private func staleText(_ snapshot: WidgetSnapshot) -> String? {
        guard !snapshot.isCurrent(on: entry.date), let day = snapshot.day.date() else { return nil }
        return "As of \(day.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct PhotoTile: View {
    let image: NSImage?
    let emptyText: String

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !emptyText.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: 10))
    }
}

private struct Header: View {
    let title: String
    let stale: String?

    var body: some View {
        HStack {
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            if let stale {
                Text(stale).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Caption: View {
    let title: String
    let subtitle: String?
    let stale: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.bold())
            if let subtitle {
                Text(subtitle).font(.caption2)
            }
            if let stale {
                Text(stale).font(.caption2).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 3)
        .padding(8)
    }
}

import SwiftUI
import YearAgoCore

/// The "On This Day" popover in the menu bar. See proposal section 5.2.
struct MenuBarContentView: View {
    @Environment(ViewerModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            photo
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("On This Day")
                .font(.headline)
            if let day = model.onThisDay {
                Text("\(DisplayFormat.yearsAgo(day.yearsAgo)) · \(DisplayFormat.range(day.window))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var photo: some View {
        if model.sources.isEmpty {
            placeholder("Add a photo folder to get started.", systemImage: "photo.stack")
        } else if let photo = model.onThisDayPhoto {
            VStack(alignment: .leading, spacing: 6) {
                MenuBarPhotoView(photo: photo, images: model.images)
                    .frame(width: 312, height: 220)
                    .clipShape(.rect(cornerRadius: 8))
                Text(DisplayFormat.photoDate(photo.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let day = model.onThisDay {
            placeholder("No photos from \(DisplayFormat.range(day.window)).", systemImage: "photo.on.rectangle.angled")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day = model.onThisDay, !day.photos.isEmpty {
                Text(day.photos.count == 1
                     ? "1 photo from \(DisplayFormat.range(day.window))"
                     : "\(day.photos.count) photos from \(DisplayFormat.range(day.window))")
                    .font(.callout)
                    .monospacedDigit()
            }
            HStack {
                Button("Shuffle", systemImage: "shuffle") { model.shuffleOnThisDay() }
                    .disabled((model.onThisDay?.photos.count ?? 0) < 2)
                    .help("Show another photo from the same week")
                Spacer()
                Button("Open in Viewer") {
                    model.showOnThisDayInViewer()
                    dismiss()
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(width: 312, height: 160)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

/// The popover's photo, filled and cropped to its frame.
private struct MenuBarPhotoView: View {
    let photo: PhotoItem
    let images: ImageRepository
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo from \(DisplayFormat.photoDate(photo.date))")
        .task(id: photo.id) {
            image = nil
            let loaded = await images.image(for: photo, maxPixelSize: 800)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

import SwiftUI
import YearAgoCore

/// One year's photos: header, current photo with arrows, and caption.
struct ViewerView: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                content
                arrows
            }
            Divider()
            caption
        }
    }

    private var header: some View {
        Text([
            DisplayFormat.yearsAgo(model.window.yearsAgo),
            DisplayFormat.range(model.window),
            DisplayFormat.position(model.stepper),
        ].joined(separator: " · "))
        .font(.headline)
        .monospacedDigit()
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if model.stepper.isEmpty {
            ContentUnavailableView {
                Label("No Photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("No photos from \(DisplayFormat.range(model.window)).")
            }
        } else if let photo = model.currentPhoto {
            PhotoView(photo: photo, loader: model.imageLoader)
        } else {
            ContentUnavailableView {
                Label("That's All for \(String(model.displayedYear))", systemImage: "checkmark.circle")
            } description: {
                Text("You've seen all \(DisplayFormat.position(model.stepper)) from \(DisplayFormat.range(model.window)).")
            }
        }
    }

    private var arrows: some View {
        HStack {
            Button("Previous Photo", systemImage: "chevron.left") { model.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!model.stepper.canGoBack)
            Spacer()
            Button("Next Photo", systemImage: "chevron.right") { model.next() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!model.stepper.canGoForward)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.circle)
        .padding()
    }

    private var caption: some View {
        HStack {
            if let photo = model.currentPhoto {
                Text(DisplayFormat.photoDate(photo.date))
                Spacer()
                Text(photo.fileName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(minHeight: 32)
    }
}

/// Decodes and shows one photo, scaled to fit.
struct PhotoView: View {
    let photo: PhotoItem
    let loader: ImageLoader

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                ContentUnavailableView("Can't Preview “\(photo.fileName)”",
                                       systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task(id: photo.id) {
            image = nil
            failed = false
            let decoded = await loader.image(at: photo.url, maxPixelSize: ViewerModel.displayPixelSize)
            guard !Task.isCancelled else { return }
            image = decoded
            failed = decoded == nil
        }
    }
}

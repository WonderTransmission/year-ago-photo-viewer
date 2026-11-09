import SwiftUI
import YearAgoCore

/// A strip of thumbnails for this year's photos. Click one to jump to it.
struct FilmstripView: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    // Identify thumbnails by photo, not position: a reload can
                    // shift photos to new positions.
                    ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            model.jump(to: index)
                        } label: {
                            ThumbnailView(photo: photo,
                                          images: model.thumbnails,
                                          isSelected: index == model.stepper.currentIndex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1) of \(model.photos.count)")
                        .id(index)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .frame(height: 80)
            .onChange(of: model.stepper.position) { _, position in
                guard !model.photos.isEmpty else { return }
                withAnimation {
                    proxy.scrollTo(min(position, model.photos.count - 1), anchor: .center)
                }
            }
        }
    }
}

private struct ThumbnailView: View {
    let photo: PhotoItem
    let images: ImageRepository
    let isSelected: Bool

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        }
        .opacity(isSelected ? 1 : 0.75)
        .task(id: photo.id) {
            image = nil
            let loaded = await images.image(for: photo, maxPixelSize: ViewerModel.thumbnailPixelSize)
            // A cancelled load belongs to a previous photo: drop it.
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

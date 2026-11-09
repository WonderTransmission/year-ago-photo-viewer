import SwiftUI
import YearAgoCore

/// One year's photos: year bar, current photo with arrows, caption, and
/// filmstrip.
struct ViewerView: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            YearBar()
            Divider()
            ZStack {
                content
                if !model.stepper.isEmpty {
                    photoArrows
                }
            }
            if !model.stepper.isEmpty {
                Divider()
                caption
                FilmstripView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.stepper.isEmpty {
            ContentUnavailableView {
                Label("No Photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("No photos from \(DisplayFormat.range(model.window)).")
            } actions: {
                NextYearButton()
            }
        } else if let photo = model.currentPhoto {
            PhotoView(photo: photo, images: model.images)
        } else {
            ContentUnavailableView {
                Label("That's All for \(String(model.displayedYear))", systemImage: "checkmark.circle")
            } description: {
                Text("You've seen all \(DisplayFormat.position(model.stepper)) from \(DisplayFormat.range(model.window)).")
            } actions: {
                NextYearButton()
            }
        }
    }

    private var photoArrows: some View {
        HStack {
            Button("Previous Photo", systemImage: "chevron.left") { model.previousPhoto() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!model.stepper.canGoBack)
            Spacer()
            Button("Next Photo", systemImage: "chevron.right") { model.nextPhoto() }
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
                if let source = model.source(id: photo.sourceID) {
                    Text("· \(source.name) (\(source.dateSource.displayName))")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let badge = photo.rawBadge {
                    Text(badge)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                        .help(badge == "RAW" ? "A RAW file with no JPEG or HEIC partner"
                                             : "Shown in place of its RAW file, which has the same name")
                }
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

/// "◀◀ Previous Year   2 years ago · Nov 1 – 8, 2024 · 12 of 37   [Year ▾]   Next Year ▶▶"
private struct YearBar: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Button("Previous Year", systemImage: "chevron.backward.2") { model.goToPreviousYear() }
                .disabled(model.previousYear == nil)
                .help("Previous year (⌘[)")

            Spacer(minLength: 0)
            Text([
                DisplayFormat.yearsAgo(model.yearsAgo),
                DisplayFormat.range(model.window),
                DisplayFormat.position(model.stepper),
            ].joined(separator: " · "))
            .font(.headline)
            .monospacedDigit()
            .lineLimit(1)
            Spacer(minLength: 0)

            YearPicker()
            Button { model.goToNextYear() } label: {
                Label("Next Year", systemImage: "chevron.forward.2")
                    .labelStyle(.titleAndIconTrailing)
            }
            .disabled(model.nextYear == nil)
            .help("Next year (⌘])")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Menu listing every offered year with its photo count.
struct YearPicker: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.navigator.years, id: \.self) { years in
                Button {
                    model.goToYear(years)
                } label: {
                    let count = model.navigator.count(yearsAgo: years)
                    let label = "\(DisplayFormat.yearsAgo(years)) (\(String(model.calendarYear(yearsAgo: years))))"
                    if years == model.yearsAgo {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                    Text(count == 0 ? "No photos" : count == 1 ? "1 photo" : "\(count) photos")
                }
            }
        } label: {
            Text(String(model.displayedYear))
        }
        .fixedSize()
        .help("Choose a year")
    }
}

/// "Next Year" button for the end card and empty panel.
private struct NextYearButton: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        if let next = model.nextYear {
            Button("Next Year: \(String(model.calendarYear(yearsAgo: next)))") { model.goToNextYear() }
                .buttonStyle(.borderedProminent)
        }
    }
}

private extension LabelStyle where Self == TitleAndIconTrailingLabelStyle {
    static var titleAndIconTrailing: TitleAndIconTrailingLabelStyle { .init() }
}

/// Title first, icon after: for "Next Year ▶▶".
private struct TitleAndIconTrailingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// Decodes and shows one photo, scaled to fit.
struct PhotoView: View {
    let photo: PhotoItem
    let images: ImageRepository

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
            let decoded = await images.image(for: photo, maxPixelSize: ViewerModel.displayPixelSize)
            guard !Task.isCancelled else { return }
            image = decoded
            failed = decoded == nil
        }
    }
}

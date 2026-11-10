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
        if model.hasNoActiveSource {
            ContentUnavailableView {
                Label("No Sources Available", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Every source is turned off or offline.")
            } actions: {
                Button("Open Sources…") { model.isShowingSources = true }
            }
        } else if model.stepper.isEmpty {
            ContentUnavailableView {
                Label("No Photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("No photos from \(DisplayFormat.range(model.window)).")
            } actions: {
                NextYearButton()
            }
        } else if let photo = model.currentPhoto {
            PhotoView(photo: photo, images: model.images)
                .contextMenu {
                    Button("Zoom In") { model.zoomIn() }
                    Button("Zoom Out") { model.zoomOut() }.disabled(!model.zoom.isZoomed)
                    Button("Zoom to Fit") { model.zoomToFit() }.disabled(!model.zoom.isZoomed)
                    Divider()
                    Button(model.revealTitle) { model.revealCurrentPhoto() }
                }
                .overlay(alignment: .top) {
                    if model.zoom.isZoomed {
                        ZoomBadge()
                            .padding(.top, 12)
                    }
                }
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
        .buttonStyle(.overlay)
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
        .accessibilityLabel("Year: \(String(model.displayedYear))")
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

/// Decodes and shows one photo, scaled to fit, with zoom and pan:
/// pinch or ⌘= / ⌘- to zoom, double-click to toggle, drag to pan.
struct PhotoView: View {
    @Environment(ViewerModel.self) private var model
    let photo: PhotoItem
    let images: ImageRepository

    @State private var image: CGImage?
    @State private var failed = false
    /// Scale and offset when the current pinch or drag began.
    @State private var pinchStart: Double?
    @State private var dragStart: CGSize?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    let layout = ZoomState.Layout(imageSize: CGSize(width: image.width, height: image.height),
                                                  viewport: geometry.size)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: layout.fitted.width, height: layout.fitted.height)
                        .scaleEffect(model.zoom.scale)
                        .offset(model.zoom.offset)
                        .onChange(of: layout, initial: true) { _, layout in
                            model.updateZoomLayout(layout)
                        }
                } else if failed {
                    ContentUnavailableView("Can't Preview “\(photo.fileName)”",
                                           systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(.rect)
            .clipped()
            .gesture(magnify)
            .simultaneousGesture(pan)
            .onTapGesture(count: 2) { model.toggleZoom() }
            .pointerStyle(model.zoom.isZoomed ? (dragStart == nil ? .grabIdle : .grabActive) : nil)
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo from \(DisplayFormat.photoDate(photo.date))")
        .accessibilityAddTraits(.isImage)
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

private extension PhotoView {
    /// Trackpad pinch, relative to the scale when the pinch began.
    var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? model.zoom.scale
                pinchStart = start
                model.setZoomScale(start * value.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Drag to pan, only while zoomed.
    var pan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard model.zoom.isZoomed else { return }
                let start = dragStart ?? model.zoom.offset
                dragStart = start
                model.setZoomOffset(CGSize(width: start.width + value.translation.width,
                                           height: start.height + value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// "250%  [Fit]" over a zoomed photo.
private struct ZoomBadge: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text("\(model.zoom.percent)%")
                .monospacedDigit()
            Button("Fit") { model.zoomToFit() }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .help("Zoom to fit (⌘0)")
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }
}

/// A round button that stays visible over any photo, light or dark: a
/// dark translucent disc with a light outline and a soft shadow.
struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OverlayButton(configuration: configuration)
    }

    private struct OverlayButton: View {
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false
        let configuration: ButtonStyleConfiguration

        var body: some View {
            // Disabled buttons keep their disc, so they still read as buttons
            // on a white photo; only the arrow dims.
            configuration.label
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.black.opacity(discOpacity)))
                .overlay(Circle().strokeBorder(.white.opacity(isEnabled ? 0.7 : 0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                .contentShape(Circle())
                .onHover { isHovered = $0 }
        }

        private var discOpacity: Double {
            guard isEnabled else { return 0.4 }
            return configuration.isPressed ? 0.75 : isHovered ? 0.65 : 0.5
        }
    }
}

extension ButtonStyle where Self == OverlayButtonStyle {
    static var overlay: OverlayButtonStyle { OverlayButtonStyle() }
}

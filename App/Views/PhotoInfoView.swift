import AppKit
import SwiftUI
import YearAgoCore

/// The Photo Info popover: every known value for one photo, in sections,
/// with Open in Maps when the photo has a location. See
/// docs/photo-info-implementation-plan.md.
struct PhotoInfoView: View {
    @Environment(ViewerModel.self) private var model
    let photo: PhotoItem

    @State private var info: PhotoInfo?
    @State private var isLoaded = false
    /// Shown only if reading is slow, so fast reads don't flash a spinner.
    @State private var showsSpinner = false
    /// The rows' natural height. A scroll view in a popover has none, so
    /// the popover sizes to this, up to `maxScrollHeight`.
    @State private var contentHeight: CGFloat = 0
    private let maxScrollHeight: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 380)
        .background(navigationShortcuts)
        .task(id: photo.id) { await load() }
    }

    private var header: some View {
        HStack {
            Text("Photo Info").font(.headline)
            Spacer()
            Button("Copy All", systemImage: "doc.on.doc") { copyAll() }
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .disabled(info == nil)
                .help("Copy every value as text")
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if let info {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let coordinate = info.coordinate {
                        MapsRow(coordinate: coordinate, label: DisplayFormat.photoDate(photo.date))
                    }
                    ForEach(info.sections) { section in
                        SectionView(section: section)
                    }
                    footer(info)
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 80), maxScrollHeight))
        } else if isLoaded {
            Text("No details are available for this photo.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            ProgressView()
                .controlSize(.small)
                .opacity(showsSpinner ? 1 : 0)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    @ViewBuilder
    private func footer(_ info: PhotoInfo) -> some View {
        let lines = [
            info.skippedBinaryCount > 0
                ? (info.skippedBinaryCount == 1 ? "1 binary value not shown."
                                                : "\(info.skippedBinaryCount) binary values not shown.")
                : nil,
            info.note,
        ].compactMap { $0 }
        if !lines.isEmpty {
            Text(lines.joined(separator: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ← and → still change photos while the popover has focus. Changing
    /// photos closes it (see ViewerView).
    private var navigationShortcuts: some View {
        ZStack {
            Button("Previous Photo") { model.previousPhoto() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Photo") { model.nextPhoto() }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func load() async {
        info = nil
        isLoaded = false
        showsSpinner = false
        let spinner = Task {
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled { showsSpinner = true }
        }
        let loaded = await model.photoInfo(for: photo)
        spinner.cancel()
        guard !Task.isCancelled else { return }
        info = loaded
        isLoaded = true
    }

    private func copyAll() {
        guard let info else { return }
        var text = info.plainText
        if let coordinate = info.coordinate, info.section("Location") == nil {
            text = "Location\nCoordinates: \(coordinate.formatted)\n\n" + text
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Coordinates with an Open in Maps button. The Maps app shows the map;
/// this app makes no network request.
private struct MapsRow: View {
    let coordinate: Coordinate
    let label: String

    var body: some View {
        HStack {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(.secondary)
            Text(coordinate.formatted)
                .textSelection(.enabled)
                .monospacedDigit()
            Spacer()
            Button("Open in Maps") {
                NSWorkspace.shared.open(coordinate.mapsURL(label: label))
            }
            .controlSize(.small)
            .help("Show this place in the Maps app")
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
    }
}

/// A section title and its label/value rows.
private struct SectionView: View {
    let section: PhotoInfo.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.subheadline.bold())
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                            .frame(minWidth: 110, alignment: .trailing)
                        Text(row.value)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.callout)
        }
    }
}

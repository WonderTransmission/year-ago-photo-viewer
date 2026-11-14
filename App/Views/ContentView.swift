import SwiftUI
import YearAgoCore

/// The main window. Shows a welcome screen, first-index progress, or the viewer.
struct ContentView: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let since = model.libraryOpeningSince {
                LibraryOpeningBanner(since: since)
                Divider()
            }
            switch model.phase {
            case .loading:
                Color.clear
            case .noSources:
                WelcomeView { model.isAddingFolder = true }
            case .scanning:
                ScanProgressView(
                    sourceName: model.syncingSourceID.flatMap(model.source(id:))?.name ?? "photos",
                    progress: model.scanProgress)
            case .ready:
                ViewerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle(CoreInfo.appName)
        .toolbar {
            ToolbarItemGroup {
                if model.phase == .ready, let progress = model.scanProgress {
                    ProgressView()
                        .controlSize(.small)
                        .help(DisplayFormat.progress(progress))
                }
                Button {
                    model.isShowingSources = true
                } label: {
                    Label(model.enabledSourceCount == 1 ? "1 Source" : "\(model.enabledSourceCount) Sources",
                          systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                }
                .help("Show, hide, and add photo sources")
                DefaultDateMenu()
                WindowLengthPicker(selection: $model.weeks)
                    .pickerStyle(.menu)
                    .fixedSize()
            }
        }
        .fileImporter(isPresented: $model.isAddingFolder, allowedContentTypes: [.folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.addFolders(urls)
            }
        }
        .onOpenURL { model.openDeepLink($0) }
        .sheet(isPresented: $model.isShowingSources) {
            SourcesView()
        }
        .alert("Something Went Wrong",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Toolbar menu: the default date setting for new sources, and "Apply to
/// All Sources".
private struct DefaultDateMenu: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Default Date for New Sources", selection: $model.defaultDateSource) {
                ForEach(DateSourceKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Apply “\(model.defaultDateSource.displayName)” to All Sources") {
                model.applyDefaultDateSourceToAll()
            }
            .disabled(model.sources.isEmpty)
        } label: {
            Text("Default date: \(model.defaultDateSource.displayName)")
        }
        .fixedSize()
        .help("The date setting for new sources. Each source can override it in the Sources panel.")
    }
}

/// Full-window progress for the first index.
private struct ScanProgressView: View {
    let sourceName: String
    let progress: ScanProgress?

    var body: some View {
        VStack(spacing: 12) {
            Text("Indexing “\(sourceName)”")
                .font(.headline)
            if let progress, progress.stage == .reading, let total = progress.total, total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(total))
                    .frame(width: 320)
            } else {
                ProgressView()
            }
            Text(progress.map(DisplayFormat.progress) ?? "Starting…")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("This happens once. Later launches only check for changes.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown before any source is added.
private struct WelcomeView: View {
    let addFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Add a Photo Folder", systemImage: "photo.stack")
        } description: {
            Text("\(CoreInfo.appName) shows the photos you took this week in past years.")
        } actions: {
            Button("Add Folder…", action: addFolder)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Shown while waiting for macOS to open the Photos library. That can take
/// many minutes the first time, e.g. after a macOS upgrade or on a slow
/// external drive. The rest of the app keeps working meanwhile.
private struct LibraryOpeningBanner: View {
    let since: Date
    /// Seconds before explaining why it can take long.
    static let explainAfter: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let waited = context.date.timeIntervalSince(since)
            HStack(alignment: .top, spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Opening your Photos library…").fontWeight(.semibold)
                        Text(DisplayFormat.elapsed(waited))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if waited >= Self.explainAfter {
                        Text("macOS is preparing your Photos library. After a macOS update, or on an external drive, this can take a while the first time. You can keep using the app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if waited >= Self.explainAfter {
                    Button("Show Progress in Photos") { PhotoKitLibrary.openPhotosApp() }
                        .help("The Photos app shows its own progress while macOS prepares the library.")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.yellow.opacity(0.12))
        }
        .accessibilityElement(children: .combine)
    }
}

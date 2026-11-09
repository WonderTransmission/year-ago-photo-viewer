import SwiftUI
import YearAgoCore

/// The main window. Shows a welcome screen, scan progress, or the viewer.
struct ContentView: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .noFolder:
                WelcomeView { model.isChoosingFolder = true }
            case .scanning:
                ScanProgressView(folderName: model.folderName ?? "folder", progress: model.scanProgress)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Can't Open Folder", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Choose Folder…") { model.isChoosingFolder = true }
                }
            case .ready:
                ViewerView()
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle(model.folderName ?? CoreInfo.appName)
        .toolbar {
            ToolbarItemGroup {
                DateSourcePicker(selection: $model.dateSource)
                    .pickerStyle(.menu)
                    .fixedSize()
                WindowLengthPicker(selection: $model.weeks)
                    .pickerStyle(.menu)
                    .fixedSize()
            }
            if model.phase == .ready, let progress = model.scanProgress {
                ToolbarItem {
                    ProgressView()
                        .controlSize(.small)
                        .help(ScanProgressView.describe(progress))
                }
            }
            ToolbarItem {
                Button("Choose Folder…", systemImage: "folder") {
                    model.isChoosingFolder = true
                }
            }
        }
        .fileImporter(isPresented: $model.isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.chooseFolder(url)
            }
        }
    }
}

/// Full-window progress for the first index of a folder.
private struct ScanProgressView: View {
    let folderName: String
    let progress: ScanProgress?

    var body: some View {
        VStack(spacing: 12) {
            Text("Indexing “\(folderName)”")
                .font(.headline)
            if let progress, progress.stage == .reading, let total = progress.total, total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(total))
                    .frame(width: 320)
            } else {
                ProgressView()
            }
            Text(progress.map(Self.describe) ?? "Starting…")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("This happens once. Later launches only check for changes.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Finding photos… 3,500 found" or "Reading photo details… 1,234 of 9,876".
    static func describe(_ progress: ScanProgress) -> String {
        switch progress.stage {
        case .finding:
            "Finding photos… \(progress.completed.formatted()) found"
        case .reading:
            "Reading photo details… \(progress.completed.formatted()) of \((progress.total ?? 0).formatted())"
        }
    }
}

/// Shown before any folder is chosen.
private struct WelcomeView: View {
    let chooseFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Choose a Photo Folder", systemImage: "photo.stack")
        } description: {
            Text("\(CoreInfo.appName) shows the photos you took this week in past years.")
        } actions: {
            Button("Choose Folder…", action: chooseFolder)
                .buttonStyle(.borderedProminent)
        }
    }
}

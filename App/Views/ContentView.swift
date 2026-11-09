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
                ProgressView("Scanning “\(model.folderName ?? "folder")”…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

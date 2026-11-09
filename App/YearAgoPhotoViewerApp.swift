import SwiftUI
import YearAgoCore

@main
struct YearAgoPhotoViewerApp: App {
    @State private var model = ViewerModel()

    var body: some Scene {
        Window(CoreInfo.appName, id: "main") {
            ContentView()
                .environment(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Folder…") { model.isChoosingFolder = true }
                    .keyboardShortcut("o")
            }
        }
    }
}

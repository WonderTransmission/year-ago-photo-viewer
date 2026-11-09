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
            ViewerCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Menu bar commands: File > Choose Folder, the View menu settings, and a
/// Go menu for photos and years.
private struct ViewerCommands: Commands {
    @Bindable var model: ViewerModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Choose Folder…") { model.isChoosingFolder = true }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .toolbar) {
            Toggle("Show Years with No Photos", isOn: $model.showEmptyYears)
            Picker("Window Length", selection: $model.weeks) {
                ForEach(WindowCalculator.allowedWeeks, id: \.self) { weeks in
                    Text(weeks == 1 ? "1 Week" : "\(weeks) Weeks").tag(weeks)
                }
            }
            Picker("Date From", selection: $model.dateSource) {
                ForEach(DateSourceKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Divider()
        }

        CommandMenu("Go") {
            Button("Previous Year") { model.goToPreviousYear() }
                .keyboardShortcut("[")
                .disabled(model.previousYear == nil)
            Button("Next Year") { model.goToNextYear() }
                .keyboardShortcut("]")
                .disabled(model.nextYear == nil)
        }
    }
}

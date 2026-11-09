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

/// Menu bar commands: File > Add Folder and Sources, View settings, and a
/// Go menu for years.
private struct ViewerCommands: Commands {
    @Bindable var model: ViewerModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Folder…") { model.isAddingFolder = true }
                .keyboardShortcut("o")
            Button("Sources…") { model.isShowingSources = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button(model.revealTitle) { model.revealCurrentPhoto() }
                .keyboardShortcut("r")
                .disabled(model.currentPhoto == nil)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Show Years with No Photos", isOn: $model.showEmptyYears)
            Picker("Window Length", selection: $model.weeks) {
                ForEach(WindowCalculator.allowedWeeks, id: \.self) { weeks in
                    Text(weeks == 1 ? "1 Week" : "\(weeks) Weeks").tag(weeks)
                }
            }
            Picker("Default Date for New Sources", selection: $model.defaultDateSource) {
                ForEach(DateSourceKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Divider()
        }

        CommandMenu("Go") {
            // Arrow keys also work in the window; these menu items document
            // them without stealing arrows from text fields.
            Button("Previous Photo") { model.previousPhoto() }
                .disabled(!model.stepper.canGoBack)
            Button("Next Photo") { model.nextPhoto() }
                .disabled(!model.stepper.canGoForward)
            Divider()
            Button("Previous Year") { model.goToPreviousYear() }
                .keyboardShortcut("[")
                .disabled(model.previousYear == nil)
            Button("Next Year") { model.goToNextYear() }
                .keyboardShortcut("]")
                .disabled(model.nextYear == nil)
        }
    }
}

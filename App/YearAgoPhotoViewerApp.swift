import SwiftUI
import YearAgoCore

@main
struct YearAgoPhotoViewerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = ViewerModel()

    var body: some Scene {
        Window(CoreInfo.appName, id: "main") {
            ContentView()
                .environment(model)
        }
        .commands {
            ViewerCommands(model: model)
        }

        MenuBarExtra("On This Day", systemImage: "clock.arrow.circlepath", isInserted: $model.showMenuBarItem) {
            MenuBarContentView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Keeps the app running after its window closes while the menu bar item
/// is shown, so the item stays available.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !SettingsStore().showMenuBarItem
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
            Toggle("Oldest Years First", isOn: $model.oldestYearsFirst)
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
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("=")
                .disabled(model.currentPhoto == nil)
            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-")
                .disabled(!model.zoom.isZoomed)
            Button("Zoom to Fit") { model.zoomToFit() }
                .keyboardShortcut("0")
                .disabled(!model.zoom.isZoomed)
            Divider()
            Button(model.isShowingInfo ? "Hide Photo Info" : "Photo Info") { model.toggleInfo() }
                .keyboardShortcut("i")
                .disabled(model.currentPhoto == nil)
            Divider()
        }

        CommandMenu("Go") {
            // Arrow keys also work in the window; these menu items document
            // them without stealing arrows from text fields.
            Button("Previous Photo") { model.previousPhoto() }
                .disabled(!model.canStepBack)
            Button("Next Photo") { model.nextPhoto() }
                .disabled(!model.canStepForward)
            Divider()
            // ⌘[ and ⌘] press the left and right year buttons, whose labels
            // depend on the direction of travel.
            Button(model.backYearLabel) { model.goBackYear() }
                .keyboardShortcut("[")
                .disabled(model.backYear == nil)
            Button(model.forwardYearLabel) { model.goForwardYear() }
                .keyboardShortcut("]")
                .disabled(model.forwardYear == nil)
            Divider()
            // ⇧⌘] jumps to the far end in the direction of travel, ⇧⌘[ to the start.
            Button("Oldest Year") { model.goToOldestYear() }
                .keyboardShortcut(model.forwardIsEarlier ? "]" : "[", modifiers: [.command, .shift])
                .disabled(model.oldestYear == nil || model.oldestYear == model.yearsAgo)
            Button("Most Recent Year") { model.goToMostRecentYear() }
                .keyboardShortcut(model.forwardIsEarlier ? "[" : "]", modifiers: [.command, .shift])
                .disabled(model.mostRecentYear == nil || model.mostRecentYear == model.yearsAgo)
        }
    }
}

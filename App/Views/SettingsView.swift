import SwiftUI
import YearAgoCore

/// The Settings window (⌘,).
struct SettingsView: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                WindowLengthPicker(selection: $model.weeks)
                Toggle("Show years with no photos", isOn: $model.showEmptyYears)
            }
            Section {
                Picker("Default date for new sources", selection: $model.defaultDateSource) {
                    ForEach(DateSourceKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .help(model.defaultDateSource.helpText)
                Button("Manage Sources…") { model.isShowingSources = true }
            } footer: {
                Text("Each source has its own date setting in the Sources panel.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}

/// Picker for the window length, 1–6 weeks.
struct WindowLengthPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("Window", selection: $selection) {
            ForEach(WindowCalculator.allowedWeeks, id: \.self) { weeks in
                Text(weeks == 1 ? "1 week" : "\(weeks) weeks").tag(weeks)
            }
        }
    }
}

extension DateSourceKind {
    /// Tooltip explaining the source and its caveats.
    var helpText: String {
        switch self {
        case .fileName: "Dates read from file names, such as macOS screenshot names."
        case .modified: "The file's last-modified date. Editing or syncing can change it."
        case .created: "The file's creation date. Copying a file often resets it."
        case .exif: "The capture date stored in the photo."
        }
    }
}

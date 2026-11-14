import SwiftUI
import YearAgoCore

/// The Sources panel: every photo source, with its on/off switch, name,
/// date setting, and status. See proposal section 5.1.
struct SourcesView: View {
    @Environment(ViewerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int64?
    @State private var isAddingFolder = false
    @State private var pendingRemoval: SourceRecord?

    var body: some View {
        VStack(spacing: 0) {
            Text("Sources")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            List(selection: $selection) {
                ForEach(model.sources) { source in
                    SourceRow(source: source)
                        .tag(source.id)
                }
                .onMove { model.moveSources(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if model.sources.isEmpty {
                    ContentUnavailableView("No Sources", systemImage: "folder.badge.plus",
                                           description: Text("Add a folder of photos to get started."))
                }
            }

            Divider()
            HStack {
                Button("Add Folder…", systemImage: "plus") { isAddingFolder = true }
                Button("Add Photos Library", systemImage: "photo.on.rectangle") { model.addPhotosLibrary() }
                    .disabled(model.hasPhotosLibrary)
                    .help(model.hasPhotosLibrary ? "The Photos library is already a source"
                                                 : "Show photos from your Mac's Photos library")
                Button("Remove", systemImage: "minus") {
                    pendingRemoval = selection.flatMap(model.source(id:))
                }
                .disabled(selection == nil)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 360)
        .fileImporter(isPresented: $isAddingFolder, allowedContentTypes: [.folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.addFolders(urls)
            }
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { source in
            Button("Remove", role: .destructive) {
                model.removeSource(source.id)
                selection = nil
            }
        } message: { _ in
            Text("Your photos stay where they are. Only the app's index for this source is deleted.")
        }
    }
}

/// One source: [✓] Name   Date: [EXIF ▾]   48,311 photos
private struct SourceRow: View {
    @Environment(ViewerModel.self) private var model
    let source: SourceRecord

    @State private var draftName = ""
    @FocusState private var isEditingName: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Show photos from \(source.name)", isOn: Binding(
                get: { source.isEnabled },
                set: { model.setEnabled($0, forSource: source.id) }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(systemName: source.kind == .photos ? "photo.on.rectangle" : "folder")
                .foregroundStyle(.secondary)

            TextField("Name", text: $draftName)
                .textFieldStyle(.plain)
                .focused($isEditingName)
                .onSubmit { model.renameSource(source.id, to: draftName) }
                .onChange(of: isEditingName) { _, editing in
                    if !editing { model.renameSource(source.id, to: draftName) }
                }
                .help(source.rootPath ?? source.name)

            Picker("Date", selection: Binding(
                get: { source.dateSource },
                set: { model.setDateSource($0, forSource: source.id) })) {
                ForEach(DateSourceKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .fixedSize()
            .help(source.dateSource.helpText)

            status
                .frame(width: 170, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .opacity(source.isEnabled ? 1 : 0.6)
        .onAppear { draftName = source.name }
        .onChange(of: source.name) { _, name in draftName = name }
    }

    @ViewBuilder
    private var status: some View {
        if !source.isOnline, source.kind == .photos, !model.photosAccessGranted {
            Button("No Access…") { PhotoKitLibrary.openPrivacySettings() }
                .buttonStyle(.link)
                .help("Turn on Photos access in System Settings › Privacy & Security › Photos, then relaunch.")
        } else if !source.isOnline, source.kind == .photos {
            Label("Unavailable", systemImage: "externaldrive.badge.xmark")
                .foregroundStyle(.secondary)
                .help("The Photos library can't be reached, for example because its drive is disconnected. Its index is kept until it returns.")
        } else if !source.isOnline {
            Label("Offline", systemImage: "externaldrive.badge.xmark")
                .foregroundStyle(.secondary)
                .help("The folder can't be reached. Its index is kept until it returns.")
        } else if model.syncingSourceID == source.id {
            if let progress = model.scanProgress, !progress.isIndeterminate || progress.fraction > 0 {
                HStack(spacing: 6) {
                    ProgressView(value: progress.fraction)
                        .frame(width: 90)
                    Text("\(progress.percent)%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
                .help(DisplayFormat.progress(progress))
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.scanProgress.map(DisplayFormat.shortProgress) ?? "Starting…")
                }
                .foregroundStyle(.secondary)
            }
        } else if model.waitingSourceIDs.contains(source.id) {
            Label("Waiting", systemImage: "clock")
                .foregroundStyle(.secondary)
                .help("Indexes after the sources before it.")
        } else {
            let visible = model.sourceStats[source.id]?.visible ?? 0
            Text(visible == 1 ? "1 photo" : "\(visible.formatted()) photos")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

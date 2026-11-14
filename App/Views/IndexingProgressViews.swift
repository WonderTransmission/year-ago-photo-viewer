import SwiftUI
import YearAgoCore

/// Toolbar control while indexing: a progress ring and "Indexing 42%".
/// Clicking it shows the details popover. See plan section 3.3.
struct IndexingToolbarButton: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Button {
            model.isShowingIndexingDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                if model.overallIsIndeterminate {
                    ProgressView().controlSize(.small)
                } else {
                    ProgressView(value: model.overallFraction ?? 0)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
                Text(title)
                    .monospacedDigit()
            }
        }
        .help("Indexing progress")
        .popover(isPresented: $model.isShowingIndexingDetails, arrowEdge: .bottom) {
            IndexingDetailsView()
                .environment(model)
        }
        .accessibilityLabel(title)
    }

    private var title: String {
        if model.overallIsIndeterminate { return "Indexing…" }
        return "Indexing \(Int(((model.overallFraction ?? 0) * 100).rounded(.down)))%"
    }
}

/// The popover: what is being indexed, how far along, time left, and
/// what's waiting.
struct IndexingDetailsView: View {
    @Environment(ViewerModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Indexing")
                .font(.headline)

            if model.isIndexing {
                current
                Divider()
                overall
                if !waitingNames.isEmpty {
                    Text("Waiting: \(waitingNames.joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Stop", systemImage: "stop.circle") { model.stopCurrentIndexing() }
                        .help(model.syncingSourceID == nil
                              ? "Stop checking for duplicates. It runs again after the next index."
                              : "Stop indexing this source. Photos indexed so far stay. Resume it from the Sources panel.")
                }
            } else {
                Text("All sources are up to date.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 340)
    }

    /// The source (or duplicate check) in progress.
    @ViewBuilder
    private var current: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentName)
                .fontWeight(.semibold)
                .lineLimit(1)
            if let progress = model.scanProgress, !progress.isIndeterminate || progress.fraction > 0 {
                ProgressView(value: progress.fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(model.scanProgress.map(DisplayFormat.progress) ?? "Starting…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var overall: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.roundSteps > 2 ? "Overall, step \(min(model.roundStepsDone + 1, model.roundSteps)) of \(model.roundSteps)" : "Overall")
                Spacer()
                if !model.overallIsIndeterminate {
                    Text("\(Int(((model.overallFraction ?? 0) * 100).rounded(.down)))%")
                        .monospacedDigit()
                }
            }
            .font(.callout)
            TimeLeftLabel(seconds: model.timeLeft)
        }
    }

    private var currentName: String {
        if let id = model.syncingSourceID, let source = model.source(id: id) {
            return source.name
        }
        return model.scanProgress?.stage == .hashing ? "All sources" : "Preparing…"
    }

    private var waitingNames: [String] {
        model.waitingSourceIDs.compactMap { model.source(id: $0)?.name }
    }
}

/// "About 12 minutes left", or "Estimating time left…" until there's
/// enough data.
struct TimeLeftLabel: View {
    let seconds: TimeInterval?

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var text: String {
        guard let seconds else { return "Estimating time left…" }
        let phrase = ProgressEstimator.describe(seconds)
        return phrase.prefix(1).uppercased() + phrase.dropFirst() + " left"
    }
}

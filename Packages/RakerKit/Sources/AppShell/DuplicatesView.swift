import AppKit
import DesignSystem
import DuplicateEngine
import RakerFoundation
import SwiftUI

/// Identical files, verified byte for byte. One copy of each set always stays.
struct DuplicatesView: View {
    @Bindable var model: AppModel

    var body: some View {
        content
            .navigationTitle("Duplicates")
            .toolbar {
                ToolbarItem {
                    Picker("Copy to keep", selection: $model.duplicateStrategy) {
                        ForEach(SurvivorStrategy.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .help("Which copy Raker suggests keeping in each set")
                    .disabled(model.duplicateSets.isEmpty)
                }
                ToolbarItem {
                    Button {
                        model.findDuplicates()
                    } label: {
                        Label("Compare Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.report == nil || model.duplicatesPhase == .scanning || model.isCleaning)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.report == nil {
            ContentUnavailableView {
                Label("Duplicates", systemImage: "square.on.square")
            } description: {
                Text("Scan a folder first, then Raker compares the files in it.")
            } actions: {
                Button("Scan \(model.scope.title)") { model.startScan() }
                    .prominentActionStyle()
            }
        } else {
            switch model.duplicatesPhase {
            case .idle:
                ContentUnavailableView {
                    Label("Find duplicates in \(model.scope.title)", systemImage: "square.on.square")
                } description: {
                    Text("Raker compares file contents byte for byte, on this Mac. Files in iCloud that aren't downloaded are left alone.")
                } actions: {
                    Button("Find Duplicates") { model.findDuplicates() }
                        .prominentActionStyle()
                }
            case .scanning:
                VStack(spacing: Spacing.m) {
                    if let progress = model.duplicateProgress, progress.filesToHash > 0 {
                        ProgressView(value: progress.fraction)
                            .frame(width: 320)
                        Text("Comparing \(progress.filesHashed.formatted()) of \(progress.filesToHash.formatted()) files…")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } else {
                        ProgressView("Looking for files of the same size…")
                    }
                    Button("Cancel") { model.cancelDuplicates() }
                }
            case .failed(let message):
                ContentUnavailableView("Couldn't compare files", systemImage: "exclamationmark.triangle", description: Text(message))
            case .finished:
                if model.duplicateSets.isEmpty {
                    ContentUnavailableView {
                        Label("No duplicates", systemImage: "checkmark.circle")
                    } description: {
                        Text("Every file in \(model.scope.title) is unique.")
                    }
                } else {
                    results
                }
            }
        }
    }

    private var results: some View {
        let frees = model.duplicateSets.reduce(UInt64(0)) { $0 &+ $1.reclaimable(keeping: model.keeper(of: $1).path) }
        return VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text("\(model.duplicateSets.count.formatted()) set\(model.duplicateSets.count == 1 ? "" : "s"), up to")
                        SizeText(frees)
                        Text("to free")
                    }
                    .font(.headline)
                    Text("★ marks the copy that stays. Nothing goes in the Tray until you choose.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select All Duplicates") { model.selectAllDuplicates() }
                if !model.duplicatesSelection.isEmpty {
                    Button("Remove from Tray") { model.duplicatesSelection = [] }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            Divider()
            List(selection: $model.inspectedIDs[.duplicates]) {
                ForEach(model.duplicateSets) { set in
                    DuplicateSetSection(set: set, model: model)
                }
            }
        }
    }
}

struct DuplicateSetSection: View {
    let set: DuplicateSet
    @Bindable var model: AppModel

    var body: some View {
        let keeper = model.keeper(of: set)
        Section {
            ForEach(set.files) { file in
                HStack(spacing: Spacing.s) {
                    if file.path == keeper.path {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .frame(width: 16)
                            .help("This copy stays")
                    } else {
                        Toggle(isOn: Binding(
                            get: { model.duplicatesSelection.contains(file.path) },
                            set: { isOn in
                                if isOn { model.duplicatesSelection.insert(file.path) } else { model.duplicatesSelection.remove(file.path) }
                            }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .frame(width: 16)
                    }
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(abbreviated((file.path as NSString).deletingLastPathComponent))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Modified \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if file.path == keeper.path {
                        Badge(text: "Stays", tint: Palette.rebuildsAutomatically)
                    } else {
                        Button("Keep This One") { model.keep(file, in: set) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                .contextMenu {
                    Button("Quick Look") { model.previewURL = URL(fileURLWithPath: file.path) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                    }
                    Divider()
                    Button("Lock as Original") { model.addUserRule(.lockOriginal, for: file.path) }
                    Button("Never Suggest This") { model.addUserRule(.exclude, for: file.path) }
                }
                .tag(file.path)
            }
        } header: {
            HStack(spacing: Spacing.s) {
                Text((keeper.path as NSString).lastPathComponent)
                    .font(.headline)
                Text("\(set.files.count) copies × \(ByteCount(set.size).formatted)")
                    .foregroundStyle(.secondary)
                Spacer()
                if set.sharesAllData {
                    Text("Copies share their data: removing them frees nothing")
                        .font(.caption)
                        .foregroundStyle(Palette.expert)
                } else {
                    Text("Frees \(ByteCount(set.reclaimable(keeping: keeper.path)).formatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

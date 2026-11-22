import AppKit
import DesignSystem
import RakerFoundation
import RakerModel
import ScanEngine
import SwiftUI

/// Downloads & Installers, and Large & Old: personal files with where they came from and when
/// they were last opened. Nothing is selected for you, and everything goes to the Trash.
struct PersonalFilesView: View {
    @Bindable var model: AppModel
    let list: AppModel.PersonalList

    var body: some View {
        content
            .navigationTitle(list == .downloads ? "Downloads & Installers" : "Large & Old")
            .toolbar { toolbar }
            .confirmationDialog(
                "Move \(selected.count.formatted()) item\(selected.count == 1 ? "" : "s") to the Trash?",
                isPresented: Binding(
                    get: { model.confirmingTrash == list },
                    set: { if !$0 { model.confirmingTrash = nil } }
                )
            ) {
                Button("Move to Trash") { model.trashSelected(list) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can put them back from Receipts while they're still in the Trash.")
            }
    }

    private var phase: AppModel.Phase {
        list == .downloads ? model.downloadsPhase : model.largePhase
    }

    private var selection: Binding<Set<String>> {
        list == .downloads ? $model.downloadsSelection : $model.largeSelection
    }

    private var selected: [Finding] {
        model.findings(for: list).filter { selection.wrappedValue.contains($0.id) }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            if list == .downloads {
                ContentUnavailableView {
                    Label("Downloads & Installers", systemImage: "arrow.down.circle")
                } description: {
                    Text("See what's piled up in Downloads, where each item came from, and which installers are for apps you already have.")
                } actions: {
                    Button("Scan Downloads") { model.scanDownloads() }
                        .prominentActionStyle()
                }
            } else {
                ContentUnavailableView {
                    Label("Large & Old", systemImage: "clock.badge.exclamationmark")
                } description: {
                    Text("Find big files, and files you haven't opened in a long time, in the folder you scan.")
                } actions: {
                    Button("Scan \(model.scope.title)") { model.startScan() }
                        .prominentActionStyle()
                }
            }
        case .scanning:
            ProgressView(list == .downloads ? "Looking through Downloads…" : "Finding large files…")
                .controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn't scan", systemImage: "exclamationmark.triangle", description: Text(message))
        case .finished:
            let findings = model.findings(for: list)
            if findings.isEmpty {
                ContentUnavailableView {
                    Label(list == .downloads ? "Downloads is empty" : "No files match", systemImage: "checkmark.circle")
                } description: {
                    Text(list == .downloads ? "Nothing to review here." : "Try a smaller size or a shorter time.")
                }
            } else {
                VStack(spacing: 0) {
                    header(findings)
                    Divider()
                    FindingsTable(
                        findings: findings, selection: selection,
                        onPreview: { model.previewURL = $0 },
                        onRule: { kind, path in model.addUserRule(kind, for: path) }
                    )
                }
                .safeAreaInset(edge: .bottom) {
                    TrashActionBar(selected: selected, disabled: model.isCleaning) {
                        model.confirmingTrash = list
                    }
                    .padding(Spacing.l)
                }
            }
        }
    }

    private func header(_ findings: [Finding]) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text("\(findings.count.formatted()) item\(findings.count == 1 ? "" : "s"),")
                    SizeText(findings.reduce(UInt64(0)) { $0 &+ $1.size.allocated })
                }
                .font(.headline)
                Text(list == .downloads
                     ? "Nothing is selected for you. Archives may be your only copy of what's inside."
                     : "Files in \(model.scope.title) from the last scan. App bundles, ~/Library and hidden folders are left out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if list == .downloads {
                Button("Select Installers of Installed Apps") { model.selectInstallersOfInstalledApps() }
            }
            if !selection.wrappedValue.isEmpty {
                Button("Clear Selection") { selection.wrappedValue = [] }
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if list == .largeAndOld {
            ToolbarItem {
                Picker("At least", selection: $model.largeCriteria.minimumSize) {
                    Text("10 MB or more").tag(UInt64(10_000_000))
                    Text("50 MB or more").tag(UInt64(50_000_000))
                    Text("100 MB or more").tag(UInt64(100_000_000))
                    Text("500 MB or more").tag(UInt64(500_000_000))
                    Text("1 GB or more").tag(UInt64(1_000_000_000))
                }
                .help("Smallest file size to list")
            }
            ToolbarItem {
                Picker("Not opened", selection: $model.largeCriteria.notOpenedForDays) {
                    Text("Opened any time").tag(Int?.none)
                    Text("Not opened for 3 months").tag(Int?.some(90))
                    Text("Not opened for a year").tag(Int?.some(365))
                    Text("Not opened for 2 years").tag(Int?.some(730))
                }
                .help("Only files you haven't opened for a while")
            }
        }
        ToolbarItem {
            Button {
                list == .downloads ? model.scanDownloads() : model.startScan()
            } label: {
                Label("Scan Again", systemImage: "arrow.clockwise")
            }
            .disabled(phase == .scanning || model.isCleaning)
        }
    }
}

/// Personal files with a checkbox, size, last-opened date and download source.
struct FindingsTable: View {
    let findings: [Finding]
    @Binding var selection: Set<String>
    let onPreview: (URL) -> Void
    let onRule: (UserRule.Kind, String) -> Void

    var body: some View {
        Table(findings) {
            TableColumn("") { finding in
                Toggle(isOn: Binding(
                    get: { selection.contains(finding.id) },
                    set: { isOn in
                        if isOn { selection.insert(finding.id) } else { selection.remove(finding.id) }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(finding.isSynced)
            }
            .width(22)
            TableColumn("Name") { finding in
                HStack(spacing: Spacing.s) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: finding.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(Paths.lastComponent(finding.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let app = finding.installedAppName {
                        Badge(text: "\(app) is installed", tint: Palette.rebuildsAutomatically)
                    }
                    if finding.isSynced {
                        Badge(text: "Synced, remove it in its cloud app", tint: .secondary)
                    }
                }
                .contextMenu {
                    Button("Quick Look") { onPreview(URL(fileURLWithPath: finding.path)) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: finding.path)])
                    }
                    Divider()
                    Button("Never Suggest This") { onRule(.exclude, finding.path) }
                    Button("Lock as Original") { onRule(.lockOriginal, finding.path) }
                }
            }
            .width(min: 240, ideal: 380)
            TableColumn("Size") { finding in
                SizeText(finding.size.allocated)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Last Opened") { finding in
                Text(finding.lastOpened.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
            TableColumn("From") { finding in
                Text(finding.downloadSite ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 140)
        }
    }
}

struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

/// The floating bar for personal files: they always go to the Trash.
struct TrashActionBar: View {
    let selected: [Finding]
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selected.isEmpty ? "Nothing selected" : "\(selected.count.formatted()) item\(selected.count == 1 ? "" : "s") selected")
                    .font(.headline)
                if !selected.isEmpty {
                    SizeText(selected.reduce(UInt64(0)) { $0 &+ $1.size.allocated })
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: action) {
                Label("Move to Trash…", systemImage: "trash")
                    .padding(.horizontal, Spacing.s)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .disabled(selected.isEmpty || disabled)
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .glassPanel(cornerRadius: Radius.panel)
    }
}

extension Finding {
    var path: String {
        if case .file(let ref) = subject { return ref.path }
        return ""
    }

    var isSynced: Bool {
        constraints.contains { if case .synced = $0 { true } else { false } }
    }

    var installedAppName: String? {
        for item in evidence {
            if case .appInstalled(let name) = item { return name }
        }
        return nil
    }

    var lastOpened: Date? {
        for item in evidence {
            if case .lastOpened(let date) = item { return date }
        }
        return nil
    }

    var downloadSite: String? {
        for item in evidence {
            if case .downloadedFrom(let site) = item { return site }
        }
        return nil
    }
}

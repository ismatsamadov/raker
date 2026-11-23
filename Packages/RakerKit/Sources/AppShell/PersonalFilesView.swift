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
    }

    private var phase: AppModel.Phase {
        list == .downloads ? model.downloadsPhase : model.largePhase
    }

    private var selection: Binding<Set<String>> {
        list == .downloads ? $model.downloadsSelection : $model.largeSelection
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            if list == .downloads {
                WorkspaceState(title: "Downloads & Installers", symbol: "arrow.down.circle",
                               detail: "See what's piled up in Downloads, where each item came from, and which installers are for apps you already have.", tint: Palette.ochre) {
                    Button("Scan Downloads") { model.scanDownloads() }
                        .prominentActionStyle()
                }
            } else {
                FolderScanPrompt(section: .largeAndOld, detail: "Find big files, and files you haven't opened in a long time, in the folder you scan.", model: model)
            }
        case .scanning:
            ProgressView(list == .downloads ? "Looking through Downloads…" : "Finding large files…")
                .controlSize(.large)
        case .failed(let message):
            if list == .downloads, model.access[.downloads] == .denied {
                WorkspaceState(title: "Raker can't open Downloads", symbol: "lock",
                               detail: "macOS asked whether Raker may open Downloads, and the answer was no. You can change it in System Settings › Privacy & Security › Files & Folders.", tint: Palette.ochre) {
                    Button("Open Privacy Settings") { PrivacySettings.open(.filesAndFolders) }
                    Button("Try Again") { model.scanDownloads() }
                }
            } else {
                WorkspaceState(title: "Couldn't scan", symbol: "exclamationmark.triangle",
                               detail: message, tint: Palette.ochre)
            }
        case .finished:
            let findings = model.findings(for: list)
            if findings.isEmpty {
                WorkspaceState(title: list == .downloads ? "Downloads is empty" : "No files match", symbol: "checkmark.circle",
                               detail: list == .downloads ? "Nothing to review here." : "Try a smaller size or a shorter time.", tint: list == .downloads ? Palette.ochre : Palette.lagoon)
            } else {
                VStack(spacing: 0) {
                    header(findings)
                    Divider()
                    FindingsTable(
                        findings: findings, selection: selection,
                        inspected: $model.inspectedIDs[list == .downloads ? .downloads : .largeAndOld],
                        onPreview: { model.previewURL = $0 },
                        onRule: { kind, path in model.addUserRule(kind, for: path) }
                    )
                    .environment(\.defaultMinListRowHeight, 32)
                    .reviewKeyboard(model)
                }
            }
        }
    }

    private func header(_ findings: [Finding]) -> some View {
        let section: AppModel.Section = list == .downloads ? .downloads : .largeAndOld
        let bytes = findings.reduce(UInt64(0)) { $0 &+ $1.size.allocated }
        return VStack(alignment: .leading, spacing: Spacing.m) {
            PanelHeading(title: "\(ByteCount(bytes).formatted) across \(findings.count.formatted()) item\(findings.count == 1 ? "" : "s")",
                         symbol: section.symbol,
                         detail: list == .downloads
                             ? "Choose which downloads to stage. An archive may be your only copy of its contents."
                             : "From \(model.scope.title). App bundles, Library and hidden folders are excluded.",
                         tint: section.tint)
            ViewThatFits(in: .horizontal) {
                HStack { selectionActions }
                VStack(alignment: .leading) { selectionActions }
            }
        }
        .padding(Spacing.l)
        .background(Palette.paper)
    }

    @ViewBuilder
    private var selectionActions: some View {
        if list == .downloads {
            Button("Select Installers of Installed Apps") { model.selectInstallersOfInstalledApps() }
        }
        // Always there, so staging the first item doesn't push the list down.
        Button("Remove from Tray") { selection.wrappedValue = [] }
            .disabled(selection.wrappedValue.isEmpty)
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
    /// The row in focus, shown in the inspector.
    @Binding var inspected: String?
    let onPreview: (URL) -> Void
    let onRule: (UserRule.Kind, String) -> Void

    var body: some View {
        Table(findings, selection: $inspected) {
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

import AppCatalog
import AppKit
import DesignSystem
import RakerFoundation
import ScanEngine
import SwiftUI

/// Installed apps with their size, source and architecture, and for the selected app,
/// every file Raker found for it, ready to uninstall or reset through the Tray.
struct AppsView: View {
    @Bindable var model: AppModel

    var body: some View {
        content
            .navigationTitle("Applications")
            .toolbar {
                ToolbarItem {
                    Picker("Sort by", selection: $model.appSort) {
                        Text("Largest First").tag(AppModel.AppSort.size)
                        Text("Name").tag(AppModel.AppSort.name)
                        Text("Least Recently Opened").tag(AppModel.AppSort.lastOpened)
                    }
                    .help("How to sort the apps")
                }
                ToolbarItem {
                    Button {
                        model.loadApps()
                    } label: {
                        Label("Look Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.appsPhase == .scanning)
                }
            }
            .onAppear {
                if model.appsPhase == .idle { model.loadApps() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.installedApps.isEmpty {
            if model.appsPhase == .scanning {
                ProgressView("Finding your apps…")
                    .controlSize(.large)
            } else {
                WorkspaceState(title: "No apps found", symbol: "square.grid.2x2",
                               detail: "Raker looks in /Applications and ~/Applications.", tint: Palette.iris)
            }
        } else {
            HStack(spacing: 0) {
                appList
                    .frame(minWidth: 220, idealWidth: 270, maxWidth: 300)
                Divider()
                AppDetailView(model: model)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $model.appSearch)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search apps")
                if !model.appSearch.isEmpty {
                    Button { model.appSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(Spacing.s)
            .surfaceCard(cornerRadius: Radius.control)
            .padding(Spacing.m)
            List(selection: $model.selectedAppPath) {
                ForEach(model.visibleApps) { app in
                    AppRow(app: app, size: model.appSizes[app.path], lastOpened: model.appLastOpened[app.path],
                           isRunning: model.isRunning(app))
                        .tag(app.path)
                }
            }
            .listStyle(.inset)
            .overlay {
                if model.visibleApps.isEmpty {
                    ContentUnavailableView.search(text: model.appSearch)
                }
            }
            Divider()
            let intel = model.installedApps.filter { $0.architecture == .intel }.count
            Text("\(model.installedApps.count.formatted()) apps" + (intel > 0 ? " · \(intel.formatted()) for Intel only" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(Spacing.s)
        }
    }
}

struct AppRow: View {
    let app: AppBundleInfo
    let size: UInt64?
    let lastOpened: Date?
    let isRunning: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(app.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if app.architecture == .intel {
                        Badge(text: "Intel", tint: Palette.expert)
                    }
                    if isRunning {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Palette.rebuildsAutomatically)
                            .help("Running")
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            if let size {
                SizeText(size)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let version = app.version { parts.append(version) }
        if let lastOpened {
            parts.append("opened " + lastOpened.formatted(.relative(presentation: .named)))
        } else {
            parts.append("never opened")
        }
        return parts.joined(separator: " · ")
    }
}

/// The selected app and everything Raker found for it.
struct AppDetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let app = model.selectedApp {
            List {
                Section {
                    header(app)
                    actions(app)
                    notes(app)
                }
                if model.appFilesPhase == .scanning {
                    Section {
                        ProgressView("Looking for its files…")
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(AppFile.Kind.allCases, id: \.self) { kind in
                    let files = model.appFiles.filter { $0.kind == kind }
                    if !files.isEmpty {
                        Section(kind.title) {
                            ForEach(files) { file in
                                AppFileRow(file: file, id: "apps:\(file.path)", selection: $model.appsSelection,
                                           measurement: model.appFileMeasurements[file.path], isEnabled: app.isRemovable,
                                           model: model)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .id(app.path)
        } else {
            WorkspaceState(title: "Select an app", symbol: "square.grid.2x2",
                           detail: "See everything an app keeps on your Mac, then uninstall it or reset it.", tint: Palette.iris)
        }
    }

    private func header(_ app: AppBundleInfo) -> some View {
        let appSize = model.appFileMeasurements[app.path]?.size.allocated ?? model.appSizes[app.path] ?? 0
        let dataSize = model.appFiles.filter { $0.kind != .application }
            .reduce(UInt64(0)) { $0 &+ (model.appFileMeasurements[$1.path]?.size.allocated ?? 0) }
        return HStack(alignment: .center, spacing: Spacing.l) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                Text([app.version, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: Spacing.xs) {
                    Badge(text: app.source.title, tint: Palette.review)
                    Badge(text: app.architecture.title, tint: app.architecture == .intel ? Palette.expert : .secondary)
                    if model.isRunning(app) {
                        Badge(text: "Running", tint: Palette.rebuildsAutomatically)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                SizeText(appSize &+ dataSize)
                    .font(.rakerMetric)
                Text("app \(ByteCount(appSize).formatted) · data \(ByteCount(dataSize).formatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.m)
        .surfaceCard()
    }

    private func actions(_ app: AppBundleInfo) -> some View {
        let resettable = model.appFiles.contains { $0.isPreselected && AppModel.resettableKinds.contains($0.kind) }
        return HStack(spacing: Spacing.m) {
            Button {
                model.stageUninstall()
            } label: {
                Label("Uninstall…", systemImage: "trash")
                    .padding(.horizontal, Spacing.xs)
            }
            .prominentActionStyle()
            .disabled(!app.isRemovable || model.appFilesPhase != .finished)
            .help("Put the app and the files that are certainly its own in the Tray, then review")
            Button {
                model.stageReset()
            } label: {
                Label("Reset…", systemImage: "arrow.counterclockwise")
            }
            .disabled(!resettable)
            .help("Remove its settings, caches and saved windows, keeping the app and its data")
            Spacer()
            Text("Only certain matches are chosen for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func notes(_ app: AppBundleInfo) -> some View {
        if !app.isRemovable {
            Label("Part of macOS, so it can't be removed.", systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if app.architecture == .intel {
            Label("Built for Intel processors. It runs through Rosetta 2, which macOS 27 is the last version to fully support.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Palette.expert)
        }
    }
}

/// One of an app's files, with a checkbox that stages it.
struct AppFileRow: View {
    let file: AppFile
    /// The ID of the file's finding, which the checkbox adds to the selection.
    let id: String
    @Binding var selection: Set<String>
    let measurement: PathMeasurement?
    var isEnabled = true
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: Spacing.s) {
            Toggle(isOn: Binding(
                get: { selection.contains(id) },
                set: { isOn in
                    if isOn { selection.insert(id) } else { selection.remove(id) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!isEnabled)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 18, height: 18)
            Text(abbreviated(file.path))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(file.path)
            Spacer(minLength: Spacing.s)
            if file.isShared {
                Badge(text: "May be shared", tint: Palette.expert)
            }
            ConfidenceChip(confidence: file.confidence)
            Group {
                if measurement?.isRefused == true {
                    Text("Not readable")
                        .help("Full Disk Access lets Raker measure it")
                } else if let measurement {
                    SizeText(measurement.size.allocated)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 72, alignment: .trailing)
        }
        .contextMenu {
            Button("Quick Look") { model.previewURL = URL(fileURLWithPath: file.path) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// How sure Raker is that a file belongs to the app, with an icon and a word.
struct ConfidenceChip: View {
    let confidence: AppFile.Confidence

    var body: some View {
        let (title, symbol, tint): (String, String, Color) = switch confidence {
        case .high: ("Certain", "checkmark.seal", Palette.rebuildsAutomatically)
        case .medium: ("Likely", "circle.lefthalf.filled", Palette.review)
        case .low: ("Possible", "questionmark.circle", .secondary)
        }
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .help(confidence == .high ? "Named after the app or declared by it" : "Matched by name or vendor; never chosen for you")
    }
}

extension AppBundleInfo.Source {
    var title: String {
        switch self {
        case .appStore: "App Store"
        case .setapp: "Setapp"
        case .apple: "macOS"
        case .direct: "Downloaded"
        }
    }
}

extension AppBundleInfo.Architecture {
    var title: String {
        switch self {
        case .universal: "Universal"
        case .appleSilicon: "Apple silicon"
        case .intel: "Intel only"
        case .unknown: "Unknown processor"
        }
    }
}

extension AppFile.Kind {
    var title: String {
        switch self {
        case .application: "Application"
        case .supportFiles: "Support Files"
        case .caches: "Caches"
        case .preferences: "Preferences"
        case .container: "Container"
        case .groupContainer: "Shared Containers"
        case .savedState: "Saved Windows"
        case .webData: "Website Data"
        case .logs: "Logs"
        case .launchAgent: "Launch Agents"
        case .scripts: "Scripts"
        case .temporary: "Temporary Files"
        }
    }
}

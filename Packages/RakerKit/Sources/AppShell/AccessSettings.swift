import AppKit
import DesignSystem
import RakerModel
import SwiftUI
import SystemKit

/// The Access Center: each protected area, whether Raker can read it, what that unlocks, and
/// how to allow it. States update by themselves when Raker becomes active again.
struct AccessSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PanelHeading(title: "Access", symbol: "lock.shield", detail: "Raker reads file names, sizes and dates on this Mac. Choose which locations it can include in a scan.")
                filesAndFolders
                fullDiskAccess
                otherAppsData
            }
            .padding(Spacing.xl)
        }
    }

    // MARK: Files & Folders

    private var filesAndFolders: some View {
        AccessSection(title: "Files & Folders", detail: "macOS asks the first time Raker opens each of these folders.") {
            let areas: [ProtectedArea] = [.downloads, .desktop, .documents]
            ForEach(areas, id: \.self) { area in
                AccessRow(area: area, state: model.access[area]) {
                    switch model.access[area] {
                    case .unknown:
                        Button("Allow…") { model.requestAccess(to: area) }
                    case .denied:
                        Button("Open Settings") { PrivacySettings.open(.filesAndFolders) }
                    case .granted, .absent:
                        EmptyView()
                    }
                }
                if area != areas.last {
                    Divider()
                }
            }
        }
    }

    // MARK: Full Disk Access

    private var fullDiskAccess: some View {
        let coverage = model.access.coverage(of: .fullDiskAccess)
        return AccessSection(title: "Full Disk Access", detail: "macOS never asks for this. You turn it on in System Settings.",
                             status: coverage.status) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Lets Raker measure caches and logs that macOS protects, the Trash, and Mail, Messages and Safari data.")
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading,
                          spacing: Spacing.s) {
                    ForEach([ProtectedArea.trash, .mail, .messages, .safari, .deviceBackups], id: \.self) { area in
                        AreaChip(area: area, state: model.access[area])
                    }
                }
                if coverage != .all {
                    Divider()
                    FullDiskAccessGuide()
                }
            }
        }
    }

    // MARK: Other apps' data

    private var otherAppsData: some View {
        // Full Disk Access covers other apps' data too.
        let state = model.access.coverage(of: .fullDiskAccess) == .all ? .granted : model.access[.otherAppsData]
        return AccessSection(title: "Other Apps' Data",
                             detail: "macOS asks the first time Raker looks inside another app's folders. Full Disk Access covers them too.") {
            AccessRow(area: .otherAppsData, state: state) { EmptyView() }
        }
    }
}

/// How to turn on Full Disk Access, for this version of macOS.
struct FullDiskAccessGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            GuideStep(number: 1) {
                Text("Open Full Disk Access in System Settings.")
                Spacer()
                Button("Open Settings") { PrivacySettings.open(.fullDiskAccess) }
            }
            GuideStep(number: 2) {
                Text("Turn on Raker. If it isn't in the list, drag this icon into it.")
                Spacer()
                DraggableAppIcon()
            }
            GuideStep(number: 3) {
                Text("Come back to Raker. It notices the change by itself; macOS may offer to quit and reopen it first.")
            }
            if PrivacySettings.allowsScopedFullDiskAccess {
                Label("This version of macOS lets you allow specific folders and apps instead of the whole disk. Raker uses what you allow, and lists what stays out of reach.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GuideStep<Content: View>: View {
    let number: Int
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Text(number.formatted())
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint))
                .accessibilityHidden(true)
            content
        }
    }
}

/// The app's icon, which can be dropped into System Settings' Full Disk Access list.
struct DraggableAppIcon: View {
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
            .resizable()
            .frame(width: 40, height: 40)
            .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
            .help("Drag into the Full Disk Access list")
            .accessibilityLabel("Raker app icon. Drag it into the Full Disk Access list.")
    }
}

// MARK: - Building blocks

struct AccessSection<Content: View>: View {
    let title: String
    let detail: String
    var status: (text: String, symbol: String, tint: Color)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let status {
                    Label(status.text, systemImage: status.symbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(status.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard()
        }
        .animation(Motion.snappy, value: status?.text)
    }
}

struct AccessRow<Accessory: View>: View {
    let area: ProtectedArea
    let state: AccessState
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: Spacing.m) {
            SymbolTile(area.symbol, tint: Palette.lagoon, size: 30)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(area.title).font(.body.weight(.medium))
                Text(area.unlocks)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.m)
            AccessStateLabel(area: area, state: state)
            accessory
        }
        .padding(.vertical, Spacing.s)
    }
}

/// An area's name with its state, for areas grouped under one permission.
struct AreaChip: View {
    let area: ProtectedArea
    let state: AccessState

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: state.symbol)
                .foregroundStyle(state.tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: state == .granted)
            Text(area.title)
                .foregroundStyle(state == .absent ? .secondary : .primary)
        }
        .font(.callout)
        .animation(Motion.snappy, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(area.title): \(state.title(for: area))")
    }
}

struct AccessStateLabel: View {
    let area: ProtectedArea
    let state: AccessState

    var body: some View {
        Label(state.title(for: area), systemImage: state.symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(state.tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: state == .granted)
            .animation(Motion.snappy, value: state)
    }
}

/// Opens System Settings at a privacy pane. Deep links change between macOS versions, so
/// they're best effort: if one doesn't open, System Settings opens on its main page.
enum PrivacySettings {
    static func open(_ permission: Permission) {
        let anchor = permission == .filesAndFolders ? "Privacy_FilesAndFolders" : "Privacy_AllFiles"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
           NSWorkspace.shared.open(url) {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// From macOS 27.3, Full Disk Access can be limited to specific folders and apps.
    static var allowsScopedFullDiskAccess: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 3, patchVersion: 0))
    }
}

// MARK: - Presentation

extension ProtectedArea {
    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .removableVolumes: "External drives"
        case .networkVolumes: "Network volumes"
        case .mail: "Mail"
        case .messages: "Messages"
        case .safari: "Safari"
        case .otherAppsData: "Other apps' data"
        case .trash: "Trash"
        case .deviceBackups: "iPhone & iPad backups"
        case .fullDiskAccess: "Protected Library folders"
        case .rootOnly: "System folders"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: "menubar.dock.rectangle"
        case .documents: "doc"
        case .downloads: "arrow.down.circle"
        case .removableVolumes: "externaldrive"
        case .networkVolumes: "server.rack"
        case .mail: "envelope"
        case .messages: "message"
        case .safari: "safari"
        case .otherAppsData: "square.stack.3d.up"
        case .trash: "trash"
        case .deviceBackups: "iphone"
        case .fullDiskAccess: "lock.shield"
        case .rootOnly: "lock"
        }
    }

    /// What being able to read the area lets Raker do.
    var unlocks: String {
        switch self {
        case .downloads: "Downloads & Installers, and scans that include Downloads."
        case .desktop: "Scans that include your Desktop."
        case .documents: "Scans that include Documents."
        case .otherAppsData: "Caches and files that apps keep in their own folders."
        case .removableVolumes, .networkVolumes: "Scans of drives you choose."
        case .mail, .messages, .safari, .trash, .deviceBackups, .fullDiskAccess: "Measuring what's there."
        case .rootOnly: "Measuring system caches and logs."
        }
    }
}

extension AccessState {
    func title(for area: ProtectedArea) -> String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .absent: "None on this Mac"
        case .unknown:
            if area.isQuietlyCheckable { "Checking…" } else if area.permission == .filesAndFolders { "Not asked yet" } else { "Not known yet" }
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "minus.circle.fill"
        case .unknown: "circle.dashed"
        case .absent: "circle.slash"
        }
    }

    var tint: Color {
        switch self {
        case .granted: Palette.rebuildsAutomatically
        case .denied: Palette.expert
        case .unknown, .absent: .secondary
        }
    }
}

extension AccessMap.Coverage {
    var status: (text: String, symbol: String, tint: Color) {
        switch self {
        case .all: ("On", "checkmark.circle.fill", Palette.rebuildsAutomatically)
        case .some: ("On for some areas", "circle.lefthalf.filled", Palette.review)
        case .none: ("Off", "minus.circle.fill", Palette.expert)
        case .unknown: ("Checking…", "circle.dashed", .secondary)
        }
    }
}

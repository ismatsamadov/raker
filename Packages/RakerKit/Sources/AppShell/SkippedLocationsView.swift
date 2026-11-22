import DesignSystem
import RakerFoundation
import RakerModel
import SwiftUI

/// Locations a scan couldn't read, grouped by what protects them, and the way to allow them.
struct SkippedLocationsView: View {
    let model: AppModel
    let locations: [SkippedLocation]
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Raker couldn't read \(locations.count.formatted()) location\(locations.count == 1 ? "" : "s")")
                    .font(.headline)
                Text("They aren't included in the sizes you see.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            HStack {
                Spacer()
                AccessSettingsButton(model: model, onOpen: onOpenSettings)
                    .prominentActionStyle()
            }
        }
        .padding(Spacing.l)
        .frame(width: 400)
    }

    private func groupView(_ group: Group) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: group.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(group.title).font(.body.weight(.medium))
                Text(group.hint).font(.caption).foregroundStyle(.secondary)
                ForEach(group.paths.prefix(3), id: \.self) { path in
                    Text(Self.abbreviated(path))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if group.paths.count > 3 {
                    Text("and \((group.paths.count - 3).formatted()) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let hint: String
        var paths: [String]
    }

    /// Files & Folders areas each have their own switch in System Settings, so they're
    /// listed one by one; everything under one permission is listed together.
    private var groups: [Group] {
        var result: [Group] = []
        for location in locations {
            let group = Self.group(for: location.reason)
            if let index = result.firstIndex(where: { $0.id == group.id }) {
                result[index].paths.append(location.path)
            } else {
                var new = group
                new.paths = [location.path]
                result.append(new)
            }
        }
        return result.sorted { $0.paths.count > $1.paths.count }
    }

    private static func group(for reason: SkippedLocation.Reason) -> Group {
        guard case .permissionDenied(let area) = reason else {
            return Group(id: "error", title: "Couldn't be read", symbol: "exclamationmark.triangle",
                         hint: "The disk reported an error, or the item went away during the scan.", paths: [])
        }
        switch area.permission {
        case .filesAndFolders:
            return Group(id: area.rawValue, title: area.title, symbol: area.symbol,
                         hint: "Allow it in System Settings › Privacy & Security › Files & Folders.", paths: [])
        case .fullDiskAccess:
            return Group(id: "fullDiskAccess", title: "Full Disk Access", symbol: "lock.shield",
                         hint: "Mail, Safari, the Trash and other folders macOS protects.", paths: [])
        case .appData:
            return Group(id: "appData", title: "Other apps' data", symbol: ProtectedArea.otherAppsData.symbol,
                         hint: "macOS asks before Raker looks inside another app's folders. Full Disk Access covers them too.",
                         paths: [])
        case .administrator:
            return Group(id: "administrator", title: "System folders", symbol: "lock",
                         hint: "Only an administrator can read these.", paths: [])
        }
    }

    private static func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// A calm note under a list: some locations were protected, with details on request.
struct ProtectedLocationsNotice: View {
    @Bindable var model: AppModel
    let locations: [SkippedLocation]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(Palette.review)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(locations.count.formatted()) location\(locations.count == 1 ? " is" : "s are") protected by macOS")
                    .font(.headline)
                Text("Raker couldn't look inside, so they aren't listed. Full Disk Access lets Raker measure them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Details…") { model.isShowingUnreadable = true }
                .popover(isPresented: $model.isShowingUnreadable, arrowEdge: .top) {
                    SkippedLocationsView(model: model, locations: locations) { model.isShowingUnreadable = false }
                }
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Opens Settings at the Access Center.
struct AccessSettingsButton: View {
    let model: AppModel
    var onOpen: () -> Void = {}
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Access Settings") {
            model.settingsTab = .access
            onOpen()
            openSettings()
        }
    }
}

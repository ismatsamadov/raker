import AppKit
import DesignSystem
import RakerFoundation
import RakerModel
import SwiftUI

/// The floating capsule at the bottom of the window: what's staged from every section, and
/// the way to review it.
struct TrayCapsule: View {
    @Bindable var model: AppModel

    var body: some View {
        let tray = model.tray
        HStack(spacing: Spacing.m) {
            Image(systemName: tray.isEmpty ? "tray" : "tray.full.fill")
                .font(.title2)
                .foregroundStyle(tray.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: tray.count)
                .frame(width: 28)
            if tray.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("The Tray is empty")
                        .font(.headline)
                    Text("Check items in any list to stage them here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(tray.count.formatted()) item\(tray.count == 1 ? "" : "s") in the Tray")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    HStack(spacing: Spacing.xxs) {
                        SizeText(tray.allocatedBytes)
                        if tray.reclaimableBytes < tray.allocatedBytes / 10 * 9 {
                            Text("· frees about")
                            SizeText(tray.reclaimableBytes)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.l)
                Button {
                    model.isReviewingTray = true
                } label: {
                    Label("Review…", systemImage: "sparkles")
                        .padding(.horizontal, Spacing.s)
                }
                .prominentActionStyle()
                .controlSize(.large)
                .disabled(model.isCleaning)
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(width: tray.isEmpty ? 360 : 520)
        .glassPanel(cornerRadius: 30)
        .animation(Motion.snappy, value: tray.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tray")
    }
}

/// Everything staged, grouped by where it goes, before anything is removed.
struct TrayReviewView: View {
    @Bindable var model: AppModel

    var body: some View {
        let items = model.tray.items
        let deleted = items.filter { model.deleteRegenerable && $0.finding.safety == .regenerable }
        let trashed = items.filter { !(model.deleteRegenerable && $0.finding.safety == .regenerable) }
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Review the Tray")
                        .font(.title2.weight(.semibold))
                    HStack(spacing: Spacing.xxs) {
                        Text("\(items.count.formatted()) item\(items.count == 1 ? "" : "s") ·")
                        SizeText(model.tray.allocatedBytes)
                        Text("· frees about")
                        SizeText(model.tray.reclaimableBytes)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Tray") { model.clearTray() }
                    .disabled(items.isEmpty)
            }
            List {
                if !deleted.isEmpty {
                    Section {
                        ForEach(deleted) { TrayItemRow(item: $0, model: model) }
                    } header: {
                        DestinationRow(symbol: "arrow.clockwise", tint: Palette.rebuildsAutomatically,
                                       title: "Deleted permanently", detail: "They rebuild automatically.",
                                       findings: deleted.map(\.finding))
                    }
                }
                if !trashed.isEmpty {
                    Section {
                        ForEach(trashed) { TrayItemRow(item: $0, model: model) }
                    } header: {
                        DestinationRow(symbol: "trash", tint: Palette.review,
                                       title: "Moved to the Trash", detail: "You can put them back from Receipts.",
                                       findings: trashed.map(\.finding))
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 260)
            if model.tray.items.contains(where: { $0.finding.safety == .regenerable }) {
                Toggle("Skip the Trash for items that rebuild automatically", isOn: $model.deleteRegenerable)
            }
            if !model.appsBlockingTray.isEmpty {
                Label("Quit \(model.appsBlockingTray.joined(separator: " and ")) first, or their items are skipped.",
                      systemImage: "app.badge.checkmark")
                    .foregroundStyle(Palette.expert)
                    .font(.callout)
            }
            HStack {
                Text("Every item is checked again just before it's removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { model.isReviewingTray = false }
                    .keyboardShortcut(.cancelAction)
                Button("Clean \(items.count.formatted()) Item\(items.count == 1 ? "" : "s")") { model.cleanTray() }
                    .prominentActionStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(items.isEmpty || model.isCleaning)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 640, height: 580)
    }
}

struct TrayItemRow: View {
    let item: TrayItem
    let model: AppModel

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.finding.path))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.finding.displayName)
                    .lineLimit(1)
                Text(abbreviated(item.finding.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Badge(text: item.source.title, tint: .secondary)
            SizeText(item.finding.size.allocated)
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
            Button {
                model.unstage(item.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Take out of the Tray")
            .accessibilityLabel("Take \(item.finding.displayName) out of the Tray")
        }
        .contextMenu {
            Button("Quick Look") { model.previewURL = URL(fileURLWithPath: item.finding.path) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.finding.path)])
            }
            Divider()
            Button("Take Out of the Tray") { model.unstage(item.id) }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

extension TrayItem.Source {
    var title: String {
        switch self {
        case .cleanup: "Caches & Temporary Files"
        case .downloads: "Downloads"
        case .largeAndOld: "Large & Old"
        case .duplicates: "Duplicate"
        }
    }
}

extension Finding {
    /// The owning app's name for app data, otherwise the file's name.
    var displayName: String {
        for item in evidence {
            if case .owner(let name, _) = item { return name }
        }
        return Paths.lastComponent(path)
    }
}

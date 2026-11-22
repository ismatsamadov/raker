import AppKit
import DesignSystem
import RakerFoundation
import RakerModel
import RuleEngine
import SafetyPolicy
import ScanEngine
import SpaceIndex
import SwiftUI

/// "What is this?" for the file or folder in focus in Largest Items: what it is, who it
/// belongs to, what Raker's safety policy says, and what can be done with it.
struct LocationInspectorView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let tree = model.report?.tree, let index = model.inspectedLocation {
            let path = tree.path(of: index)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header(tree: tree, index: index, path: path)
                    staging
                    Divider()
                    if let explanation = model.locationExplanation, explanation.path == path {
                        about(explanation)
                    }
                    Divider()
                    details(tree: tree, index: index)
                    Divider()
                    actions(path: path)
                }
                .padding(Spacing.l)
            }
            .id(path)
        } else {
            ContentUnavailableView {
                Label("Nothing to explain", systemImage: "questionmark.folder")
            } description: {
                Text("Scan a folder, then select anything in it to see what it is.")
            }
        }
    }

    // MARK: Parts

    private func header(tree: SizeTree, index: SizeTree.Index, path: String) -> some View {
        VStack(spacing: Spacing.m) {
            Group {
                if let thumbnail = model.inspectorThumbnail, thumbnail.path == path {
                    Image(nsImage: thumbnail.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 112, height: 112)
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            VStack(spacing: Spacing.xxs) {
                Text(index == tree.root ? Paths.lastComponent(tree.rootPath) : tree.name(of: index))
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                Text(abbreviated(path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .multilineTextAlignment(.center)
            if let level = model.locationExplanation?.rule?.safety.level {
                SafetyChip(level: level)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var staging: some View {
        if let finding = model.inspectedFinding {
            if model.tray.contains(finding.id) {
                Button {
                    model.toggleStaged(finding)
                } label: {
                    Label("In the Tray", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Take it out of the Tray")
            } else if model.canStageFromExplorer(finding) {
                Button {
                    model.toggleStaged(finding)
                } label: {
                    Label("Add to Tray", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity)
                }
                .prominentActionStyle()
                .controlSize(.large)
                .help("Stage it for cleaning; it goes to the Trash")
            } else {
                Label(finding.isSynced ? "Synced: remove it in its cloud app" : "Raker won't remove this",
                      systemImage: finding.isSynced ? "icloud" : "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func about(_ explanation: LocationExplanation) -> some View {
        if let rule = explanation.rule {
            paragraph("What it is", "\(rule.title). \(rule.explanation)")
            paragraph("If removed", rule.ifRemoved)
        } else if let known = explanation.knownLocation, explanation.knownLocationIsExact {
            paragraph("What it is", "\(known.title). \(known.explanation)")
            if !known.removable {
                paragraph("If removed", "Raker never removes this folder as a whole, only parts a rule describes.")
            }
        } else {
            paragraph("What it is", explanation.knownLocation.map { "Inside \($0.title.lowercased()). \($0.explanation)" }
                ?? "No rule describes this location yet.")
        }
        if let owner = explanation.owner.summary {
            paragraph("Belongs to", owner)
        }
        paragraph("Raker's policy", explanation.verdict.summary)
    }

    private func paragraph(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func details(tree: SizeTree, index: SizeTree.Index) -> some View {
        let size = tree.size(of: index)
        let onDisk = ByteCount(size.allocated).formatted
        let frees = size.reclaimable.map { ByteCount($0).formatted }
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
            row("On disk", onDisk)
            if let frees, frees != onDisk {
                row("Frees", frees)
            }
            if tree.kind(of: index) == .directory {
                row("Items", tree.descendantCount(of: index).formatted())
            }
            row("Modified", tree.modificationDate(of: index).formatted(date: .abbreviated, time: .shortened))
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func actions(path: String) -> some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Button {
                    model.previewURL = URL(fileURLWithPath: path)
                } label: {
                    Label("Quick Look", systemImage: "eye").frame(maxWidth: .infinity)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Label("Reveal", systemImage: "folder").frame(maxWidth: .infinity)
                }
            }
            Button {
                model.addUserRule(.exclude, for: path)
            } label: {
                Label("Never Suggest This", systemImage: "hand.raised").frame(maxWidth: .infinity)
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

extension Owner {
    /// Who the location belongs to, or nil when its name says nothing.
    var summary: String? {
        switch status {
        case .installed: "\(name), an installed app."
        case .system: "macOS."
        case .notInstalled: "No installed app is called \(name). It may be left over from an app you removed."
        case .unknown: nil
        }
    }
}

extension SafetyPolicy.Verdict {
    var summary: String {
        switch self {
        case .allowed: "Cleanup rules can include it, and you can choose it yourself."
        case .selectionOnly(let reason): "Raker removes it only if you choose it yourself: \(reason.phrase)."
        case .denied(let reason): "Raker never removes it: \(reason.phrase)."
        }
    }
}

extension SafetyPolicy.Reason {
    var phrase: String {
        switch self {
        case .notAbsolute: "it isn't a full path"
        case .volumeRoot: "it's the top of a disk"
        case .systemLocation: "it's part of macOS"
        case .protectedFolder: "macOS and apps expect this folder to be there"
        case .credentials: "it holds passwords or keys"
        case .appDatabases: "apps keep their databases here"
        case .photosLibraryInternals: "it's inside a Photos library"
        case .otherUserData: "it belongs to another user"
        case .personalFiles: "these are your own files"
        case .installedApps: "it's an installed app"
        case .syncedFolder: "it's synced, so removing it here would remove it everywhere"
        case .userExcluded: "you excluded it"
        case .lockedOriginal: "you locked it as an original"
        }
    }
}

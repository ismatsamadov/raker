import AppKit
import DesignSystem
import RakerFoundation
import RakerModel
import SwiftUI

/// The item in focus: what it is, why it's listed, what happens if it's removed, and what
/// can be done with it.
struct InspectorView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let finding = model.inspectedFinding {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header(finding)
                    staging(finding)
                    Divider()
                    explanation("Why it's here", finding.explanation)
                    explanation("If removed", model.ifRemoved(finding))
                    Divider()
                    details(finding)
                    Divider()
                    actions(finding)
                }
                .padding(Spacing.l)
            }
            .id(finding.id)
            .transition(.opacity)
        } else {
            ContentUnavailableView {
                Label("No Selection", systemImage: "sidebar.right")
            } description: {
                Text("Select an item to see what it is and what happens if it's removed.")
            }
        }
    }

    // MARK: Parts

    private func header(_ finding: Finding) -> some View {
        VStack(spacing: Spacing.m) {
            Group {
                if let thumbnail = model.inspectorThumbnail, thumbnail.path == finding.path {
                    Image(nsImage: thumbnail.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: finding.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 128, height: 128)
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            .animation(Motion.reveal, value: model.inspectorThumbnail?.path)
            VStack(spacing: Spacing.xxs) {
                Text(finding.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                Text(abbreviated(finding.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .multilineTextAlignment(.center)
            if !model.isKeptCopy(finding) {
                SafetyChip(level: finding.safety)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func staging(_ finding: Finding) -> some View {
        if model.isKeptCopy(finding) {
            Label("This copy stays", systemImage: "star.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity)
        } else if finding.isSynced {
            Label("Synced: remove it in its cloud app", systemImage: "icloud")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if model.tray.contains(finding.id) {
            Button {
                model.toggleStaged(finding)
            } label: {
                Label("In the Tray", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .help("Take it out of the Tray")
        } else {
            Button {
                model.toggleStaged(finding)
            } label: {
                Label("Add to Tray", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .help("Stage it for cleaning")
        }
    }

    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func details(_ finding: Finding) -> some View {
        let dates = FileDates(path: finding.path)
        // Other sizes only when they'd read differently from the size on disk.
        let onDisk = ByteCount(finding.size.allocated).formatted
        let frees = finding.size.reclaimable.map { ByteCount($0).formatted }
        let size = ByteCount(finding.size.logical).formatted
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
            detail("On disk", onDisk)
            if let frees, frees != onDisk {
                detail("Frees", frees)
            }
            if size != onDisk {
                detail("Size", size)
            }
            if let modified = dates.modified {
                detail("Modified", modified.formatted(date: .abbreviated, time: .shortened))
            }
            if let added = dates.added {
                detail("Added", added.formatted(date: .abbreviated, time: .omitted))
            }
            ForEach(Array(finding.evidence.enumerated()), id: \.offset) { _, evidence in
                if let line = describe(evidence) {
                    detail(line.label, line.value)
                }
            }
            detail("Goes to", model.deleteRegenerable && finding.safety == .regenerable ? "Deleted" : "Trash")
        }
        .font(.callout)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func describe(_ evidence: Evidence) -> (label: String, value: String)? {
        switch evidence {
        case .rule(let id): ("Rule", id)
        case .downloadedFrom(let site): ("From", site)
        case .lastOpened(let date): ("Last opened", date.formatted(.relative(presentation: .named)))
        case .largerThan(let bytes): ("Larger than", ByteCount(bytes).formatted)
        case .olderThan(let days): ("Untouched for", "\(days.formatted()) days or more")
        case .matchedBundleID(let bundleID): ("App ID", bundleID)
        case .owner(let name, _): ("Used by", name)
        case .ownerNotInstalled: ("Used by", "No installed app")
        case .appInstalled(let name): ("Installed", name)
        case .duplicateOf(let path, _): ("Copy of", abbreviated(path))
        }
    }

    private func actions(_ finding: Finding) -> some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Button {
                    model.previewURL = URL(fileURLWithPath: finding.path)
                } label: {
                    Label("Quick Look", systemImage: "eye").frame(maxWidth: .infinity)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: finding.path)])
                } label: {
                    Label("Reveal", systemImage: "folder").frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: Spacing.s) {
                Button {
                    model.addUserRule(.exclude, for: finding.path)
                } label: {
                    Label("Exclude", systemImage: "hand.raised").frame(maxWidth: .infinity)
                }
                .help("Never suggest this again")
                Button {
                    model.addUserRule(.lockOriginal, for: finding.path)
                } label: {
                    Label("Lock", systemImage: "lock").frame(maxWidth: .infinity)
                }
                .help("Lock it as an original: always the copy that stays")
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// A safety level as a colored chip, always with its icon and name.
struct SafetyChip: View {
    let level: SafetyLevel

    var body: some View {
        Label(level.title, systemImage: level.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(level.tint)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(level.tint.opacity(0.12)))
    }
}

/// When a file was last changed and when it arrived in its folder.
struct FileDates {
    let modified: Date?
    let added: Date?

    init(path: String) {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
        modified = values?.contentModificationDate
        added = values?.addedToDirectoryDate
    }
}

extension View {
    /// In a list: Space previews the item in focus, Delete stages or unstages it, E excludes
    /// it and L locks it as an original.
    func reviewKeyboard(_ model: AppModel) -> some View {
        onKeyPress(.space) { actOnInspected(model) { model.previewURL = URL(fileURLWithPath: $0.path) } }
            .onKeyPress(.delete) { actOnInspected(model) { model.toggleStaged($0) } }
            .onKeyPress("e") { actOnInspected(model) { model.addUserRule(.exclude, for: $0.path) } }
            .onKeyPress("l") { actOnInspected(model) { model.addUserRule(.lockOriginal, for: $0.path) } }
    }
}

@MainActor
private func actOnInspected(_ model: AppModel, _ action: (Finding) -> Void) -> KeyPress.Result {
    guard let finding = model.inspectedFinding else { return .ignored }
    action(finding)
    return .handled
}

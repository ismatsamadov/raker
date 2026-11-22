import AppKit
import CleanEngine
import DesignSystem
import RakerFoundation
import RakerModel
import RuleEngine
import ScanEngine
import SwiftUI

/// Caches, temporary files and logs: what each item is, whether it rebuilds itself, and
/// cleaning the ones you choose.
struct CleanupView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.cleanupPhase {
            case .idle:
                ContentUnavailableView {
                    Label("Caches, temporary files and logs", systemImage: "sparkles")
                } description: {
                    Text("See what apps and tools leave behind, what each item is, and whether it rebuilds itself. Nothing is removed until you choose.")
                } actions: {
                    Button("Scan") { model.scanCleanup() }
                        .prominentActionStyle()
                }
            case .scanning:
                ProgressView("Looking through caches, temporary files and logs…")
                    .controlSize(.large)
            case .failed(let message):
                ContentUnavailableView("Couldn't scan", systemImage: "exclamationmark.triangle", description: Text(message))
            case .finished:
                if let report = model.cleanupReport {
                    CleanupReportList(report: report, selection: $model.cleanupSelection, appName: model.appName(for:))
                        .safeAreaInset(edge: .bottom) {
                            CleanupActionBar(model: model)
                                .padding(Spacing.l)
                        }
                }
            }
        }
        .navigationTitle("Caches & Temporary Files")
        .toolbar {
            ToolbarItem {
                Button {
                    model.scanCleanup()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .disabled(model.cleanupPhase == .scanning || model.isCleaning)
            }
        }
        .sheet(isPresented: $model.isConfirmingCleanup) {
            CleanupConfirmation(model: model)
        }
    }
}

struct CleanupReportList: View {
    let report: RuleScanReport
    @Binding var selection: Set<String>
    let appName: (String) -> String

    var body: some View {
        List {
            Section {
                HStack(spacing: Spacing.l) {
                    SummaryTile(title: SafetyLevel.regenerable.title, symbol: SafetyLevel.regenerable.symbol,
                                tint: SafetyLevel.regenerable.tint, bytes: report.allocatedBytes(safety: .regenerable))
                    SummaryTile(title: SafetyLevel.review.title, symbol: SafetyLevel.review.symbol,
                                tint: SafetyLevel.review.tint, bytes: report.allocatedBytes(safety: .review))
                }
                .padding(.vertical, Spacing.s)
            }
            ForEach([SafetyLevel.regenerable, .review, .expert], id: \.self) { level in
                let groups = report.groups.filter { $0.rule.safety.level == level }
                if !groups.isEmpty {
                    Section(level.title) {
                        ForEach(groups) { CleanupGroupRow(group: $0, selection: $selection, appName: appName) }
                    }
                }
            }
            Section {
                Text("Items that rebuild automatically start selected. Items that need review are never selected for you, and always go to the Trash.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The floating bar with the current selection and the Clean button.
struct CleanupActionBar: View {
    @Bindable var model: AppModel

    var body: some View {
        let selected = model.selectedFindings
        let bytes = selected.reduce(UInt64(0)) { $0 &+ $1.size.allocated }
        HStack(spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selected.isEmpty ? "Nothing selected" : "\(selected.count.formatted()) item\(selected.count == 1 ? "" : "s") selected")
                    .font(.headline)
                if !selected.isEmpty {
                    SizeText(bytes)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.isConfirmingCleanup = true
            } label: {
                Label("Clean…", systemImage: "sparkles")
                    .padding(.horizontal, Spacing.s)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .disabled(selected.isEmpty || model.isCleaning)
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .glassPanel(cornerRadius: Radius.panel)
        .animation(Motion.snappy, value: model.cleanupSelection)
    }
}

/// What will happen, grouped by destination, before anything is removed.
struct CleanupConfirmation: View {
    @Bindable var model: AppModel

    var body: some View {
        let selected = model.selectedFindings
        let deleted = selected.filter { model.deleteRegenerable && $0.safety == .regenerable }
        let trashed = selected.filter { !(model.deleteRegenerable && $0.safety == .regenerable) }
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Clean \(selected.count.formatted()) item\(selected.count == 1 ? "" : "s")?")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: Spacing.m) {
                DestinationRow(symbol: "arrow.clockwise", tint: Palette.rebuildsAutomatically,
                               title: "Deleted permanently", detail: "They rebuild automatically.", findings: deleted)
                DestinationRow(symbol: "trash", tint: Palette.review,
                               title: "Moved to the Trash", detail: "You can put them back from History.", findings: trashed)
            }
            Toggle("Skip the Trash for items that rebuild automatically", isOn: $model.deleteRegenerable)
            if !model.appsBlockingSelection.isEmpty {
                Label("Quit \(model.appsBlockingSelection.joined(separator: " and ")) first, or their items are skipped.",
                      systemImage: "app.badge.checkmark")
                    .foregroundStyle(Palette.expert)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.isConfirmingCleanup = false }
                    .keyboardShortcut(.cancelAction)
                Button("Clean") { model.cleanSelected() }
                    .prominentActionStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
    }
}

struct DestinationRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let findings: [Finding]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                SizeText(findings.reduce(UInt64(0)) { $0 &+ $1.size.allocated })
                    .font(.headline)
                Text("\(findings.count.formatted()) item\(findings.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(findings.isEmpty ? 0.45 : 1)
    }
}

struct CleaningProgressView: View {
    let progress: CleanupExecutor.Progress?

    var body: some View {
        VStack(spacing: Spacing.m) {
            if let progress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .frame(width: 260)
                Text("Cleaning \(progress.completed.formatted()) of \(progress.total.formatted())…")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                ProgressView()
                Text("Cleaning…")
            }
        }
        .padding(Spacing.xl)
        .glassPanel()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.08))
    }
}

struct SummaryTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let bytes: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
            SizeText(bytes)
                .font(.rakerMetric)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .surfaceCard()
    }
}

struct CleanupGroupRow: View {
    let group: RuleFindingGroup
    @Binding var selection: Set<String>
    let appName: (String) -> String

    var body: some View {
        DisclosureGroup {
            ForEach(group.findings) { FindingRow(finding: $0, selection: $selection) }
        } label: {
            HStack(alignment: .top, spacing: Spacing.s) {
                groupCheckbox
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.rule.title)
                            .font(.headline)
                        Text("\(group.findings.count.formatted()) item\(group.findings.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        SizeText(group.allocatedBytes)
                    }
                    Text(group.rule.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("If removed: \(group.rule.ifRemoved)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if group.reclaimableBytes < group.allocatedBytes / 10 * 9 {
                        Label("Frees about \(ByteCount(group.reclaimableBytes).formatted): the rest is shared with other files.",
                              systemImage: "square.on.square.dashed")
                            .font(.caption)
                            .foregroundStyle(Palette.expert)
                    }
                    if !quitApps.isEmpty {
                        Label("Quit \(quitApps.joined(separator: " and ")) first", systemImage: "app.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(Palette.review)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    /// Selects or clears the whole group; shows a dash when only some items are selected.
    private var groupCheckbox: some View {
        let ids = Set(group.findings.map(\.id))
        let chosen = ids.intersection(selection).count
        let symbol = chosen == 0 ? "square" : chosen == ids.count ? "checkmark.square.fill" : "minus.square.fill"
        return Button {
            if chosen == ids.count {
                selection.subtract(ids)
            } else {
                selection.formUnion(ids)
            }
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(chosen == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .font(.body)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chosen == ids.count ? "Deselect \(group.rule.title)" : "Select \(group.rule.title)")
    }

    private var quitApps: [String] {
        Set(group.findings.flatMap(\.constraints).compactMap { constraint -> String? in
            if case .requiresQuit(let bundleID) = constraint { return appName(bundleID) }
            return nil
        }).sorted()
    }
}

struct FindingRow: View {
    let finding: Finding
    @Binding var selection: Set<String>

    var body: some View {
        HStack(spacing: Spacing.s) {
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                Text(abbreviated(path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isOrphan {
                Text("No installed app")
                    .font(.caption2)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Capsule().fill(.quaternary))
            }
            SizeText(finding.size.allocated)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private var path: String {
        if case .file(let ref) = finding.subject { return ref.path }
        return ""
    }

    private var title: String {
        for evidence in finding.evidence {
            if case .owner(let name, _) = evidence { return name }
        }
        return Paths.lastComponent(path)
    }

    private var isOrphan: Bool {
        finding.evidence.contains { if case .ownerNotInstalled = $0 { true } else { false } }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

extension SafetyLevel {
    var title: String {
        switch self {
        case .regenerable: "Rebuilds automatically"
        case .review: "Needs your review"
        case .expert: "Expert"
        }
    }

    var symbol: String {
        switch self {
        case .regenerable: "arrow.clockwise"
        case .review: "eye"
        case .expert: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .regenerable: Palette.rebuildsAutomatically
        case .review: Palette.review
        case .expert: Palette.expert
        }
    }
}

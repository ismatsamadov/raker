import AppKit
import DesignSystem
import RakerFoundation
import RakerModel
import RuleEngine
import ScanEngine
import SwiftUI

/// Caches, temporary files and logs: what each item is and whether it rebuilds itself.
struct CleanupView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.cleanupPhase {
            case .idle:
                ContentUnavailableView {
                    Label("Caches, temporary files and logs", systemImage: "sparkles")
                } description: {
                    Text("See what apps and tools leave behind, what each item is, and whether it rebuilds itself. Nothing is removed.")
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
                    CleanupReportList(report: report, appName: model.appName(for:))
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
                .disabled(model.cleanupPhase == .scanning)
            }
        }
    }
}

struct CleanupReportList: View {
    let report: RuleScanReport
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
                        ForEach(groups) { CleanupGroupRow(group: $0, appName: appName) }
                    }
                }
            }
            Section {
                Text("Nothing has been removed. Cleaning comes next: items will go to the Trash first, with a receipt you can undo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
    let appName: (String) -> String

    var body: some View {
        DisclosureGroup {
            ForEach(group.findings) { FindingRow(finding: $0) }
        } label: {
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
            .padding(.vertical, Spacing.xs)
        }
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

    var body: some View {
        HStack(spacing: Spacing.s) {
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

import DesignSystem
import RakerFoundation
import ScanEngine
import SpaceIndex
import SwiftUI
import UniformTypeIdentifiers
import VisualizationKit

/// The live disk ring for the current scope, with what's inside it.
struct OverviewView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                HStack(alignment: .center, spacing: Spacing.hero) {
                    ring
                        .frame(width: 300, height: 300)
                    legend
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                cards
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .principal) {
                scopePicker
            }
        }
        .fileImporter(isPresented: $model.isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.scope = .folder(url)
                model.startScan()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.volumeName)
                    .font(.title2.weight(.semibold))
                if let volume = model.volume {
                    HStack(spacing: Spacing.xs) {
                        SizeText(volume.availableIncludingPurgeable)
                        Text("available of")
                        SizeText(volume.total)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                withAnimation(Motion.snappy) { model.toggleScan() }
            } label: {
                Label(model.isScanning ? "Stop" : "Scan \(model.scope.title)",
                      systemImage: model.isScanning ? "stop.fill" : "sparkle.magnifyingglass")
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.horizontal, Spacing.xs)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var scopePicker: some View {
        Menu {
            Button("Downloads") { choose(.downloads) }
            Button("Home Folder") { choose(.home) }
            Divider()
            Button("Choose Folder…") { model.isChoosingFolder = true }
        } label: {
            Label(model.scope.title, systemImage: "folder")
        }
        .help("Choose what to scan")
    }

    private func choose(_ scope: ScanScopeChoice) {
        model.scope = scope
        model.startScan()
    }

    // MARK: Ring

    @ViewBuilder
    private var ring: some View {
        switch model.phase {
        case .scanning:
            ScanningRingView {
                VStack(spacing: Spacing.xs) {
                    SizeText(model.progress?.counters.allocatedBytes ?? 0)
                        .font(.rakerMetric)
                    Text("\((model.progress?.counters.items ?? 0).formatted()) items")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .animation(Motion.snappy, value: model.progress)
            }
        case .finished:
            DiskRingView(segments: segments) {
                VStack(spacing: Spacing.xxs) {
                    SizeText(model.report.map { $0.tree.allocatedSize(of: $0.tree.root) } ?? 0)
                        .font(.rakerHero)
                    Text("in \(model.scope.title)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        case .idle, .failed:
            DiskRingView(segments: []) {
                VStack(spacing: Spacing.s) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tint)
                    Text("Ready to scan")
                        .font(.headline)
                }
            }
        }
    }

    private var sortedKinds: [(kind: StorageKind, bytes: UInt64)] {
        model.breakdown
            .filter { $0.value > 0 }
            .map { (kind: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    private var segments: [RingSegment] {
        sortedKinds.map {
            .init(id: $0.kind.rawValue, value: Double($0.bytes), color: $0.kind.color,
                  label: "\($0.kind.title), \(ByteCount($0.bytes).formatted)")
        }
    }

    // MARK: Legend

    @ViewBuilder
    private var legend: some View {
        switch model.phase {
        case .finished:
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(sortedKinds, id: \.kind) { entry in
                    HStack(spacing: Spacing.m) {
                        Image(systemName: entry.kind.symbol)
                            .foregroundStyle(entry.kind.color)
                            .frame(width: 22)
                        Text(entry.kind.title)
                        Spacer(minLength: Spacing.l)
                        SizeText(entry.bytes)
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                }
            }
            .frame(maxWidth: 360)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        case .scanning:
            explainer(title: "Scanning \(model.scope.title)",
                      text: "Sizes appear as Raker reads each folder. Nothing is changed or removed.")
        case .idle:
            explainer(title: "See what's taking up space",
                      text: "Raker reads file sizes only, on this Mac. Start with Downloads, or choose any folder from the toolbar.")
        case .failed(let message):
            if model.scope == .downloads, model.access[.downloads] == .denied {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    explainer(title: "Raker can't open Downloads",
                              text: "macOS asked whether Raker may open Downloads, and the answer was no. You can change it in System Settings › Privacy & Security › Files & Folders.")
                    Button("Open Privacy Settings") { PrivacySettings.open(.filesAndFolders) }
                }
            } else {
                explainer(title: "Couldn't scan \(model.scope.title)", text: message)
            }
        }
    }

    private func explainer(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).font(.title3.weight(.semibold))
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    // MARK: Cards

    @ViewBuilder
    private var cards: some View {
        if model.phase == .finished, let report = model.report {
            let tree = report.tree
            HStack(alignment: .top, spacing: Spacing.l) {
                if let folder = tree.largestChildren(of: tree.root, limit: 1).first {
                    InsightCard(title: "Largest item", symbol: "arrow.up.right.circle", tint: Palette.installers,
                                value: ByteCount(tree.allocatedSize(of: folder)).formatted,
                                detail: tree.name(of: folder))
                }
                if let file = tree.largestFiles(limit: 1).first {
                    InsightCard(title: "Largest file", symbol: "doc.circle", tint: Palette.documents,
                                value: ByteCount(tree.allocatedSize(of: file)).formatted,
                                detail: tree.name(of: file))
                }
                InsightCard(title: "Items scanned", symbol: "checklist", tint: Palette.rebuildsAutomatically,
                            value: tree.descendantCount(of: tree.root).formatted(),
                            detail: "in \(report.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))")
                if report.skipped.isEmpty {
                    InsightCard(title: "Everything readable", symbol: "lock.open", tint: Palette.rebuildsAutomatically,
                                value: "0", detail: "No locations were skipped")
                } else {
                    Button {
                        model.isShowingSkipped = true
                    } label: {
                        InsightCard(title: "Skipped", symbol: "lock", tint: Palette.expert,
                                    value: report.skipped.count.formatted(), detail: "locations Raker couldn't read · Details")
                    }
                    .buttonStyle(.plain)
                    .help("See what Raker couldn't read, and how to allow it")
                    .popover(isPresented: $model.isShowingSkipped, arrowEdge: .bottom) {
                        SkippedLocationsView(model: model, locations: report.skipped) { model.isShowingSkipped = false }
                    }
                }
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }
}

struct InsightCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.rakerMetric)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(Spacing.l)
        .surfaceCard()
    }
}

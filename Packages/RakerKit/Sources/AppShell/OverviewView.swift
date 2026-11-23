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
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack {
                        Label("Folder breakdown", systemImage: "chart.pie")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        scanButton
                    }
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.xxl) {
                            dial
                            legend.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(spacing: Spacing.l) {
                            dial
                            legend
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(Spacing.xl)
                .surfaceCard(cornerRadius: Radius.panel)
                cards
            }
            .padding(Spacing.xl)
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
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label(model.volumeName, systemImage: "internaldrive.fill")
                .font(.headline)
                .foregroundStyle(Palette.lichen)
            if let volume = model.volume {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    SizeText(volume.availableIncludingPurgeable)
                        .font(.rakerHero)
                    Text("available").font(.title3)
                }
                .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    let used = volume.total - min(volume.total, volume.availableIncludingPurgeable)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.20))
                            Capsule().fill(Palette.lichen)
                                .frame(width: proxy.size.width * (volume.total > 0 ? Double(used) / Double(volume.total) : 0))
                        }
                    }
                    .frame(maxWidth: 300)
                    .frame(height: 5)
                    .accessibilityHidden(true)
                    Text("\(ByteCount(used).formatted) used of \(ByteCount(volume.total).formatted)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.83))
                }
            } else {
                Text("Volume capacity unavailable")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .leading)
        .background {
            ZStack {
                Palette.forest
                Terrain(ink: Palette.lichen, center: UnitPoint(x: 0.86, y: 0.38))
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.32),
                                                 .init(color: .black, location: 0.74)],
                                         startPoint: .leading, endPoint: .trailing))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
    }

    private var scanButton: some View {
        Button {
            withAnimation(Motion.snappy) { model.toggleScan() }
        } label: {
            Label(model.isScanning ? "Stop" : "Scan \(model.scope.title)",
                  systemImage: model.isScanning ? "stop.fill" : "viewfinder")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .prominentActionStyle()
        .controlSize(.large)
        .keyboardShortcut("r", modifiers: .command)
    }

    private var dial: some View {
        ring
            .padding(10)
            .background {
                Circle().strokeBorder(Palette.rule, style: StrokeStyle(lineWidth: 3, dash: [1, 7]))
                    .accessibilityHidden(true)
            }
            .frame(width: 218, height: 218)
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
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        // The ring's hole is 146 points across; a total such as 123.45 GB
                        // would reach the arcs at full size.
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 136)
                    Text("in \(model.scope.title)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 130)
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
                if sortedKinds.isEmpty {
                    explainer(title: "No measurable files", text: "This folder has no file sizes to chart.")
                }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
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
                    InsightCard(title: "Skipped locations", symbol: "lock.open", tint: Palette.rebuildsAutomatically,
                                value: "0", detail: "All locations were readable")
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
            HStack(spacing: Spacing.s) {
                SymbolTile(symbol, tint: tint, size: 26)
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text(value)
                .font(.rakerMetric)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Two lines even for a short detail, so cards in a row match in height.
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(Spacing.l)
        .surfaceCard()
    }
}

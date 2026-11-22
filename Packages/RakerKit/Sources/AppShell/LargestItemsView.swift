import AppKit
import DesignSystem
import FileSystemKit
import QuickLook
import RakerFoundation
import SpaceIndex
import SwiftUI
import VisualizationKit

/// The size tree as a ranked, drillable list.
struct LargestItemsView: View {
    @Bindable var model: AppModel

    struct Row: Identifiable {
        let id: SizeTree.Index
        let name: String
        let path: String
        let isFolder: Bool
        let bytes: UInt64
        let fraction: Double
        let items: Int
        let modified: Date
    }

    var body: some View {
        Group {
            if let tree = model.report?.tree {
                content(tree: tree, folder: model.browsedIndex ?? tree.root)
            } else {
                FolderScanPrompt(section: .largest, detail: "Scan a folder to see what's taking up space, largest first.", model: model)
            }
        }
        .navigationTitle("Largest Items")
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $model.largestMode) {
                    Label("List", systemImage: "list.bullet").tag(AppModel.LargestMode.list)
                    Label("Space Lens", systemImage: "circle.circle").tag(AppModel.LargestMode.lens)
                }
                .pickerStyle(.segmented)
                .help("Show the folder as a list or as Space Lens (⌘L)")
                .disabled(model.report == nil)
            }
            if model.largestMode == .lens {
                ToolbarItem {
                    Picker("Color", selection: $model.lensColoring) {
                        Text("By Folder").tag(AppModel.LensColoring.folder)
                        Text("By Age").tag(AppModel.LensColoring.age)
                    }
                    .help("Color segments by top-level folder, or by how long ago they changed")
                }
            }
        }
    }

    private func content(tree: SizeTree, folder: SizeTree.Index) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumbs(tree: tree, folder: folder)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .background(Palette.paper)
            Divider()
            switch model.largestMode {
            case .list:
                table(tree: tree, folder: folder)
            case .lens:
                lens(tree: tree, folder: folder)
            }
        }
    }

    private func table(tree: SizeTree, folder: SizeTree.Index) -> some View {
        let rows = makeRows(tree: tree, folder: folder)
        return Table(rows, selection: $model.largestSelection) {
            TableColumn("Name") { row in
                HStack(spacing: Spacing.s) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: row.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if model.tray.contains("largest:\(row.path)") {
                        Image(systemName: "tray.full.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .help("In the Tray")
                    }
                }
            }
            .width(min: 220, ideal: 360)
            TableColumn("Size") { row in
                HStack(spacing: Spacing.s) {
                    SizeBar(fraction: row.fraction, tint: row.isFolder ? Palette.documents : Palette.installers)
                        .frame(width: 70)
                    SizeText(row.bytes)
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }
            .width(min: 150, ideal: 170)
            TableColumn("Items") { row in
                Text(row.isFolder ? row.items.formatted() : "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Modified") { row in
                Text(row.modified, format: .dateTime.year().month(.abbreviated).day())
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: SizeTree.Index.self) { indices in
            Button("Reveal in Finder") { reveal(indices, in: tree) }
            Button("Quick Look") { preview(indices.first, in: tree) }
            Divider()
            let staged = !indices.isEmpty && indices.allSatisfy { model.tray.contains("largest:\(tree.path(of: $0))") }
            Button(staged ? "Take Out of the Tray" : "Add to Tray") { model.setStaged(indices, !staged) }
                .disabled(indices.isEmpty)
            Button("Never Suggest This") {
                for index in indices { model.addUserRule(.exclude, for: tree.path(of: index)) }
            }
        } primaryAction: { indices in
            guard let index = indices.first else { return }
            if tree.kind(of: index) == .directory {
                open(index)
            } else {
                preview(index, in: tree)
            }
        }
        .environment(\.defaultMinListRowHeight, 32)
        .reviewKeyboard(model)
    }

    // MARK: Space Lens

    private func lens(tree: SizeTree, folder: SizeTree.Index) -> some View {
        let total = max(Double(tree.allocatedSize(of: folder)), 1)
        return VStack(spacing: Spacing.m) {
            SunburstView(
                segments: model.lensSegments,
                highlighted: model.lensHighlight,
                color: { color(for: $0, tree: tree) },
                label: { label(for: $0, tree: tree, total: total) },
                onHover: { model.lensHovered = $0 },
                onSelect: { select($0, tree: tree) }
            ) {
                lensCenter(tree: tree, folder: folder)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.l)
            caption(tree: tree, total: total)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .surfaceCard()
            if model.lensColoring == .age {
                ageLegend
            }
        }
        .padding(.bottom, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lensCenter(tree: SizeTree, folder: SizeTree.Index) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(name(of: folder, in: tree))
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            SizeText(tree.allocatedSize(of: folder))
                .font(.rakerMetric)
            if folder != tree.root {
                Label("Up", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Circle())
        .onTapGesture {
            if let parent = tree.parent(of: folder) { open(parent) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(folder == tree.root ? [] : .isButton)
        .accessibilityHint(folder == tree.root ? "" : "Goes up one folder")
    }

    /// What's under the pointer, or how to use the lens.
    @ViewBuilder
    private func caption(tree: SizeTree, total: Double) -> some View {
        switch model.lensHovered {
        case .item(let index):
            HStack(spacing: Spacing.s) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: tree.path(of: index)))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(tree.name(of: index))
                    .font(.headline)
                    .lineLimit(1)
                SizeText(tree.allocatedSize(of: index))
                    .foregroundStyle(.secondary)
                Text(percent(Double(tree.allocatedSize(of: index)), of: total))
                    .foregroundStyle(.secondary)
            }
        case .smaller(let parent):
            let shown = Set(model.lensSegments.compactMap { if case .item(let index) = $0.key { index } else { nil } })
            let hidden = tree.children(of: parent).filter { !shown.contains($0) }
            Text("\(hidden.count.formatted()) smaller items in \(name(of: parent, in: tree))")
                .foregroundStyle(.secondary)
        case nil:
            Text("Click a folder to zoom in, a file to inspect it, and the center to go back up.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func select(_ segment: SunburstSegment<SizeTree.Index>, tree: SizeTree) {
        guard case .item(let index) = segment.key else { return }
        if tree.kind(of: index) == .directory, !tree.children(of: index).isEmpty {
            open(index)
        } else {
            model.largestSelection = [index]
        }
    }

    private func color(for segment: SunburstSegment<SizeTree.Index>, tree: SizeTree) -> Color {
        guard case .item(let index) = segment.key else { return Color.secondary.opacity(0.3) }
        switch model.lensColoring {
        case .folder:
            let palette = [Palette.documents, Palette.media, Palette.installers, Palette.developer,
                           Palette.archives, Palette.apps, Palette.caches, Palette.other]
            let base = palette[((segment.branch % palette.count) + palette.count) % palette.count]
            return base.opacity(1 - Double(segment.depth - 1) * 0.15)
        case .age:
            return AgeBand(date: tree.modificationDate(of: index)).color
        }
    }

    private func label(for segment: SunburstSegment<SizeTree.Index>, tree: SizeTree, total: Double) -> String {
        switch segment.key {
        case .item(let index):
            "\(tree.name(of: index)), \(ByteCount(tree.allocatedSize(of: index)).formatted), \(percent(segment.value, of: total))"
        case .smaller(let parent):
            "Smaller items in \(name(of: parent, in: tree)), \(ByteCount(UInt64(segment.value)).formatted)"
        }
    }

    private func percent(_ value: Double, of total: Double) -> String {
        (value / total).formatted(.percent.precision(.fractionLength(0 ... 1)))
    }

    private var ageLegend: some View {
        HStack(spacing: Spacing.l) {
            ForEach(AgeBand.allCases, id: \.self) { band in
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(band.color)
                        .frame(width: 8, height: 8)
                    Text(band.title)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func makeRows(tree: SizeTree, folder: SizeTree.Index) -> [Row] {
        let total = max(tree.allocatedSize(of: folder), 1)
        return tree.largestChildren(of: folder, limit: 500).map { index in
            let bytes = tree.allocatedSize(of: index)
            return Row(
                id: index,
                name: tree.name(of: index),
                path: tree.path(of: index),
                isFolder: tree.kind(of: index) == .directory,
                bytes: bytes,
                fraction: Double(bytes) / Double(total),
                items: tree.descendantCount(of: index),
                modified: tree.modificationDate(of: index)
            )
        }
    }

    private func breadcrumbs(tree: SizeTree, folder: SizeTree.Index) -> some View {
        var chain: [SizeTree.Index] = []
        var current: SizeTree.Index? = folder
        while let index = current {
            chain.insert(index, at: 0)
            current = tree.parent(of: index)
        }
        return HStack(spacing: Spacing.xs) {
            SymbolTile("folder", tint: Palette.lagoon, size: 28)
            ForEach(chain, id: \.self) { index in
                if index != tree.root {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button(name(of: index, in: tree)) {
                    open(index)
                }
                .buttonStyle(.plain)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(tree.path(of: index))
                .foregroundStyle(index == folder ? .primary : .secondary)
            }
            Spacer()
            SizeText(tree.allocatedSize(of: folder))
                .font(.headline.monospacedDigit())
                .fixedSize()
        }
        .font(.callout)
    }

    /// The scanned folder goes by its own name, not its full path.
    private func name(of index: SizeTree.Index, in tree: SizeTree) -> String {
        index == tree.root ? Paths.lastComponent(tree.rootPath) : tree.name(of: index)
    }

    private func open(_ index: SizeTree.Index) {
        model.largestSelection = []
        model.lensHovered = nil
        withAnimation(Motion.snappy) { model.browsedIndex = index }
    }

    private func preview(_ index: SizeTree.Index?, in tree: SizeTree) {
        guard let index else { return }
        model.previewURL = URL(fileURLWithPath: tree.path(of: index))
    }

    private func reveal(_ indices: Set<SizeTree.Index>, in tree: SizeTree) {
        let urls = indices.map { URL(fileURLWithPath: tree.path(of: $0)) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// How long ago something changed, in the Age lens's colors: recent data is warm, long
/// untouched data cool.
enum AgeBand: CaseIterable {
    case month
    case halfYear
    case year
    case threeYears
    case older

    init(date: Date, now: Date = .now) {
        let days = now.timeIntervalSince(date) / 86_400
        self = days < 31 ? .month : days < 183 ? .halfYear : days < 366 ? .year : days < 3 * 366 ? .threeYears : .older
    }

    var title: String {
        switch self {
        case .month: "This month"
        case .halfYear: "6 months"
        case .year: "A year"
        case .threeYears: "3 years"
        case .older: "Older"
        }
    }

    var color: Color {
        switch self {
        case .month: Palette.installers
        case .halfYear: Color(nsColor: .systemYellow)
        case .year: Palette.caches
        case .threeYears: Palette.documents
        case .older: Palette.apps
        }
    }
}

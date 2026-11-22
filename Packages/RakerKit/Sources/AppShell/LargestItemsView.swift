import AppKit
import DesignSystem
import FileSystemKit
import QuickLook
import RakerFoundation
import SpaceIndex
import SwiftUI

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
                ContentUnavailableView {
                    Label("No scan yet", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("Scan a folder to see what's taking up space, largest first.")
                } actions: {
                    Button("Scan \(model.scope.title)") { model.startScan() }
                        .prominentActionStyle()
                }
            }
        }
        .navigationTitle("Largest Items")
    }

    private func content(tree: SizeTree, folder: SizeTree.Index) -> some View {
        let rows = makeRows(tree: tree, folder: folder)
        return VStack(alignment: .leading, spacing: 0) {
            breadcrumbs(tree: tree, folder: folder)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
            Divider()
            Table(rows, selection: $model.largestSelection) {
                TableColumn("Name") { row in
                    HStack(spacing: Spacing.s) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: row.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
            } primaryAction: { indices in
                guard let index = indices.first else { return }
                if tree.kind(of: index) == .directory {
                    open(index)
                } else {
                    preview(index, in: tree)
                }
            }
            .onKeyPress(.space) {
                preview(model.largestSelection.first, in: tree)
                return .handled
            }
        }
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
            ForEach(chain, id: \.self) { index in
                if index != tree.root {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button(index == tree.root ? Paths.lastComponent(tree.rootPath) : tree.name(of: index)) {
                    open(index)
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == folder ? .primary : .secondary)
            }
            Spacer()
            SizeText(tree.allocatedSize(of: folder))
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func open(_ index: SizeTree.Index) {
        model.largestSelection = []
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

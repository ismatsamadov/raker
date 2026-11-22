import AppKit
import DesignSystem
import RakerFoundation
import RakerModel
import SwiftUI

/// Every cleanup: what moved where, how free space changed, and putting items back.
struct HistoryView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.receipts.isEmpty {
                WorkspaceState(title: "No cleanups yet", symbol: "clock.arrow.circlepath",
                               detail: "Every cleanup is recorded here: what was deleted, what went to the Trash, and how free space changed.", tint: Palette.lagoon)
            } else {
                List {
                    ForEach(model.receipts) { receipt in
                        Section {
                            ReceiptSummary(receipt: receipt, appName: model.appName(for:))
                                .padding(Spacing.l)
                                .surfaceCard()
                            DisclosureGroup("Items") {
                                ForEach(receipt.items) { ExecutedItemRow(item: $0) }
                            }
                            let restorable = receipt.items.filter(\.isRestorable).count
                            if restorable > 0 {
                                Button("Put Back \(restorable.formatted()) Item\(restorable == 1 ? "" : "s") from the Trash") {
                                    model.restore(receipt)
                                }
                            }
                        } header: {
                            Label(receipt.startedAt.formatted(date: .complete, time: .shortened), systemImage: "clock")
                                .font(.headline)
                                .padding(.vertical, Spacing.xs)
                        }
                    }
                }
            }
        }
        .navigationTitle("Receipts")
        .toolbar {
            ToolbarItem {
                Button {
                    model.refreshHistory()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { model.refreshHistory() }
    }
}

struct ExecutedItemRow: View {
    let item: ExecutedItem

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(Paths.lastComponent(item.path))
                Text(abbreviated(item.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            SizeText(item.size.allocated)
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
    }

    private var symbol: String {
        if item.restoredAt != nil { return "arrow.uturn.backward" }
        switch item.outcome {
        case .deleted: return "checkmark.circle"
        case .movedToTrash: return "trash"
        case .skipped: return "forward"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch item.outcome {
        case .deleted: Palette.rebuildsAutomatically
        case .movedToTrash: Palette.review
        case .skipped: .secondary
        case .failed: Palette.expert
        }
    }

    private var status: String {
        if item.restoredAt != nil { return "Put back" }
        switch item.outcome {
        case .deleted: return "Deleted"
        case .movedToTrash: return "In the Trash"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

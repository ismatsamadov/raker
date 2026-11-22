import DesignSystem
import RakerFoundation
import RakerModel
import SwiftUI

/// The receipt shown right after a cleanup.
struct ReceiptView: View {
    let receipt: CleanupReceipt
    let appName: (String) -> String
    let onRestore: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Palette.rebuildsAutomatically)
                    .symbolEffect(.bounce, value: receipt.id)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Cleanup receipt")
                        .font(.title2.weight(.semibold))
                    Text(receipt.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            ReceiptSummary(receipt: receipt, appName: appName)
            Text("Free space can grow further after the Trash is emptied, and local snapshots can delay part of the gain.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                let restorable = receipt.items.filter(\.isRestorable).count
                if restorable > 0 {
                    Button("Put Back \(restorable.formatted()) Item\(restorable == 1 ? "" : "s")", action: onRestore)
                }
                Spacer()
                Button("Done", action: onDone)
                    .prominentActionStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 480)
    }
}

/// Totals, reasons and the observed change in free space for one cleanup.
struct ReceiptSummary: View {
    let receipt: CleanupReceipt
    let appName: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            row("Deleted", symbol: "arrow.clockwise", tint: Palette.rebuildsAutomatically, total: receipt.deleted)
            row("Moved to the Trash", symbol: "trash", tint: Palette.review, total: receipt.movedToTrash)
            row("Skipped", symbol: "forward", tint: .secondary, total: receipt.skipped)
            row("Failed", symbol: "exclamationmark.triangle", tint: Palette.expert, total: receipt.failed)
            ForEach(reasons, id: \.text) { reason in
                Text("\(reason.count.formatted()) item\(reason.count == 1 ? "" : "s"): \(reason.text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
            }
            if let before = receipt.spaceBefore, let after = receipt.spaceAfter, let change = receipt.observedChange {
                Divider()
                HStack {
                    Label("Free space", systemImage: "internaldrive")
                    Spacer()
                    SizeText(before.free)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SizeText(after.free)
                    Text("(\(change >= 0 ? "+" : "−")\(ByteCount(change.magnitude).formatted) observed)")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private func row(_ title: String, symbol: String, tint: some ShapeStyle, total: CleanupReceipt.Total) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(tint)
            Spacer()
            Text("\(total.count.formatted()) item\(total.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            SizeText(total.bytes)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .opacity(total.count == 0 ? 0.5 : 1)
    }

    /// Why items were skipped or failed, most common first.
    private var reasons: [(text: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in receipt.items {
            switch item.outcome {
            case .skipped(let reason): counts[describe(reason), default: 0] += 1
            case .failed(let reason): counts[describe(reason), default: 0] += 1
            case .movedToTrash, .deleted: continue
            }
        }
        return counts.map { (text: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    private func describe(_ reason: SkipReason) -> String {
        switch reason {
        case .changedSinceScan: "changed since the scan"
        case .missing: "already gone"
        case .protected: "protected by the safety policy"
        case .appRunning(let bundleID): "skipped while \(appName(bundleID)) is open"
        case .synced: "synced with iCloud or another provider, so removing it here would remove it everywhere"
        case .unsupported: "not supported yet"
        }
    }

    private func describe(_ reason: FailureReason) -> String {
        switch reason {
        case .permissionDenied: "no permission"
        case .locked: "locked"
        case .crossesVolume: "part of it is on another volume"
        case .trashUnavailable: "couldn't be moved to the Trash"
        case .ioError(let code): "disk error \(code)"
        }
    }
}

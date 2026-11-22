import Darwin
import FileSystemKit
import Foundation
import Persistence
import RakerModel

/// Puts items back from the Trash, using the journal's record of where they came from.
public struct Restorer: Sendable {
    public enum Outcome: Sendable, Hashable {
        case restored
        /// The item didn't go to the Trash, or was already put back.
        case notRestorable
        /// The item is no longer in the Trash, for example because the Trash was emptied.
        case notInTrash
        /// Something else now exists at the original location; it is never replaced.
        case originalLocationTaken
        case failed(String)
    }

    private let trash: any TrashService
    private let journal: JournalStore?

    public init(trash: any TrashService = SystemTrash(), journal: JournalStore?) {
        self.trash = trash
        self.journal = journal
    }

    public func restore(_ item: ExecutedItem) -> Outcome {
        guard item.isRestorable, case .movedToTrash(let trashPath) = item.outcome else { return .notRestorable }
        guard Self.exists(trashPath) else { return .notInTrash }
        guard !Self.exists(item.path) else { return .originalLocationTaken }
        do {
            try trash.restore(trashPath, to: item.path)
        } catch {
            return .failed(error.localizedDescription)
        }
        try? journal?.markRestored(itemID: item.id, at: Date())
        return .restored
    }

    /// Restores every restorable item of a cleanup.
    public func restoreAll(in receipt: CleanupReceipt) -> [UUID: Outcome] {
        var outcomes: [UUID: Outcome] = [:]
        for item in receipt.items where item.isRestorable {
            outcomes[item.id] = restore(item)
        }
        return outcomes
    }

    /// Whether anything exists at a path, without following a final symlink.
    private static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}

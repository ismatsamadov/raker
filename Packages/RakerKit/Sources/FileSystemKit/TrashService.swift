import Foundation

/// Moves items to the Trash and back. Tests use a fake that moves items into a folder.
public protocol TrashService: Sendable {
    /// Moves an item to the Trash and returns its new path there.
    func moveToTrash(_ path: String) throws -> String

    /// Moves an item from the Trash back to where it was.
    func restore(_ trashedPath: String, to originalPath: String) throws
}

/// The user's Trash, through FileManager.
public struct SystemTrash: TrashService {
    public init() {}

    public func moveToTrash(_ path: String) throws -> String {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        return resulting?.path ?? path
    }

    public func restore(_ trashedPath: String, to originalPath: String) throws {
        let destination = URL(fileURLWithPath: originalPath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // moveItem refuses to overwrite, so an item now at the original path is never replaced.
        try FileManager.default.moveItem(at: URL(fileURLWithPath: trashedPath), to: destination)
    }
}

import Foundation
import RakerModel

/// Capacity and identity of the volume that holds a path.
public enum VolumeInfo {
    public static func space(containing path: String) throws -> VolumeSpace {
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
        let free = UInt64(max(0, values.volumeAvailableCapacity ?? 0))
        let important = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(free)))
        return VolumeSpace(total: total, free: free, availableIncludingPurgeable: max(important, free))
    }

    /// The volume's name as Finder shows it, such as "Macintosh HD".
    public static func name(containing path: String) -> String? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName
    }
}

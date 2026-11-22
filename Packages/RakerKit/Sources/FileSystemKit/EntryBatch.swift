/// The kind of a directory entry.
public enum EntryKind: UInt8, Sendable {
    case file
    case directory
    case symlink
    case other
}

/// Facts about an entry, from the filesystem and from later analysis.
public struct EntryFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// A directory where another volume is mounted.
    public static let mountPoint = EntryFlags(rawValue: 1 << 0)
    /// A cloud file whose content isn't on this Mac; reading it would download it.
    public static let dataless = EntryFlags(rawValue: 1 << 1)
    /// Transparently compressed by the filesystem.
    public static let compressed = EntryFlags(rawValue: 1 << 2)
    /// Hidden in Finder (flag set, or the name starts with a dot).
    public static let hidden = EntryFlags(rawValue: 1 << 3)
    /// A file with more than one hard link.
    public static let multiplyLinked = EntryFlags(rawValue: 1 << 4)
    public static let firmlink = EntryFlags(rawValue: 1 << 5)
    /// Locked with the user or system immutable flag.
    public static let immutable = EntryFlags(rawValue: 1 << 6)
    /// The APFS private size was reported, so reclaimable space is known exactly.
    public static let privateSizeKnown = EntryFlags(rawValue: 1 << 7)
    /// The filesystem returned an error for this entry's attributes.
    public static let attributeError = EntryFlags(rawValue: 1 << 8)
    /// Another hard link to the same file was already counted.
    public static let duplicateHardLink = EntryFlags(rawValue: 1 << 9)
    /// A directory that couldn't be opened or read completely.
    public static let unreadable = EntryFlags(rawValue: 1 << 10)
}

/// The entries of one directory, stored column by column so reading a directory
/// doesn't allocate per entry. Workers reuse one batch for every directory they read.
public struct EntryBatch: Sendable {
    public private(set) var nameBytes: [UInt8] = []
    public private(set) var nameOffsets: [UInt32] = []
    public private(set) var nameLengths: [UInt16] = []
    public private(set) var kinds: [EntryKind] = []
    public private(set) var flags: [EntryFlags] = []
    public private(set) var fileIDs: [UInt64] = []
    public private(set) var linkCounts: [UInt32] = []
    public private(set) var logicalSizes: [UInt64] = []
    public private(set) var allocatedSizes: [UInt64] = []
    /// Equal to the allocated size unless `.privateSizeKnown` is set.
    public private(set) var privateSizes: [UInt64] = []
    /// Seconds since 1970.
    public private(set) var modificationTimes: [Int64] = []

    public init() {}

    public var count: Int { kinds.count }

    public func name(at index: Int) -> String {
        let start = Int(nameOffsets[index])
        return String(decoding: nameBytes[start ..< start + Int(nameLengths[index])], as: UTF8.self)
    }

    /// The entry's name as raw UTF-8, without copying.
    public func nameUTF8(at index: Int) -> ArraySlice<UInt8> {
        let start = Int(nameOffsets[index])
        return nameBytes[start ..< start + Int(nameLengths[index])]
    }

    mutating func removeAll() {
        nameBytes.removeAll(keepingCapacity: true)
        nameOffsets.removeAll(keepingCapacity: true)
        nameLengths.removeAll(keepingCapacity: true)
        kinds.removeAll(keepingCapacity: true)
        flags.removeAll(keepingCapacity: true)
        fileIDs.removeAll(keepingCapacity: true)
        linkCounts.removeAll(keepingCapacity: true)
        logicalSizes.removeAll(keepingCapacity: true)
        allocatedSizes.removeAll(keepingCapacity: true)
        privateSizes.removeAll(keepingCapacity: true)
        modificationTimes.removeAll(keepingCapacity: true)
    }

    mutating func append(
        name: UnsafeRawBufferPointer,
        kind: EntryKind,
        flags entryFlags: EntryFlags,
        fileID: UInt64,
        linkCount: UInt32,
        logicalSize: UInt64,
        allocatedSize: UInt64,
        privateSize: UInt64,
        modificationTime: Int64
    ) {
        nameOffsets.append(UInt32(nameBytes.count))
        nameLengths.append(UInt16(clamping: name.count))
        nameBytes.append(contentsOf: name.prefix(Int(UInt16.max)))
        kinds.append(kind)
        flags.append(entryFlags)
        fileIDs.append(fileID)
        linkCounts.append(linkCount)
        logicalSizes.append(logicalSize)
        allocatedSizes.append(allocatedSize)
        privateSizes.append(privateSize)
        modificationTimes.append(modificationTime)
    }
}

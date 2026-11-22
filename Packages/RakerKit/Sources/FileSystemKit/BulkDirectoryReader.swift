import Darwin

/// Reads whole directories with `getattrlistbulk(2)`: one system call returns a batch of
/// entries with their names, types, sizes and identifiers, instead of one `stat` per file.
///
/// Each worker thread owns one reader; it isn't thread-safe.
final class BulkDirectoryReader {
    private let buffer: UnsafeMutableRawPointer
    private let capacity: Int
    /// Ask for APFS extended attributes (private size). Turned off for good if a volume
    /// rejects them.
    private var requestsExtendedAttributes = true

    init(capacity: Int = 256 * 1024) {
        self.capacity = capacity
        self.buffer = .allocate(byteCount: capacity, alignment: 16)
    }

    deinit {
        buffer.deallocate()
    }

    /// Appends every entry of the open directory `fd` to `batch`.
    /// - Returns: 0 on success, or an `errno` value if reading stopped early.
    func read(directory fd: Int32, into batch: inout EntryBatch) -> Int32 {
        var attributes = Self.attributeList(extended: requestsExtendedAttributes)
        while true {
            let options = requestsExtendedAttributes ? UInt64(FSOPT_ATTR_CMN_EXTENDED) : 0
            let count = getattrlistbulk(fd, &attributes, buffer, capacity, options)
            if count < 0 {
                let code = errno
                if code == EINTR { continue }
                if code == EINVAL, requestsExtendedAttributes, batch.count == 0 {
                    requestsExtendedAttributes = false
                    attributes = Self.attributeList(extended: false)
                    continue
                }
                return code
            }
            if count == 0 { return 0 }
            parse(entryCount: Int(count), into: &batch)
        }
    }

    private static func attributeList(extended: Bool) -> attrlist {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
        list.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
            | attrgroup_t(ATTR_FILE_DATALENGTH)
        // With FSOPT_ATTR_CMN_EXTENDED the fork group carries extended common attributes.
        list.forkattr = extended ? attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) : 0
        return list
    }

    /// Decodes `entryCount` packed entries from the buffer.
    ///
    /// Layout per entry: total length, the returned-attributes set, the error code, then the
    /// remaining common attributes in bit order, then directory, file and extended attributes.
    /// Only attributes listed in the returned set are present, and fields are not necessarily
    /// aligned, hence the unaligned loads.
    private func parse(entryCount: Int, into batch: inout EntryBatch) {
        var entry = UnsafeRawPointer(buffer)
        let end = entry + capacity
        for _ in 0 ..< entryCount {
            let length = Int(entry.loadUnaligned(as: UInt32.self))
            guard length > 0, entry + length <= end else { return }
            var field = entry + MemoryLayout<UInt32>.size
            let returned = field.loadUnaligned(as: attribute_set_t.self)
            field += MemoryLayout<attribute_set_t>.size

            func has(_ group: attrgroup_t, _ bit: Int32) -> Bool { group & attrgroup_t(bit) != 0 }
            func has(_ group: attrgroup_t, _ bit: UInt32) -> Bool { group & attrgroup_t(bit) != 0 }

            var flags: EntryFlags = []
            if has(returned.commonattr, ATTR_CMN_ERROR) {
                if field.loadUnaligned(as: UInt32.self) != 0 { flags.insert(.attributeError) }
                field += MemoryLayout<UInt32>.size
            }

            var name = UnsafeRawBufferPointer(start: nil, count: 0)
            if has(returned.commonattr, ATTR_CMN_NAME) {
                let reference = field.loadUnaligned(as: attrreference_t.self)
                // attr_length counts the terminating NUL.
                let nameLength = max(0, Int(reference.attr_length) - 1)
                name = UnsafeRawBufferPointer(start: field + Int(reference.attr_dataoffset), count: nameLength)
                field += MemoryLayout<attrreference_t>.size
            }

            var objectType: UInt32 = 0
            if has(returned.commonattr, ATTR_CMN_OBJTYPE) {
                objectType = field.loadUnaligned(as: UInt32.self)
                field += MemoryLayout<UInt32>.size
            }

            var modificationTime: Int64 = 0
            if has(returned.commonattr, ATTR_CMN_MODTIME) {
                modificationTime = Int64(field.loadUnaligned(as: timespec.self).tv_sec)
                field += MemoryLayout<timespec>.size
            }

            var statFlags: UInt32 = 0
            if has(returned.commonattr, ATTR_CMN_FLAGS) {
                statFlags = field.loadUnaligned(as: UInt32.self)
                field += MemoryLayout<UInt32>.size
            }

            var fileID: UInt64 = 0
            if has(returned.commonattr, ATTR_CMN_FILEID) {
                fileID = field.loadUnaligned(as: UInt64.self)
                field += MemoryLayout<UInt64>.size
            }

            if has(returned.dirattr, ATTR_DIR_MOUNTSTATUS) {
                if field.loadUnaligned(as: UInt32.self) & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0 {
                    flags.insert(.mountPoint)
                }
                field += MemoryLayout<UInt32>.size
            }

            var linkCount: UInt32 = 1
            if has(returned.fileattr, ATTR_FILE_LINKCOUNT) {
                linkCount = field.loadUnaligned(as: UInt32.self)
                field += MemoryLayout<UInt32>.size
            }

            var allocatedSize: UInt64 = 0
            if has(returned.fileattr, ATTR_FILE_ALLOCSIZE) {
                allocatedSize = UInt64(max(0, field.loadUnaligned(as: Int64.self)))
                field += MemoryLayout<Int64>.size
            }

            var logicalSize: UInt64 = 0
            if has(returned.fileattr, ATTR_FILE_DATALENGTH) {
                logicalSize = UInt64(max(0, field.loadUnaligned(as: Int64.self)))
                field += MemoryLayout<Int64>.size
            }

            var privateSize = allocatedSize
            if has(returned.forkattr, ATTR_CMNEXT_PRIVATESIZE) {
                privateSize = UInt64(max(0, field.loadUnaligned(as: Int64.self)))
                flags.insert(.privateSizeKnown)
                field += MemoryLayout<Int64>.size
            }

            let kind: EntryKind
            switch objectType {
            case UInt32(VREG.rawValue): kind = .file
            case UInt32(VDIR.rawValue): kind = .directory
            case UInt32(VLNK.rawValue): kind = .symlink
            default: kind = .other
            }

            if statFlags & UInt32(SF_DATALESS) != 0 { flags.insert(.dataless) }
            if statFlags & UInt32(UF_COMPRESSED) != 0 { flags.insert(.compressed) }
            if statFlags & UInt32(SF_FIRMLINK) != 0 { flags.insert(.firmlink) }
            if statFlags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0 { flags.insert(.immutable) }
            if statFlags & UInt32(UF_HIDDEN) != 0 || name.first == UInt8(ascii: ".") { flags.insert(.hidden) }
            if kind != .directory, linkCount > 1 { flags.insert(.multiplyLinked) }

            batch.append(
                name: name,
                kind: kind,
                flags: flags,
                fileID: fileID,
                linkCount: linkCount,
                logicalSize: logicalSize,
                allocatedSize: allocatedSize,
                privateSize: privateSize,
                modificationTime: modificationTime
            )
            entry += length
        }
    }
}

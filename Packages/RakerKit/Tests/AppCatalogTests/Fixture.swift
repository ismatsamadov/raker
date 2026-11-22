import Foundation

/// A temporary folder standing in for Applications folders and a home folder.
struct Fixture {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("raker-apps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        path = base.resolvingSymlinksInPath().path
    }

    func app(_ relative: String, bundleID: String, name: String? = nil, version: String = "1.0",
             executable: [UInt8]? = nil, receipt: Bool = false) throws {
        let contents = path + "/" + relative + "/Contents"
        try FileManager.default.createDirectory(atPath: contents + "/MacOS", withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version,
                                    "CFBundleExecutable": "main"]
        if let name { plist["CFBundleName"] = name }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: contents + "/Info.plist"))
        if let executable {
            try Data(executable).write(to: URL(fileURLWithPath: contents + "/MacOS/main"))
        }
        if receipt {
            try FileManager.default.createDirectory(atPath: contents + "/_MASReceipt", withIntermediateDirectories: true)
            try Data([1]).write(to: URL(fileURLWithPath: contents + "/_MASReceipt/receipt"))
        }
    }

    func item(_ relative: String) throws {
        let url = URL(fileURLWithPath: path + "/" + relative)
        if relative.hasSuffix(".plist") || relative.hasSuffix(".binarycookies") {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 1_000).write(to: url.appendingPathComponent("data"))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Mach-O headers: a universal binary with two slices, and single slices.
let universalHeader: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2,
                                        0x01, 0, 0, 0x07, 0, 0, 0, 3, 0, 0, 0x10, 0, 0, 0, 0x10, 0, 0, 0, 0, 12,
                                        0x01, 0, 0, 0x0C, 0, 0, 0, 0, 0, 0, 0x20, 0, 0, 0, 0x10, 0, 0, 0, 0, 14]
let armHeader: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0, 0, 0x01, 0, 0, 0, 0]
let intelHeader: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x07, 0, 0, 0x01, 3, 0, 0, 0]

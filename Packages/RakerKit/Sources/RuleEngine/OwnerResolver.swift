import RakerModel

/// Who a folder belongs to, worked out from its name.
public struct Owner: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// An installed app uses this bundle ID.
        case installed
        /// Named like an app, but no installed app uses the name. Possibly left behind by an
        /// app that was removed; possibly a helper or library. Never assumed safe.
        case notInstalled
        /// Part of macOS or an Apple service.
        case system
        /// Not named after an app; the name is all we know.
        case unknown
    }

    public var name: String
    public var bundleID: String?
    public var status: Status

    public init(name: String, bundleID: String?, status: Status) {
        self.name = name
        self.bundleID = bundleID
        self.status = status
    }
}

/// Maps folder names such as "com.spotify.client" to the app that owns them.
public struct OwnerResolver: Sendable {
    private let apps: any AppDirectory

    public init(apps: any AppDirectory) {
        self.apps = apps
    }

    public func owner(ofFolderNamed name: String) -> Owner {
        guard Self.looksLikeBundleID(name) else {
            return Owner(name: name, bundleID: nil, status: .unknown)
        }
        // Helpers and sub-caches extend the app's ID: com.google.Chrome.code_sign_clone
        // belongs to com.google.Chrome.
        var components = name.split(separator: ".")
        while components.count >= 2 {
            let candidate = components.joined(separator: ".")
            if let app = apps.installedApp(bundleID: candidate) {
                return Owner(name: app.name, bundleID: candidate, status: .installed)
            }
            components.removeLast()
        }
        if name.lowercased().hasPrefix("com.apple.") {
            return Owner(name: "macOS", bundleID: name, status: .system)
        }
        return Owner(name: name, bundleID: name, status: .notInstalled)
    }

    /// Reverse-DNS names with at least three parts, such as com.vendor.App. Version-like
    /// names such as "v1.2.3" don't count.
    public static func looksLikeBundleID(_ name: String) -> Bool {
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3,
              let first = components.first, (2 ... 6).contains(first.count), first.allSatisfy(\.isLetter),
              components[1].first?.isLetter == true
        else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}

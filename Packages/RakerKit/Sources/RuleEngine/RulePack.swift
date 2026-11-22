import RakerModel

/// A versioned set of cleanup rules.
///
/// Packs are data: they describe locations and explain them, but they can't run commands,
/// and every location they match is checked against the safety policy before use.
public struct RulePack: Codable, Sendable {
    public var schema: Int
    public var version: String
    /// Evaluated in order; the first rule that claims an item wins, so specific rules come
    /// before generic ones.
    public var rules: [Rule]
    /// Descriptions of well-known locations, used to explain items no rule removes.
    public var locations: [KnownLocation]
    /// Rules switched off by ID, so a misbehaving rule can be disabled without an app release.
    public var disabledRules: [String]

    public static let supportedSchema = 1

    public init(schema: Int = supportedSchema, version: String, rules: [Rule], locations: [KnownLocation] = [], disabledRules: [String] = []) {
        self.schema = schema
        self.version = version
        self.rules = rules
        self.locations = locations
        self.disabledRules = disabledRules
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        version = try container.decode(String.self, forKey: .version)
        rules = try container.decode([Rule].self, forKey: .rules)
        locations = try container.decodeIfPresent([KnownLocation].self, forKey: .locations) ?? []
        disabledRules = try container.decodeIfPresent([String].self, forKey: .disabledRules) ?? []
    }

    /// Rules that aren't disabled, in evaluation order.
    public var activeRules: [Rule] {
        let disabled = Set(disabledRules)
        return rules.filter { !disabled.contains($0.id) }
    }
}

public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    /// What the item is, in one or two plain sentences.
    public var explanation: String
    /// What happens if it's removed.
    public var ifRemoved: String
    /// A dotted category such as "caches.browsers".
    public var category: String
    public var safety: RuleSafety
    public var targets: [RuleTarget]
    /// Apps that use this data, so Raker can ask to quit them first.
    public var appBundleIDs: [String]
    public var whileRunning: RunningPolicy
    /// Report each matched item separately, labeled with the app or tool that owns it.
    public var identifiesOwners: Bool

    public init(
        id: String,
        title: String,
        explanation: String,
        ifRemoved: String,
        category: String,
        safety: RuleSafety,
        targets: [RuleTarget],
        appBundleIDs: [String] = [],
        whileRunning: RunningPolicy = .allow,
        identifiesOwners: Bool = false
    ) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.ifRemoved = ifRemoved
        self.category = category
        self.safety = safety
        self.targets = targets
        self.appBundleIDs = appBundleIDs
        self.whileRunning = whileRunning
        self.identifiesOwners = identifiesOwners
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        explanation = try container.decode(String.self, forKey: .explanation)
        ifRemoved = try container.decode(String.self, forKey: .ifRemoved)
        category = try container.decode(String.self, forKey: .category)
        safety = try container.decode(RuleSafety.self, forKey: .safety)
        targets = try container.decode([RuleTarget].self, forKey: .targets)
        appBundleIDs = try container.decodeIfPresent([String].self, forKey: .appBundleIDs) ?? []
        whileRunning = try container.decodeIfPresent(RunningPolicy.self, forKey: .whileRunning) ?? .allow
        identifiesOwners = try container.decodeIfPresent(Bool.self, forKey: .identifiesOwners) ?? false
    }
}

public struct RuleTarget: Codable, Sendable, Hashable {
    /// An absolute path, or one starting with `~` or `$VARIABLE` (see `PathEnvironment`).
    /// `*`, `?` and `[...]` match within a single path component.
    public var path: String
    public var scope: TargetScope
    /// Only items untouched for this many days, judged by their newest file.
    public var olderThanDays: Int?
    /// Names to skip, as patterns.
    public var exclude: [String]
    /// Only items the current user owns, for folders shared between users.
    public var onlyOwnedByUser: Bool

    public init(path: String, scope: TargetScope, olderThanDays: Int? = nil, exclude: [String] = [], onlyOwnedByUser: Bool = false) {
        self.path = path
        self.scope = scope
        self.olderThanDays = olderThanDays
        self.exclude = exclude
        self.onlyOwnedByUser = onlyOwnedByUser
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        scope = try container.decode(TargetScope.self, forKey: .scope)
        olderThanDays = try container.decodeIfPresent(Int.self, forKey: .olderThanDays)
        exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
        onlyOwnedByUser = try container.decodeIfPresent(Bool.self, forKey: .onlyOwnedByUser) ?? false
    }
}

public enum TargetScope: String, Codable, Sendable {
    /// The matched item itself.
    case item
    /// Each item inside the matched folder; the folder stays.
    case contents
}

public enum RuleSafety: String, Codable, Sendable {
    case regenerable
    case review
    case expert

    public var level: SafetyLevel {
        switch self {
        case .regenerable: .regenerable
        case .review: .review
        case .expert: .expert
        }
    }
}

public enum RunningPolicy: String, Codable, Sendable {
    /// Leave the items alone while the app runs.
    case skip
    /// Ask the user to quit the app first.
    case requireQuit
    case allow
}

/// A well-known location and what it's for. Used to explain items, not to remove them.
public struct KnownLocation: Codable, Sendable, Hashable {
    public var path: String
    public var title: String
    public var explanation: String
    /// Whether removing the whole location ever makes sense.
    public var removable: Bool

    public init(path: String, title: String, explanation: String, removable: Bool) {
        self.path = path
        self.title = title
        self.explanation = explanation
        self.removable = removable
    }
}

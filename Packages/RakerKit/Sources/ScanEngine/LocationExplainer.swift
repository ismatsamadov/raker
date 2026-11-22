import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import RuleEngine
import SafetyPolicy

/// Everything Raker knows about one location: the answer to "what is this?"
public struct LocationExplanation: Sendable {
    public let path: String
    /// The rule that describes the location, if one covers it.
    public let rule: Rule?
    /// A description of a well-known location that contains or is this path.
    public let knownLocation: KnownLocation?
    /// Whether `knownLocation` describes this exact path rather than a parent.
    public let knownLocationIsExact: Bool
    public let owner: Owner
    public let verdict: SafetyPolicy.Verdict
    public let measurement: Measurement?
}

/// Explains any path, using the rule pack, folder names and the safety policy.
public struct LocationExplainer: Sendable {
    private let pack: RulePack
    private let environment: PathEnvironment
    private let apps: any AppDirectory

    public init(pack: RulePack, environment: PathEnvironment = .current(), apps: any AppDirectory) {
        self.pack = pack
        self.environment = environment
        self.apps = apps
    }

    /// Blocks while measuring; call it off the main thread.
    public func explain(_ path: String) -> LocationExplanation {
        let rule = pack.activeRules.first { rule in
            rule.targets.contains { covers($0, path: path) }
        }
        let known = knownLocation(for: path)
        let owner = OwnerResolver(apps: apps).owner(ofFolderNamed: Paths.lastComponent(path))
        return LocationExplanation(
            path: path,
            rule: rule,
            knownLocation: known?.location,
            knownLocationIsExact: known?.isExact ?? false,
            owner: owner,
            verdict: SafetyPolicy(homeDirectory: environment.home).evaluate(path),
            measurement: PathMeasurer.measure(path)
        )
    }

    /// A target covers its matches and everything inside them. For a contents target the rule
    /// describes what's inside the folder, which also explains the folder itself.
    private func covers(_ target: RuleTarget, path: String) -> Bool {
        guard let expanded = PathPattern.expand(target.path, in: environment) else { return false }
        return PathPattern.covers(expanded, path: path)
    }

    /// The most specific known location that is, or contains, `path`.
    private func knownLocation(for path: String) -> (location: KnownLocation, isExact: Bool)? {
        let pathComponents = path.split(separator: "/")
        var best: (location: KnownLocation, depth: Int)?
        for location in pack.locations {
            guard let expanded = PathPattern.expand(location.path, in: environment),
                  PathPattern.covers(expanded, path: path) else { continue }
            let depth = expanded.split(separator: "/").count
            if depth > (best?.depth ?? -1) { best = (location, depth) }
        }
        return best.map { ($0.location, $0.depth == pathComponents.count) }
    }
}

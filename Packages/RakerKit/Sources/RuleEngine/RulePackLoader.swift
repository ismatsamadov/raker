import Foundation
import SafetyPolicy

public enum RulePackError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case unsupportedSchema(Int)
    case duplicateRuleID(String)
    case unknownVariable(rule: String, path: String)
    case unsafeTarget(rule: String, path: String, reason: String)

    public var description: String {
        switch self {
        case .unreadable(let detail): "The rule pack couldn't be read: \(detail)"
        case .unsupportedSchema(let schema): "Rule pack schema \(schema) isn't supported."
        case .duplicateRuleID(let id): "Two rules share the ID \(id)."
        case .unknownVariable(let rule, let path): "Rule \(rule) uses an unknown variable in \(path)."
        case .unsafeTarget(let rule, let path, let reason): "Rule \(rule) could reach a protected location (\(path): \(reason))."
        }
    }
}

public enum RulePackLoader {
    public static func decode(_ data: Data) throws(RulePackError) -> RulePack {
        let pack: RulePack
        do {
            pack = try JSONDecoder().decode(RulePack.self, from: data)
        } catch {
            throw .unreadable(String(describing: error))
        }
        guard pack.schema == RulePack.supportedSchema else { throw .unsupportedSchema(pack.schema) }
        return pack
    }

    /// Checks that rule IDs are unique, variables are known, and every target could only
    /// reach locations the safety policy lets rules target.
    ///
    /// Wildcards are probed with a placeholder name. The scanner still checks every real
    /// match against the policy, so this is a first line of defense, not the only one.
    public static func validate(_ pack: RulePack, environment: PathEnvironment) throws(RulePackError) {
        let policy = SafetyPolicy(homeDirectory: environment.home)
        var seen = Set<String>()
        for rule in pack.rules {
            guard seen.insert(rule.id).inserted else { throw .duplicateRuleID(rule.id) }
            for target in rule.targets {
                guard let expanded = PathPattern.expand(target.path, in: environment) else {
                    throw .unknownVariable(rule: rule.id, path: target.path)
                }
                var probe = expanded.split(separator: "/")
                    .map { PathPattern.hasWildcard($0) ? "raker-probe" : String($0) }
                    .reduce("") { $0 + "/" + $1 }
                if target.scope == .contents { probe += "/raker-probe" }
                switch policy.evaluate(probe) {
                case .allowed:
                    continue
                case .selectionOnly(let reason), .denied(let reason):
                    throw .unsafeTarget(rule: rule.id, path: target.path, reason: reason.rawValue)
                }
            }
        }
    }
}

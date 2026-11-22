import Darwin
import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import RuleEngine
import SafetyPolicy
import Synchronization

/// The findings one rule produced, largest first.
public struct RuleFindingGroup: Sendable, Identifiable {
    public let rule: Rule
    public let findings: [Finding]

    public var id: String { rule.id }

    public var allocatedBytes: UInt64 {
        findings.reduce(0) { $0 &+ $1.size.allocated }
    }

    public var reclaimableBytes: UInt64 {
        findings.reduce(0) { $0 &+ ($1.size.reclaimable ?? 0) }
    }
}

public struct RuleScanReport: Sendable {
    /// Non-empty groups, in rule order.
    public let groups: [RuleFindingGroup]
    public let duration: Duration
    public let packVersion: String
    /// Locations rules point at that Raker wasn't allowed to read, such as caches that
    /// Full Disk Access protects. Their size is unknown, so they aren't findings.
    public let unreadable: [SkippedLocation]

    public var findings: [Finding] { groups.flatMap(\.findings) }

    public func allocatedBytes(safety: SafetyLevel) -> UInt64 {
        groups.filter { $0.rule.safety.level == safety }.reduce(0) { $0 &+ $1.allocatedBytes }
    }

    /// The same report with only the findings that pass `isIncluded`; emptied groups are dropped.
    public func filtered(_ isIncluded: (Finding) -> Bool) -> RuleScanReport {
        let kept = groups.compactMap { group -> RuleFindingGroup? in
            let findings = group.findings.filter(isIncluded)
            return findings.isEmpty ? nil : RuleFindingGroup(rule: group.rule, findings: findings)
        }
        return RuleScanReport(groups: kept, duration: duration, packVersion: packVersion, unreadable: unreadable)
    }
}

/// Applies a rule pack to the disk and produces explained findings.
///
/// Rules run in order and the first rule to claim an item wins. A generic rule never
/// double-counts what a specific rule claimed: it splits around it instead. Every candidate
/// is re-checked against the safety policy, must not be reached through a symlink, and is
/// measured honestly (clone- and hard-link-aware).
public struct RuleScanner: Sendable {
    private let pack: RulePack
    private let environment: PathEnvironment
    private let policy: SafetyPolicy
    private let apps: any AppDirectory
    private let now: @Sendable () -> Date

    public init(
        pack: RulePack,
        environment: PathEnvironment = .current(),
        apps: any AppDirectory,
        exclusions: [String] = [],
        lockedOriginals: [String] = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.pack = pack
        self.environment = environment
        self.policy = SafetyPolicy(homeDirectory: environment.home, exclusions: exclusions, lockedOriginals: lockedOriginals)
        self.apps = apps
        self.now = now
    }

    public func scan() async -> RuleScanReport {
        await withCheckedContinuation { continuation in
            // Measuring blocks on file system calls, so it gets its own thread.
            let thread = Thread {
                continuation.resume(returning: scanBlocking())
            }
            thread.name = "Raker rule scan"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    func scanBlocking() -> RuleScanReport {
        let clock = ContinuousClock()
        let start = clock.now
        let resolver = OwnerResolver(apps: apps)
        var claims = ClaimSet()
        var groups: [RuleFindingGroup] = []
        let refused = Mutex(Set<String>())

        for rule in pack.activeRules {
            // Earlier rules' claims decide what this rule may consider; within one rule the
            // pieces don't overlap, so they're measured in parallel.
            let pieces = rule.targets.flatMap { target in
                candidates(for: target, refused: refused).flatMap { claims.split($0) }.map { (target: target, path: $0) }
            }
            let results = Mutex([Int: Finding]())
            // Few large items get more threads each; many small ones get fewer.
            let cores = BulkWalker.defaultWorkerCount
            let workersPerItem = max(2, cores / max(1, min(pieces.count, cores)))
            DispatchQueue.concurrentPerform(iterations: pieces.count) { index in
                let piece = pieces[index]
                switch makeFinding(rule: rule, target: piece.target, path: piece.path, resolver: resolver,
                                   workers: workersPerItem) {
                case .found(let finding): results.withLock { $0[index] = finding }
                case .refused: refused.withLock { _ = $0.insert(piece.path) }
                case .ignored: break
                }
            }
            let found = results.withLock { $0 }
            var findings: [Finding] = []
            for index in pieces.indices {
                guard let finding = found[index] else { continue }
                claims.insert(pieces[index].path)
                findings.append(finding)
            }
            if !findings.isEmpty {
                groups.append(RuleFindingGroup(rule: rule, findings: findings.sorted { $0.size.allocated > $1.size.allocated }))
            }
        }
        let unreadable = refused.withLock { $0 }.sorted().map { path in
            SkippedLocation(path: path, reason: .permissionDenied(
                area: ProtectedArea.classify(path: path, homeDirectory: environment.home)))
        }
        return RuleScanReport(groups: groups, duration: clock.now - start, packVersion: pack.version, unreadable: unreadable)
    }

    private func candidates(for target: RuleTarget, refused: borrowing Mutex<Set<String>>) -> [String] {
        guard let expanded = PathPattern.expand(target.path, in: environment) else { return [] }
        var result: [String] = []
        for match in PathPattern.existingMatches(of: expanded) {
            switch target.scope {
            case .item:
                result.append(match)
            case .contents:
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: match) else {
                    if policy.evaluate(match).permitsRules, Self.isRefused(match) {
                        refused.withLock { _ = $0.insert(match) }
                    }
                    continue
                }
                result += names.sorted().map { Paths.join(match, $0) }
            }
        }
        return result.filter { path in
            let name = Paths.lastComponent(path)
            return !target.exclude.contains { PathPattern.matches(Substring($0), name) }
        }
    }

    /// What became of one candidate.
    private enum Candidate {
        case found(Finding)
        /// It qualified, but Raker wasn't allowed to read it.
        case refused
        case ignored
    }

    private func makeFinding(rule: Rule, target: RuleTarget, path: String, resolver: OwnerResolver, workers: Int) -> Candidate {
        guard let status = try? FileStatus.of(path), !status.isSymlink else { return .ignored }
        // Refuse anything reached through a symlink anywhere in its path.
        guard let resolved = try? FileStatus.resolvedPath(path),
              PathCanonicalizer.comparisonKey(for: resolved) == PathCanonicalizer.comparisonKey(for: path)
        else { return .ignored }
        guard policy.evaluate(path).permitsRules else {
            Log.safety.notice("Rule \(rule.id, privacy: .public) matched a protected path; skipped")
            return .ignored
        }
        if target.onlyOwnedByUser, status.ownerID != getuid() { return .ignored }
        let cutoff = target.olderThanDays.map { Int64(now().timeIntervalSince1970) - Int64($0) * 86_400 }
        // Something changed recently can't be untouched; don't bother measuring it.
        if let cutoff, status.modificationTime / 1_000_000_000 >= cutoff { return .ignored }
        guard let measurement = PathMeasurer.measure(path, workerCount: workers) else { return .ignored }
        if measurement.isRefused { return .refused }
        guard measurement.size.allocated > 0 else { return .ignored }

        var evidence: [Evidence] = [.rule(id: rule.id)]
        if let cutoff, let days = target.olderThanDays {
            guard measurement.newestModification < cutoff else { return .ignored }
            evidence.append(.olderThan(days: days))
        }

        var runningCheck = rule.appBundleIDs
        if rule.identifiesOwners {
            let owner = resolver.owner(ofFolderNamed: Paths.lastComponent(path))
            switch owner.status {
            case .installed:
                evidence.append(.owner(name: owner.name, bundleID: owner.bundleID))
                if let bundleID = owner.bundleID { runningCheck.append(bundleID) }
            case .system:
                // "macOS" says little in a list of Apple caches; the folder name says more.
                evidence.append(.owner(name: Paths.lastComponent(path), bundleID: owner.bundleID))
            case .unknown:
                evidence.append(.owner(name: owner.name, bundleID: owner.bundleID))
            case .notInstalled:
                evidence.append(.ownerNotInstalled(bundleID: owner.bundleID ?? owner.name))
            }
        }

        var constraints: [Constraint] = []
        if rule.whileRunning != .allow {
            for bundleID in Set(runningCheck) where apps.isRunning(bundleID: bundleID) {
                if rule.whileRunning == .skip { return .ignored }
                constraints.append(.requiresQuit(bundleID: bundleID))
            }
        }

        return .found(Finding(
            id: "\(rule.id):\(path)",
            subject: .file(FileRef(path: path, identity: status.identity)),
            category: CategoryID(rawValue: rule.category),
            safety: rule.safety.level,
            size: measurement.size,
            evidence: evidence,
            explanation: rule.explanation,
            constraints: constraints,
            preselected: rule.safety == .regenerable
        ))
    }

    /// Whether macOS privacy protection or file permissions keep Raker out of a folder.
    private static func isRefused(_ path: String) -> Bool {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor < 0 else {
            close(descriptor)
            return false
        }
        return errno == EPERM || errno == EACCES
    }
}

/// Items already claimed by a rule, compared by canonical, case-folded path.
struct ClaimSet {
    private var keys: [String] = []

    mutating func insert(_ path: String) {
        if let key = PathCanonicalizer.comparisonKey(for: path) { keys.append(key) }
    }

    /// The parts of `path` no rule has claimed yet: the path itself, nothing if it's already
    /// claimed, or its unclaimed children when something inside it is claimed.
    func split(_ path: String) -> [String] {
        guard let key = PathCanonicalizer.comparisonKey(for: path) else { return [] }
        if keys.contains(where: { key == $0 || key.hasPrefix($0 + "/") }) { return [] }
        guard keys.contains(where: { $0.hasPrefix(key + "/") }) else { return [path] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.sorted().flatMap { split(Paths.join(path, $0)) }
    }
}

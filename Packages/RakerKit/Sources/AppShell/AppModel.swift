import CleanEngine
import DuplicateEngine
import FileSystemKit
import Foundation
import Observation
import Persistence
import RakerFoundation
import RakerModel
import RuleEngine
import SafetyPolicy
import ScanEngine
import SpaceIndex
import SystemKit

/// What the user chose to scan.
public enum ScanScopeChoice: Hashable, Sendable {
    case downloads
    case home
    case folder(URL)

    var path: String {
        switch self {
        case .downloads:
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? Paths.join(NSHomeDirectory(), "Downloads")
        case .home:
            NSHomeDirectory()
        case .folder(let url):
            url.path
        }
    }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .home: "Home"
        case .folder(let url): url.lastPathComponent
        }
    }
}

/// App-wide state: navigation, the current scope and the latest scan.
@MainActor
@Observable
public final class AppModel {
    public enum Section: String, CaseIterable, Identifiable, Hashable {
        case overview
        case largest
        case downloads
        case largeAndOld
        case duplicates
        case cleanup
        case history

        public var id: Self { self }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .largest: "Largest Items"
            case .downloads: "Downloads & Installers"
            case .largeAndOld: "Large & Old"
            case .duplicates: "Duplicates"
            case .cleanup: "Caches & Temporary Files"
            case .history: "Receipts"
            }
        }

        var symbol: String {
            switch self {
            case .overview: "gauge.with.dots.needle.33percent"
            case .largest: "chart.bar.doc.horizontal"
            case .downloads: "arrow.down.circle"
            case .largeAndOld: "clock.badge.exclamationmark"
            case .duplicates: "square.on.square"
            case .cleanup: "sparkles"
            case .history: "clock.arrow.circlepath"
            }
        }
    }

    public enum Phase: Equatable {
        case idle
        case scanning
        case finished
        case failed(String)
    }

    public var selection: Section? = .overview
    public var scope: ScanScopeChoice = .downloads

    // View state lives in the model rather than in views, so screens stay declarative
    // and their state is testable.
    /// The folder shown in Largest Items.
    public var browsedIndex: SizeTree.Index?
    public var largestSelection: Set<SizeTree.Index> = []
    public var previewURL: URL?
    public var isChoosingFolder = false

    public private(set) var phase: Phase = .idle
    public private(set) var progress: ScanProgress?
    public private(set) var report: ScanReport?
    public private(set) var breakdown: [StorageKind: UInt64] = [:]
    public private(set) var volume: VolumeSpace?
    public private(set) var volumeName = "Macintosh HD"
    public private(set) var cleanupPhase: Phase = .idle
    public private(set) var cleanupReport: RuleScanReport?
    /// Finding IDs chosen for cleaning; starts with the items that rebuild automatically.
    public var cleanupSelection: Set<String> = []
    /// Skip the Trash for items that rebuild automatically. Everything else always goes to the Trash.
    public var deleteRegenerable = true
    public var isConfirmingCleanup = false
    public var isShowingReceipt = false
    public private(set) var isCleaning = false
    public private(set) var cleanupProgress: CleanupExecutor.Progress?
    public private(set) var lastReceipt: CleanupReceipt?
    public private(set) var receipts: [CleanupReceipt] = []

    /// The two lists of personal files: everything in Downloads, and large or old files.
    public enum PersonalList: Hashable, Sendable {
        case downloads
        case largeAndOld
    }

    public private(set) var downloadsPhase: Phase = .idle
    public private(set) var downloadsFindings: [Finding] = []
    public var downloadsSelection: Set<String> = []
    public private(set) var largePhase: Phase = .idle
    public private(set) var largeFindings: [Finding] = []
    public var largeSelection: Set<String> = []
    public var largeCriteria = PersonalFileFinder.LargeFileCriteria() {
        didSet { refreshLargeFiles() }
    }
    /// The list whose selection is waiting for confirmation before going to the Trash.
    public var confirmingTrash: PersonalList?

    public private(set) var duplicatesPhase: Phase = .idle
    public private(set) var duplicateSets: [DuplicateSet] = []
    public private(set) var duplicateProgress: DuplicateFinder.Progress?
    /// Paths of copies chosen for removal. A set's kept copy is never among them.
    public var duplicatesSelection: Set<String> = []
    public var duplicateStrategy: SurvivorStrategy = .original {
        didSet {
            keeperOverrides = [:]
            duplicatesSelection.subtract(duplicateSets.map { keeper(of: $0).path })
        }
    }
    /// Copies the user chose to keep instead of the strategy's choice, by set ID.
    public private(set) var keeperOverrides: [String: String] = [:]
    public var isConfirmingDuplicates = false
    private var duplicatesTask: Task<Void, Never>?

    /// Exclusions and locked originals, applied to every scan and cleanup.
    public private(set) var userRules: [UserRule] = []
    public var isChoosingExclusion = false

    private let engine = ScanEngine()
    private let apps = LaunchServicesAppDirectory()
    private let database = try? AppDatabase.open()
    private var journal: JournalStore? { database?.journal }
    private let metadata = SystemFileMetadata()
    private let rulePack = Result { () throws(RulePackError) -> RulePack in try RulePackLoader.baseline() }
    private var scanTask: Task<Void, Never>?
    /// Ignores progress from a scan that has since been replaced.
    private var generation = 0

    public init() {
        refreshVolume()
        refreshHistory()
        refreshUserRules()
    }

    public var isScanning: Bool { phase == .scanning }

    public func toggleScan() {
        isScanning ? cancelScan() : startScan()
    }

    public func startScan() {
        scanTask?.cancel()
        generation += 1
        let current = generation
        let scope = ScanScope(path: self.scope.path)
        phase = .scanning
        progress = nil

        scanTask = Task {
            do throws(ScanError) {
                let report = try await engine.scan(scope) { progress in
                    Task { @MainActor in
                        guard self.generation == current, self.phase == .scanning else { return }
                        self.progress = progress
                    }
                }
                let tree = report.tree
                let breakdown = await Task.detached(priority: .userInitiated) {
                    StorageKindClassifier.breakdown(of: tree, under: tree.root)
                }.value
                guard generation == current else { return }
                self.report = report
                self.breakdown = breakdown
                self.browsedIndex = tree.root
                self.phase = .finished
                refreshLargeFiles()
            } catch {
                guard generation == current else { return }
                phase = .failed(Self.describe(error))
            }
            refreshVolume()
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
    }

    /// An installed app's name, or the bundle ID when no app is installed for it.
    public func appName(for bundleID: String) -> String {
        apps.installedApp(bundleID: bundleID)?.name ?? bundleID
    }

    /// Finds caches, temporary files and logs with the baseline rule pack.
    public func scanCleanup() {
        let pack: RulePack
        switch rulePack {
        case .success(let loaded): pack = loaded
        case .failure(let error):
            cleanupPhase = .failed(error.description)
            return
        }
        cleanupPhase = .scanning
        let scanner = RuleScanner(pack: pack, apps: apps, exclusions: userRules.exclusions, lockedOriginals: userRules.lockedOriginals)
        Task {
            let report = await scanner.scan()
            cleanupReport = report
            cleanupSelection = Set(report.findings.filter(\.preselected).map(\.id))
            cleanupPhase = .finished
        }
    }

    // MARK: Cleaning

    /// The findings currently selected for cleaning.
    public var selectedFindings: [Finding] {
        cleanupReport?.findings.filter { cleanupSelection.contains($0.id) } ?? []
    }

    /// Apps that must quit before some selected items can be cleaned.
    public var appsBlockingSelection: [String] {
        let bundleIDs = Set(selectedFindings.flatMap(\.constraints).compactMap { constraint -> String? in
            if case .requiresQuit(let bundleID) = constraint, apps.isRunning(bundleID: bundleID) { return bundleID }
            return nil
        })
        return bundleIDs.map(appName(for:)).sorted()
    }

    /// Cleans the selected findings, then shows the receipt and scans again.
    public func cleanSelected() {
        let findings = selectedFindings
        guard !findings.isEmpty, !isCleaning else { return }
        isConfirmingCleanup = false
        isCleaning = true
        let plan = PlanBuilder.plan(
            for: findings,
            deleteRegenerable: deleteRegenerable,
            spaceBefore: try? VolumeInfo.space(containing: NSHomeDirectory())
        )
        let executor = makeExecutor()
        Task {
            let receipt = await executor.execute(plan) { progress in
                Task { @MainActor in self.cleanupProgress = progress }
            }
            isCleaning = false
            cleanupProgress = nil
            lastReceipt = receipt
            isShowingReceipt = true
            refreshVolume()
            refreshHistory()
            scanCleanup()
        }
    }

    /// Puts back everything a cleanup moved to the Trash.
    public func restore(_ receipt: CleanupReceipt) {
        let restorer = Restorer(journal: journal)
        Task {
            _ = await Task.detached(priority: .userInitiated) { restorer.restoreAll(in: receipt) }.value
            refreshHistory()
            if lastReceipt?.id == receipt.id {
                lastReceipt = receipts.first { $0.id == receipt.id }
            }
            refreshVolume()
        }
    }

    public func refreshHistory() {
        receipts = (try? journal?.receipts()) ?? []
    }

    // MARK: Personal files

    /// Scans Downloads and lists what's there. Asking is what triggers macOS's prompt for
    /// access to Downloads, at the moment the user wants it.
    public func scanDownloads() {
        downloadsPhase = .scanning
        let path = ScanScopeChoice.downloads.path
        let finder = makeFinder()
        Task {
            do throws(ScanError) {
                let tree = try await engine.scan(ScanScope(path: path)).tree
                let findings = await Task.detached(priority: .userInitiated) { finder.downloads(in: tree) }.value
                downloadsFindings = findings
                downloadsSelection = []
                downloadsPhase = .finished
            } catch {
                downloadsPhase = .failed(Self.describe(error))
            }
        }
    }

    /// Lists large or long-unopened files from the last scan of the current scope.
    public func refreshLargeFiles() {
        guard let tree = report?.tree else {
            largePhase = .idle
            largeFindings = []
            return
        }
        largePhase = .scanning
        let finder = makeFinder()
        let criteria = largeCriteria
        Task {
            let findings = await Task.detached(priority: .userInitiated) {
                finder.largeFiles(in: tree, criteria: criteria)
            }.value
            largeFindings = findings
            largeSelection.formIntersection(findings.map(\.id))
            largePhase = .finished
        }
    }

    public func findings(for list: PersonalList) -> [Finding] {
        list == .downloads ? downloadsFindings : largeFindings
    }

    /// Selects installers whose app is already installed: the safest things to remove from Downloads.
    public func selectInstallersOfInstalledApps() {
        downloadsSelection = Set(downloadsFindings.filter { finding in
            finding.evidence.contains { if case .appInstalled = $0 { true } else { false } }
                && !finding.constraints.contains { if case .synced = $0 { true } else { false } }
        }.map(\.id))
    }

    /// Moves the selected files of a list to the Trash, then shows the receipt.
    public func trashSelected(_ list: PersonalList) {
        let selection = list == .downloads ? downloadsSelection : largeSelection
        let findings = findings(for: list).filter { selection.contains($0.id) }
        guard !findings.isEmpty, !isCleaning else { return }
        confirmingTrash = nil
        isCleaning = true
        let plan = PlanBuilder.plan(
            for: findings, deleteRegenerable: false,
            spaceBefore: try? VolumeInfo.space(containing: NSHomeDirectory())
        )
        let executor = makeExecutor()
        Task {
            let receipt = await executor.execute(plan) { progress in
                Task { @MainActor in self.cleanupProgress = progress }
            }
            isCleaning = false
            cleanupProgress = nil
            lastReceipt = receipt
            isShowingReceipt = true
            let moved = Set(receipt.items.filter { if case .movedToTrash = $0.outcome { true } else { false } }.map(\.findingID))
            switch list {
            case .downloads:
                downloadsFindings.removeAll { moved.contains($0.id) }
                downloadsSelection.subtract(moved)
            case .largeAndOld:
                largeFindings.removeAll { moved.contains($0.id) }
                largeSelection.subtract(moved)
            }
            refreshVolume()
            refreshHistory()
        }
    }

    // MARK: Duplicates

    /// Compares files in the last scan of the current scope. Reads file contents, on this Mac.
    public func findDuplicates() {
        guard let tree = report?.tree else { return }
        duplicatesTask?.cancel()
        duplicatesPhase = .scanning
        duplicateProgress = nil
        let finder = DuplicateFinder(options: .init(exclusions: userRules.exclusions))
        duplicatesTask = Task {
            let sets = await finder.find(in: tree) { progress in
                Task { @MainActor in self.duplicateProgress = progress }
            }
            guard !Task.isCancelled else { return }
            duplicateSets = sets
            duplicatesSelection = []
            keeperOverrides = [:]
            duplicatesPhase = .finished
        }
    }

    public func cancelDuplicates() {
        duplicatesTask?.cancel()
        duplicatesPhase = .idle
    }

    /// The copy that stays: a locked original if there is one, otherwise the user's choice,
    /// otherwise the strategy's suggestion.
    public func keeper(of set: DuplicateSet) -> DuplicateFile {
        if !set.files.contains(where: { isLocked($0.path) }),
           let path = keeperOverrides[set.id], let file = set.files.first(where: { $0.path == path }) {
            return file
        }
        return duplicateStrategy.keeper(in: set, locked: userRules.lockedOriginals)
    }

    /// Keeps this copy instead, and makes sure it isn't selected for removal.
    public func keep(_ file: DuplicateFile, in set: DuplicateSet) {
        keeperOverrides[set.id] = file.path
        duplicatesSelection.remove(file.path)
    }

    /// Selects every copy except the one that stays in each set.
    public func selectAllDuplicates() {
        duplicatesSelection = Set(duplicateSets.flatMap { set in
            let keeper = keeper(of: set).path
            return set.files.map(\.path).filter { $0 != keeper }
        })
    }

    /// Moves the selected copies to the Trash, keeping one copy of each set.
    public func trashSelectedDuplicates() {
        let findings = duplicateSets.flatMap { $0.findings(removing: duplicatesSelection, keeping: keeper(of: $0)) }
        guard !findings.isEmpty, !isCleaning else { return }
        isConfirmingDuplicates = false
        isCleaning = true
        let plan = PlanBuilder.plan(
            for: findings, deleteRegenerable: false,
            spaceBefore: try? VolumeInfo.space(containing: NSHomeDirectory())
        )
        let executor = makeExecutor()
        Task {
            let receipt = await executor.execute(plan) { progress in
                Task { @MainActor in self.cleanupProgress = progress }
            }
            isCleaning = false
            cleanupProgress = nil
            lastReceipt = receipt
            isShowingReceipt = true
            let moved = Set(receipt.items.filter { if case .movedToTrash = $0.outcome { true } else { false } }.map(\.path))
            duplicatesSelection.subtract(moved)
            duplicateSets = duplicateSets.compactMap { set in
                let files = set.files.filter { !moved.contains($0.path) }
                return files.count > 1 ? DuplicateSet(id: set.id, size: set.size, allocatedPerCopy: set.allocatedPerCopy, files: files) : nil
            }
            refreshVolume()
            refreshHistory()
        }
    }

    private func makeFinder() -> PersonalFileFinder {
        PersonalFileFinder(metadata: metadata, installedAppNames: ApplicationsFolder.installedAppNames(),
                           exclusions: userRules.exclusions, lockedOriginals: userRules.lockedOriginals)
    }

    private func makeExecutor() -> CleanupExecutor {
        CleanupExecutor(exclusions: userRules.exclusions, lockedOriginals: userRules.lockedOriginals,
                        apps: apps, journal: journal)
    }

    // MARK: Exclusions and locked originals

    /// Adds a rule and takes matching items out of every list right away.
    public func addUserRule(_ kind: UserRule.Kind, for path: String) {
        try? database?.userRules.add(UserRule(path: path, kind: kind))
        refreshUserRules()
        applyUserRules()
    }

    public func removeUserRule(_ rule: UserRule) {
        try? database?.userRules.remove(id: rule.id)
        refreshUserRules()
    }

    private func refreshUserRules() {
        userRules = (try? database?.userRules.all()) ?? []
    }

    private var userRulePolicy: SafetyPolicy {
        SafetyPolicy(homeDirectory: NSHomeDirectory(), exclusions: userRules.exclusions, lockedOriginals: userRules.lockedOriginals)
    }

    private func isLocked(_ path: String) -> Bool {
        userRulePolicy.evaluate(path) == .denied(.lockedOriginal)
    }

    private func applyUserRules() {
        let policy = userRulePolicy
        func blocked(_ path: String) -> Bool {
            switch policy.evaluate(path) {
            case .denied(.userExcluded), .denied(.lockedOriginal): true
            default: false
            }
        }
        cleanupReport = cleanupReport?.filtered { !blocked($0.path) }
        cleanupSelection = cleanupSelection.filter { id in cleanupReport?.findings.contains { $0.id == id } ?? false }
        downloadsFindings.removeAll { blocked($0.path) }
        downloadsSelection = downloadsSelection.filter { id in downloadsFindings.contains { $0.id == id } }
        largeFindings.removeAll { blocked($0.path) }
        largeSelection = largeSelection.filter { id in largeFindings.contains { $0.id == id } }
        // Excluded copies leave their sets; locked copies stay, as the copy that's kept.
        duplicateSets = duplicateSets.compactMap { set in
            let files = set.files.filter { policy.evaluate($0.path) != .denied(.userExcluded) }
            return files.count > 1 ? DuplicateSet(id: set.id, size: set.size, allocatedPerCopy: set.allocatedPerCopy, files: files) : nil
        }
        duplicatesSelection = duplicatesSelection.filter { !blocked($0) }
    }

    public func refreshVolume() {
        // Ask about the home folder, not Downloads: touching a protected folder would show a
        // privacy prompt before the user has asked for anything. A chosen folder was granted
        // by the user's own selection.
        let path: String
        switch scope {
        case .folder(let url): path = url.path
        case .downloads, .home: path = NSHomeDirectory()
        }
        volume = try? VolumeInfo.space(containing: path)
        volumeName = VolumeInfo.name(containing: path) ?? "Macintosh HD"
    }

    private static func describe(_ error: ScanError) -> String {
        switch error {
        case .rootNotFound(let path): "Raker couldn't find \(path)."
        case .rootNotDirectory(let path): "\(path) isn't a folder."
        case .rootUnreadable(let path, _): "Raker doesn't have permission to read \(path)."
        }
    }
}

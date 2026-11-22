import AppKit
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
    /// Skip the Trash for items that rebuild automatically. Everything else always goes to the Trash.
    public var deleteRegenerable = true
    public var isReviewingTray = false
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
    public private(set) var largePhase: Phase = .idle
    public private(set) var largeFindings: [Finding] = []
    public var largeCriteria = PersonalFileFinder.LargeFileCriteria() {
        didSet { refreshLargeFiles() }
    }

    public private(set) var duplicatesPhase: Phase = .idle
    public private(set) var duplicateSets: [DuplicateSet] = []
    public private(set) var duplicateProgress: DuplicateFinder.Progress?
    public var duplicateStrategy: SurvivorStrategy = .original {
        didSet {
            keeperOverrides = [:]
            stageDuplicates(duplicatesSelection)
        }
    }
    /// Copies the user chose to keep instead of the strategy's choice, by set ID.
    public private(set) var keeperOverrides: [String: String] = [:]
    private var duplicatesTask: Task<Void, Never>?

    /// Exclusions and locked originals, applied to every scan and cleanup.
    public private(set) var userRules: [UserRule] = []

    /// Items staged for cleaning from every section, kept across relaunches. Checking an item
    /// in any list stages it.
    public private(set) var tray = Tray()
    public var isChoosingExclusion = false

    /// What Raker knows about each protected area.
    public private(set) var access: AccessMap
    public var settingsTab: SettingsTab = .access
    public var isShowingSkipped = false
    public var isShowingUnreadable = false

    public enum SettingsTab: Hashable {
        case access
        case exclusions
    }

    /// First run: a welcome, then what to scan first. The scan itself, on the Overview, is the
    /// last step.
    public var isShowingFirstRun: Bool
    public var firstRunStep: FirstRunStep = .welcome
    public var firstRunChoice: FirstRunChoice = .downloads
    public var isChoosingFirstRunFolder = false

    public enum FirstRunStep: Hashable {
        case welcome
        case chooseScope
    }

    public enum FirstRunChoice: Hashable {
        case downloads
        case home
        case folder
    }

    private static let accessKey = "access.remembered"
    private static let firstRunKey = "firstRun.completed"
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    private let engine = ScanEngine()
    private let apps = LaunchServicesAppDirectory()
    private let database: AppDatabase?
    private var journal: JournalStore? { database?.journal }
    private let metadata = SystemFileMetadata()
    private let rulePack = Result { () throws(RulePackError) -> RulePack in try RulePackLoader.baseline() }
    private var scanTask: Task<Void, Never>?
    /// Ignores progress from a scan that has since been replaced.
    private var generation = 0

    /// - Parameter database: Where history, rules and the Tray are kept. Previews and tests
    ///   pass one in memory.
    public init(database: AppDatabase? = try? AppDatabase.open()) {
        self.database = database
        let defaults = UserDefaults.standard
        access = AccessMap(remembered: defaults.dictionary(forKey: Self.accessKey) as? [String: String] ?? [:])
        isShowingFirstRun = !defaults.bool(forKey: Self.firstRunKey)
        refreshVolume()
        refreshHistory()
        refreshUserRules()
        tray = Tray(items: (try? database?.tray.all()) ?? [])
        revalidateTray()
        refreshAccess()
        // Access given in System Settings shows up as soon as the person comes back.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccess() }
        }
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
                if report.completed {
                    learnAccess { $0.learn(fromScanOf: tree.rootPath, skipped: report.skipped, homeDirectory: NSHomeDirectory()) }
                }
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
                learnAccess(from: error)
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
    /// - Parameter preselect: Stage the items that rebuild automatically. Off when scanning
    ///   again right after a cleanup, so the Tray doesn't refill on its own.
    public func scanCleanup(preselect: Bool = true) {
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
            learnAccess { $0.learn(refused: report.unreadable) }
            cleanupReport = report
            updateTray { tray in
                tray.unstage { $0.source == .cleanup }
                for finding in report.findings where preselect && finding.preselected {
                    tray.stage(TrayItem(finding: finding, source: .cleanup))
                }
            }
            cleanupPhase = .finished
        }
    }

    // MARK: Cleaning

    /// Apps that must quit before some staged items can be cleaned.
    public var appsBlockingTray: [String] {
        let bundleIDs = Set(tray.findings.flatMap(\.constraints).compactMap { constraint -> String? in
            if case .requiresQuit(let bundleID) = constraint, apps.isRunning(bundleID: bundleID) { return bundleID }
            return nil
        })
        return bundleIDs.map(appName(for:)).sorted()
    }

    /// Cleans everything in the Tray, then shows the receipt. Items that rebuild automatically
    /// are deleted if the person agreed; everything else goes to the Trash.
    public func cleanTray() {
        let findings = tray.findings
        guard !findings.isEmpty, !isCleaning else { return }
        let sources = Set(tray.items.map(\.source))
        isReviewingTray = false
        isCleaning = true
        let plan = PlanBuilder.plan(
            for: findings,
            deleteRegenerable: deleteRegenerable,
            spaceBefore: try? VolumeInfo.space(containing: NSHomeDirectory())
        )
        let executor = makeExecutor()
        let started = ContinuousClock.now
        Task {
            let receipt = await executor.execute(plan) { progress in
                Task { @MainActor in self.cleanupProgress = progress }
            }
            // Let the review sheet finish closing before the receipt opens.
            let elapsed = ContinuousClock.now - started
            if elapsed < .milliseconds(450) {
                try? await Task.sleep(for: .milliseconds(450) - elapsed)
            }
            isCleaning = false
            cleanupProgress = nil
            lastReceipt = receipt
            isShowingReceipt = true
            removeCleaned(in: receipt)
            unstageCompleted(in: receipt)
            refreshVolume()
            refreshHistory()
            if sources.contains(.cleanup) {
                scanCleanup(preselect: false)
            }
        }
    }

    public func clearTray() {
        updateTray { $0.removeAll() }
    }

    public func unstage(_ id: String) {
        updateTray { $0.unstage(id) }
    }

    /// Takes what a cleanup removed out of the lists that showed it.
    private func removeCleaned(in receipt: CleanupReceipt) {
        let removed = receipt.items.filter { item in
            switch item.outcome {
            case .movedToTrash, .deleted: true
            case .skipped, .failed: false
            }
        }
        let ids = Set(removed.map(\.findingID))
        let paths = Set(removed.map(\.path))
        downloadsFindings.removeAll { ids.contains($0.id) }
        largeFindings.removeAll { ids.contains($0.id) }
        duplicateSets = duplicateSets.compactMap { set in
            let files = set.files.filter { !paths.contains($0.path) }
            return files.count > 1 ? DuplicateSet(id: set.id, size: set.size, allocatedPerCopy: set.allocatedPerCopy, files: files) : nil
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
                let report = try await engine.scan(ScanScope(path: path))
                let tree = report.tree
                learnAccess { $0.learn(fromScanOf: tree.rootPath, skipped: report.skipped, homeDirectory: NSHomeDirectory()) }
                let findings = await Task.detached(priority: .userInitiated) { finder.downloads(in: tree) }.value
                downloadsFindings = findings
                restage(from: .downloads, keepingOnly: findings)
                downloadsPhase = .finished
            } catch {
                learnAccess(from: error)
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
            // Items the new criteria leave out stay staged: the person chose them.
            restage(from: .largeAndOld, keepingOnly: nil, updating: findings)
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
            keeperOverrides = [:]
            // Copies staged before stay staged, now naming this comparison's kept copy.
            stageDuplicates(duplicatesSelection)
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
        downloadsFindings.removeAll { blocked($0.path) }
        largeFindings.removeAll { blocked($0.path) }
        // Excluded copies leave their sets; locked copies stay, as the copy that's kept.
        duplicateSets = duplicateSets.compactMap { set in
            let files = set.files.filter { policy.evaluate($0.path) != .denied(.userExcluded) }
            return files.count > 1 ? DuplicateSet(id: set.id, size: set.size, allocatedPerCopy: set.allocatedPerCopy, files: files) : nil
        }
        // Excluded and locked items leave the Tray. Other copies of a locked file now name it
        // as the copy that stays.
        updateTray { $0.unstage { blocked($0.finding.path) } }
        stageDuplicates(duplicatesSelection)
    }

    // MARK: Tray

    /// Finding IDs staged from Caches & Temporary Files. Setting it stages and unstages
    /// listed items to match.
    public var cleanupSelection: Set<String> {
        get { tray.ids(from: .cleanup) }
        set { stage(newValue, from: .cleanup, among: cleanupReport?.findings ?? []) }
    }

    public var downloadsSelection: Set<String> {
        get { tray.ids(from: .downloads) }
        set { stage(newValue, from: .downloads, among: downloadsFindings) }
    }

    public var largeSelection: Set<String> {
        get { tray.ids(from: .largeAndOld) }
        set { stage(newValue, from: .largeAndOld, among: largeFindings) }
    }

    /// Paths of copies staged for removal. A set's kept copy is never among them.
    public var duplicatesSelection: Set<String> {
        get { Set(tray.items(from: .duplicates).map(\.finding.path)) }
        set { stageDuplicates(newValue) }
    }

    /// Makes the listed items staged from `source` exactly those in `ids`. Staged items that
    /// aren't listed, such as ones a filter hides, stay.
    private func stage(_ ids: Set<String>, from source: TrayItem.Source, among listed: [Finding]) {
        let listedIDs = Set(listed.map(\.id))
        updateTray { tray in
            tray.unstage { $0.source == source && listedIDs.contains($0.id) && !ids.contains($0.id) }
            for finding in listed where ids.contains(finding.id) && !tray.contains(finding.id) {
                tray.stage(TrayItem(finding: finding, source: source))
            }
        }
    }

    /// Stages the chosen copies of the sets on screen, each naming its set's current kept
    /// copy, which is never staged itself. Copies staged from earlier comparisons stay.
    private func stageDuplicates(_ paths: Set<String>) {
        var onScreen = Set<String>()
        var staged: [Finding] = []
        for set in duplicateSets {
            onScreen.formUnion(set.files.map(\.path))
            staged += set.findings(removing: paths, keeping: keeper(of: set))
        }
        let stagedIDs = Set(staged.map(\.id))
        updateTray { tray in
            tray.unstage { $0.source == .duplicates && onScreen.contains($0.finding.path) && !stagedIDs.contains($0.id) }
            for finding in staged {
                tray.stage(TrayItem(finding: finding, source: .duplicates))
            }
        }
    }

    /// After a fresh scan of a section: refreshes staged items that are still there, and, when
    /// `keepingOnly` is given, unstages the ones that aren't.
    private func restage(from source: TrayItem.Source, keepingOnly present: [Finding]?, updating listed: [Finding]? = nil) {
        let current = Dictionary((present ?? listed ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        updateTray { tray in
            if present != nil {
                tray.unstage { $0.source == source && current[$0.id] == nil }
            }
            for item in tray.items(from: source) {
                if let finding = current[item.id] {
                    tray.stage(TrayItem(finding: finding, source: source))
                }
            }
        }
    }

    /// Takes out what a cleanup moved to the Trash or deleted. Skipped and failed items stay.
    private func unstageCompleted(in receipt: CleanupReceipt) {
        let done = Set(receipt.items.compactMap { item -> String? in
            switch item.outcome {
            case .movedToTrash, .deleted: item.findingID
            case .skipped, .failed: nil
            }
        })
        updateTray { $0.unstage { done.contains($0.id) } }
    }

    /// Drops staged items that changed or disappeared while Raker was closed, or that the
    /// person excluded since. Items blocked only by a running app stay.
    private func revalidateTray() {
        guard !tray.isEmpty else { return }
        let findings = tray.findings
        let executor = makeExecutor()
        Task {
            let stale = await Task.detached(priority: .utility) { () -> Set<String> in
                let plan = PlanBuilder.plan(for: findings, deleteRegenerable: false, spaceBefore: nil)
                var stale = Set<String>()
                for (item, reason) in zip(plan.items, executor.preview(plan)) {
                    guard let reason else { continue }
                    if case .appRunning = reason { continue }
                    stale.insert(item.finding.id)
                }
                return stale
            }.value
            updateTray { $0.unstage { stale.contains($0.id) } }
        }
    }

    private func updateTray(_ update: (inout Tray) -> Void) {
        var updated = tray
        update(&updated)
        guard updated != tray else { return }
        tray = updated
        try? database?.tray.save(updated.items)
    }

    // MARK: Access

    /// Checks again what can be checked without macOS asking anything.
    public func refreshAccess() {
        let areas = access.areasToCheck
        let probe = AccessProbe()
        Task {
            let states = await Task.detached(priority: .utility) { probe.check(areas) }.value
            learnAccess { map in
                for (area, state) in states { map[area] = state }
            }
        }
    }

    /// Reads a Files & Folders area, which makes macOS ask if it hasn't already.
    public func requestAccess(to area: ProtectedArea) {
        let probe = AccessProbe()
        Task {
            let state = await Task.detached(priority: .userInitiated) { probe.check(area) }.value
            learnAccess { $0[area] = state }
        }
    }

    private func learnAccess(_ update: (inout AccessMap) -> Void) {
        var updated = access
        update(&updated)
        guard updated != access else { return }
        access = updated
        UserDefaults.standard.set(updated.remembered, forKey: Self.accessKey)
    }

    private func learnAccess(from error: ScanError) {
        if case .rootUnreadable(let path, let code) = error, code == .EPERM || code == .EACCES {
            learnAccess { $0.learn(unreadableRoot: path, homeDirectory: NSHomeDirectory()) }
        }
    }

    // MARK: First run

    /// Starts the scan chosen on the second screen, asking for the folder first if needed.
    public func startFirstScan() {
        switch firstRunChoice {
        case .downloads: finishFirstRun(scanning: .downloads)
        case .home: finishFirstRun(scanning: .home)
        case .folder: isChoosingFirstRunFolder = true
        }
    }

    public func showFirstRun() {
        firstRunStep = .welcome
        isShowingFirstRun = true
    }

    public func finishFirstRun(scanning scope: ScanScopeChoice) {
        UserDefaults.standard.set(true, forKey: Self.firstRunKey)
        self.scope = scope
        selection = .overview
        isShowingFirstRun = false
        startScan()
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

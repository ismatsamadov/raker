import CleanEngine
import FileSystemKit
import Foundation
import Observation
import Persistence
import RakerFoundation
import RakerModel
import RuleEngine
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

    private let engine = ScanEngine()
    private let apps = LaunchServicesAppDirectory()
    private let journal = try? JournalStore.open()
    private let rulePack = Result { () throws(RulePackError) -> RulePack in try RulePackLoader.baseline() }
    private var scanTask: Task<Void, Never>?
    /// Ignores progress from a scan that has since been replaced.
    private var generation = 0

    public init() {
        refreshVolume()
        refreshHistory()
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
        let scanner = RuleScanner(pack: pack, apps: apps)
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
        let executor = CleanupExecutor(apps: apps, journal: journal)
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

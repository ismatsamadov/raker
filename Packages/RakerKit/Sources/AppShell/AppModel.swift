import FileSystemKit
import Foundation
import Observation
import RakerFoundation
import RakerModel
import ScanEngine
import SpaceIndex

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
        case history

        public var id: Self { self }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .largest: "Largest Items"
            case .downloads: "Downloads & Installers"
            case .largeAndOld: "Large & Old"
            case .duplicates: "Duplicates"
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

    private let engine = ScanEngine()
    private var scanTask: Task<Void, Never>?
    /// Ignores progress from a scan that has since been replaced.
    private var generation = 0

    public init() {
        refreshVolume()
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

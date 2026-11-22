import DesignSystem
import QuickLook
import SwiftUI

/// The app's scenes. The Xcode app target and the development runner both use this.
public struct RakerScenes: Scene {
    private let model: AppModel

    /// - Parameter model: Created once by the app and kept for its lifetime.
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Scene {
        WindowGroup("Raker", id: "main") {
            RakerRootView(model: model)
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(after: .help) {
                Button("Welcome to Raker") { model.showFirstRun() }
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

/// The main window: sidebar, content and (later) inspector.
public struct RakerRootView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.isShowingFirstRun {
                FirstRunView(model: model)
                    .transition(.opacity)
            } else {
                mainWindow
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .animation(Motion.smooth, value: model.isShowingFirstRun)
    }

    private var mainWindow: some View {
        NavigationSplitView {
            SidebarView(selection: $model.selection)
        } detail: {
            detail(for: model.selection ?? .overview)
                .safeAreaInset(edge: .bottom) {
                    if showsTray {
                        TrayCapsule(model: model)
                            .padding(.bottom, Spacing.l)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(Motion.smooth, value: showsTray)
                .sheet(isPresented: $model.isReviewingTray) {
                    TrayReviewView(model: model)
                }
                .inspector(isPresented: Binding(
                    get: { model.isShowingInspector && model.hasInspector },
                    set: { if model.hasInspector { model.isShowingInspector = $0 } }
                )) {
                    InspectorView(model: model)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
                }
                .toolbar {
                    if model.hasInspector {
                        ToolbarItem {
                            Button {
                                model.isShowingInspector.toggle()
                            } label: {
                                Label("Inspector", systemImage: "sidebar.right")
                            }
                            .help(model.isShowingInspector ? "Hide the inspector" : "Show the inspector")
                        }
                    }
                }
        }
        .overlay {
            if model.isCleaning {
                CleaningProgressView(progress: model.cleanupProgress)
            }
        }
        .sheet(isPresented: $model.isShowingReceipt) {
            if let receipt = model.lastReceipt {
                ReceiptView(receipt: receipt, appName: model.appName(for:)) {
                    model.restore(receipt)
                } onDone: {
                    model.isShowingReceipt = false
                }
            }
        }
        .quickLookPreview($model.previewURL)
    }

    /// The Tray shows wherever items can be staged, and everywhere once it holds something.
    private var showsTray: Bool {
        guard model.tray.isEmpty else { return true }
        switch model.selection ?? .overview {
        case .cleanup, .downloads, .largeAndOld, .duplicates: return true
        case .overview, .largest, .history: return false
        }
    }

    @ViewBuilder
    private func detail(for section: AppModel.Section) -> some View {
        switch section {
        case .overview:
            OverviewView(model: model)
        case .largest:
            LargestItemsView(model: model)
        case .downloads:
            PersonalFilesView(model: model, list: .downloads)
        case .largeAndOld:
            PersonalFilesView(model: model, list: .largeAndOld)
        case .duplicates:
            DuplicatesView(model: model)
        case .cleanup:
            CleanupView(model: model)
        case .history:
            HistoryView(model: model)
        }
    }
}

struct SidebarView: View {
    @Binding var selection: AppModel.Section?

    var body: some View {
        List(selection: $selection) {
            row(.overview)
            Section("Explore") {
                ForEach([AppModel.Section.largest, .downloads, .largeAndOld, .duplicates]) { row($0) }
            }
            Section("Clean") {
                row(.cleanup)
            }
            Section("History") {
                row(.history)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    private func row(_ section: AppModel.Section) -> some View {
        Label(section.title, systemImage: section.symbol).tag(section)
    }
}

struct PlaceholderView: View {
    let section: AppModel.Section
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.symbol)
        } description: {
            Text(message)
        } actions: {
            Text("Coming in the first release")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(section.title)
    }
}


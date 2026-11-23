import DesignSystem
import SwiftUI

extension AppModel.Section {
    var tint: Color {
        switch self {
        case .overview, .cleanup: Palette.moss
        case .largest, .largeAndOld, .history: Palette.lagoon
        case .downloads, .leftovers: Palette.ochre
        case .duplicates, .applications: Palette.iris
        }
    }
}

/// A consistent starting point for a scan, an empty result, or a recoverable error.
struct WorkspaceState<Actions: View>: View {
    let title: String
    let symbol: String
    let detail: String
    var tint: Color = Palette.accent
    @ViewBuilder var actions: Actions

    var body: some View {
        ViewThatFits(in: .vertical) {
            card
            ScrollView { card }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(spacing: 0) {
            ZStack {
                tint.opacity(0.08)
                Terrain(ink: tint.opacity(0.34), center: UnitPoint(x: 0.74, y: 0.58))
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 68, height: 68)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 19))
                    .shadow(color: tint.opacity(0.16), radius: 8, y: 3)
                    .accessibilityHidden(true)
            }
            .frame(height: 120)
            .clipped()
            Divider()
            VStack(spacing: Spacing.m) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Even empty, a row of actions would add the stack's spacing below the text.
                if Actions.self != EmptyView.self {
                    HStack { actions }.controlSize(.large)
                }
            }
            .multilineTextAlignment(.center)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
        .surfaceCard(cornerRadius: Radius.panel)
        .frame(maxWidth: 440)
        .padding(Spacing.xl)
    }
}

extension WorkspaceState where Actions == EmptyView {
    init(title: String, symbol: String, detail: String, tint: Color = Palette.accent) {
        self.init(title: title, symbol: symbol, detail: detail, tint: tint) { EmptyView() }
    }
}

struct PanelHeading: View {
    let title: String
    let symbol: String
    let detail: String
    var tint: Color = Palette.accent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            SymbolTile(symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Several destinations use the overview scan. Keep the action and its progress together.
struct FolderScanPrompt: View {
    let section: AppModel.Section
    let detail: String
    let model: AppModel

    var body: some View {
        switch model.phase {
        case .scanning:
            WorkspaceState(title: "Scanning \(model.scope.title)", symbol: section.symbol,
                           detail: "Reading file sizes and dates.", tint: section.tint) {
                ProgressView().controlSize(.small)
                Button("Stop Scan") { model.cancelScan() }
            }
        case .failed(let message):
            WorkspaceState(title: "Couldn’t scan \(model.scope.title)", symbol: "exclamationmark.triangle",
                           detail: message, tint: Palette.ochre) {
                if model.scope == .downloads, model.access[.downloads] == .denied {
                    Button("Open Privacy Settings") { PrivacySettings.open(.filesAndFolders) }
                }
                Button("Try Again") { model.startScan() }.prominentActionStyle()
            }
        default:
            WorkspaceState(title: section.title, symbol: section.symbol, detail: detail, tint: section.tint) {
                Button("Scan \(model.scope.title)") { model.startScan() }.prominentActionStyle()
            }
        }
    }
}

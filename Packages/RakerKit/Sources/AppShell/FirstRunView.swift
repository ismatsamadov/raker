import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// First run: a welcome, then what to scan first. The scan itself is the last step; it runs
/// on the Overview, where the ring fills in live. Other permissions wait until a feature
/// needs them.
struct FirstRunView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            Group {
                switch model.firstRunStep {
                case .welcome:
                    WelcomeStep(model: model)
                case .chooseScope:
                    ChooseScopeStep(model: model)
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.xxl)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: model.firstRunStep)
        .fileImporter(isPresented: $model.isChoosingFirstRunFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.finishFirstRun(scanning: .folder(url))
            }
        }
    }
}

private struct WelcomeStep: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading) {
                HStack(spacing: Spacing.s) {
                    RakerIcon().frame(width: 44, height: 44)
                    Text("Raker").font(.title.bold())
                }
                Spacer()
                Text("See what’s taking up space.")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 255, alignment: .leading)
            }
            .foregroundStyle(.white)
            .padding(Spacing.xxl)
            .frame(width: 334, alignment: .leading)
            .background {
                ZStack {
                    Palette.forest
                    Terrain(ink: Palette.lichen.opacity(0.80), center: UnitPoint(x: 0.78, y: 0.43))
                    LinearGradient(colors: [.clear, Palette.forest.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                }
            }
            .clipped()
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Welcome to Raker")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Promise(symbol: "checkmark.shield.fill", tint: Palette.moss,
                        title: "Review before cleaning",
                        detail: "See each item and why it’s there. Most go to the Trash, where you can put them back.")
                Promise(symbol: "lock.fill", tint: Palette.lagoon,
                        title: "Private by design",
                        detail: "Your files stay on this Mac. Raker needs no account and collects no telemetry.")
                Promise(symbol: "heart.fill", tint: Palette.iris,
                        title: "Free and open source",
                        detail: "Every feature is free, and anyone can read the code.")
                Button {
                    model.firstRunStep = .chooseScope
                } label: {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                        .padding(.horizontal, Spacing.l)
                }
                .prominentActionStyle()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 930, minHeight: 410)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .surfaceCard(cornerRadius: 24)
    }
}

private struct ChooseScopeStep: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("What should Raker look at first?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("You can change folders later from the toolbar.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Palette.forest
                    Terrain(ink: Palette.lichen.opacity(0.5), center: UnitPoint(x: 0.88, y: 0.56))
                        .mask(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .trailing))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
            HStack(alignment: .top, spacing: Spacing.l) {
                ScopeCard(symbol: "arrow.down.circle.fill", tint: Palette.installers, title: "Downloads",
                          detail: "Installers and old downloads are often the easiest space to win back.",
                          note: "macOS will ask you to allow access.", isRecommended: true,
                          isSelected: model.firstRunChoice == .downloads) { model.firstRunChoice = .downloads }
                ScopeCard(symbol: "house.fill", tint: Palette.documents, title: "Home Folder",
                          detail: "Everything in your home folder, largest first.",
                          note: "macOS may ask about Desktop, Documents and Downloads.", isRecommended: false,
                          isSelected: model.firstRunChoice == .home) { model.firstRunChoice = .home }
                ScopeCard(symbol: "folder.fill", tint: Palette.archives, title: "A Folder",
                          detail: "Any folder you choose, such as a project or a drive.",
                          note: "Choosing it is all the permission Raker needs.", isRecommended: false,
                          isSelected: model.firstRunChoice == .folder) { model.firstRunChoice = .folder }
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.m) {
                Button("Back") { model.firstRunStep = .welcome }
                    .controlSize(.large)
                Spacer()
                Button {
                    model.startFirstScan()
                } label: {
                    Label(model.firstRunChoice == .folder ? "Choose Folder…" : "Start Scan",
                          systemImage: "sparkle.magnifyingglass")
                        .frame(minWidth: 160)
                }
                .prominentActionStyle()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            Label("Scanning only reads file names, sizes and dates.", systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 850)
    }
}

private struct Promise: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            SymbolTile(symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ScopeCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let note: String
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .center) {
                    SymbolTile(symbol, tint: tint, size: 40)
                    Spacer()
                    if isRecommended {
                        Badge(text: "Recommended", tint: Palette.moss)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Palette.accent : .secondary)
                        .accessibilityHidden(true)
                }
                // Symbols differ in height; a fixed row, as tall as the tile, keeps the titles
                // aligned across cards.
                .frame(height: 40)
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 190, maxHeight: .infinity, alignment: .topLeading)
            .surfaceCard(cornerRadius: Radius.panel)
            .overlay {
                shape.strokeBorder(isSelected ? Palette.accent : .clear, lineWidth: 2)
            }
            .contentShape(shape)
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .animation(Motion.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(note)
    }
}

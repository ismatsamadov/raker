import DesignSystem
import SwiftUI
import UniformTypeIdentifiers
import VisualizationKit

/// First run: a welcome, then what to scan first. The scan itself is the last step; it runs
/// on the Overview, where the ring fills in live. Other permissions wait until a feature
/// needs them.
struct FirstRunView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FirstRunBackdrop()
            Group {
                switch model.firstRunStep {
                case .welcome:
                    WelcomeStep(model: model)
                case .chooseScope:
                    ChooseScopeStep(model: model)
                }
            }
            .padding(.horizontal, Spacing.hero)
            .padding(.vertical, Spacing.xxl)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(Motion.smooth, value: model.firstRunStep)
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
        VStack(spacing: Spacing.xl) {
            HeroRing()
                .frame(width: 150, height: 150)
            VStack(spacing: Spacing.s) {
                Text("Welcome to Raker")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("See what's taking up space on your Mac, and free it safely.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Spacing.m) {
                Promise(symbol: "checkmark.shield.fill", tint: Palette.rebuildsAutomatically,
                        title: "Nothing is removed without your review",
                        detail: "You see every item and why it's there first. Most go to the Trash, so you can put them back.")
                Promise(symbol: "lock.fill", tint: Palette.review,
                        title: "Private by design",
                        detail: "No account and no telemetry. Raker looks at your files on this Mac and nowhere else.")
                Promise(symbol: "heart.fill", tint: Palette.media,
                        title: "Free and open source",
                        detail: "Every feature is free, and anyone can read the code.")
            }
            .frame(maxWidth: 460)
            Button {
                model.firstRunStep = .chooseScope
            } label: {
                Text("Continue")
                    .frame(minWidth: 160)
            }
            .prominentActionStyle()
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct ChooseScopeStep: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.s) {
                Text("What should Raker look at first?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("You can scan anything else later from the toolbar.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
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
            .frame(maxWidth: 780)
            HStack(spacing: Spacing.m) {
                Button("Back") { model.firstRunStep = .welcome }
                    .controlSize(.extraLarge)
                Button {
                    model.startFirstScan()
                } label: {
                    Label(model.firstRunChoice == .folder ? "Choose Folder…" : "Start Scan",
                          systemImage: "sparkle.magnifyingglass")
                        .frame(minWidth: 160)
                }
                .prominentActionStyle()
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
            }
            Text("Scanning reads names, sizes and dates. Nothing is changed or removed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Promise: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint.gradient)
                .frame(width: 32)
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
                    Image(systemName: symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(tint.gradient)
                    Spacer()
                    if isRecommended {
                        Badge(text: "Recommended", tint: tint)
                    }
                }
                // Symbols differ in height; a fixed row keeps the titles aligned across cards.
                .frame(height: 36)
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
                shape.strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(shape)
            .scaleEffect(isSelected ? 1 : 0.98)
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .animation(Motion.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(note)
    }
}

/// The category ring, turning slowly: a quiet picture of what Raker does.
private struct HeroRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let segments: [RingSegment] = [
        RingSegment(id: "installers", value: 32, color: Palette.installers, label: ""),
        RingSegment(id: "media", value: 22, color: Palette.media, label: ""),
        RingSegment(id: "developer", value: 16, color: Palette.developer, label: ""),
        RingSegment(id: "caches", value: 13, color: Palette.caches, label: ""),
        RingSegment(id: "documents", value: 10, color: Palette.documents, label: ""),
        RingSegment(id: "apps", value: 7, color: Palette.apps, label: ""),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120) / 120
            ZStack {
                DiskRingView(segments: segments, lineWidth: 18) { EmptyView() }
                    .rotationEffect(.degrees(reduceMotion ? 0 : turn * 360))
                Image(systemName: "sparkles")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(Color.accentColor.gradient)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Soft washes of the category colors behind the first-run screens.
private struct FirstRunBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            wash(Palette.installers, opacity: 0.20, radius: 420, at: UnitPoint(x: 0.08, y: 0.05))
            wash(Palette.media, opacity: 0.12, radius: 340, at: UnitPoint(x: 0.85, y: 0.0))
            wash(Palette.documents, opacity: 0.16, radius: 460, at: UnitPoint(x: 0.92, y: 0.95))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func wash(_ color: Color, opacity: Double, radius: CGFloat, at center: UnitPoint) -> some View {
        RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }
}

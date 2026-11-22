import AppKit
import DesignSystem
import RakerFoundation
import RakerModel
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            AccessSettings(model: model)
                .tabItem { Label("Access", systemImage: "lock.shield") }
                .tag(AppModel.SettingsTab.access)
            ExclusionsSettings(model: model)
                .tabItem { Label("Exclusions", systemImage: "hand.raised") }
                .tag(AppModel.SettingsTab.exclusions)
        }
        .frame(width: 640, height: 600)
    }
}

/// Locations Raker leaves alone, and originals it always keeps.
struct ExclusionsSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Raker never suggests or removes anything you exclude. A locked original is always the copy that stays when it has duplicates.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.userRules.isEmpty {
                ContentUnavailableView {
                    Label("No exclusions", systemImage: "hand.raised")
                } description: {
                    Text("Right-click any item and choose Never Suggest This or Lock as Original.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(model.userRules) { rule in
                    HStack(spacing: Spacing.s) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: rule.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Paths.lastComponent(rule.path))
                            Text(abbreviated(rule.path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Badge(text: rule.kind == .exclude ? "Never suggested" : "Locked original",
                              tint: rule.kind == .exclude ? Palette.review : Palette.rebuildsAutomatically)
                        Button {
                            model.removeUserRule(rule)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this rule")
                    }
                }
            }
            HStack {
                Button("Exclude a Folder…") { model.isChoosingExclusion = true }
                Spacer()
            }
        }
        .padding(Spacing.l)
        .fileImporter(isPresented: $model.isChoosingExclusion, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.addUserRule(.exclude, for: url.path)
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

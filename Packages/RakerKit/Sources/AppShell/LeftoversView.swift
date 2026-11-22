import AppCatalog
import AppKit
import DesignSystem
import SwiftUI

/// What removed apps left in the Library, by app, ready to remove through the Tray.
struct LeftoversView: View {
    @Bindable var model: AppModel

    var body: some View {
        content
            .navigationTitle("Leftovers")
            .toolbar {
                ToolbarItem {
                    Button {
                        model.loadLeftovers()
                    } label: {
                        Label("Look Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.leftoversPhase == .scanning)
                }
            }
            .onAppear {
                if model.leftoversPhase == .idle { model.loadLeftovers() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.leftovers.isEmpty {
            if model.leftoversPhase == .scanning {
                ProgressView("Looking for leftovers…")
                    .controlSize(.large)
            } else {
                WorkspaceState(title: "No leftovers", symbol: "checkmark.seal",
                               detail: "No removed app left anything in your Library.", tint: Palette.ochre)
            }
        } else {
            List {
                Section {
                    header
                }
                ForEach(model.leftovers) { leftovers in
                    Section {
                        ForEach(leftovers.files) { file in
                            AppFileRow(file: file, id: "leftovers:\(file.path)", selection: $model.leftoversSelection,
                                       measurement: model.leftoverMeasurements[file.path], model: model)
                        }
                    } header: {
                        HStack {
                            Text(leftovers.bundleID)
                                .textSelection(.enabled)
                            Spacer()
                            if isMeasured {
                                SizeText(model.size(of: leftovers))
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var isMeasured: Bool {
        !model.leftoverMeasurements.isEmpty
    }

    private var header: some View {
        let total = model.leftovers.reduce(UInt64(0)) { $0 &+ model.size(of: $1) }
        let hasCertain = model.leftovers.contains { $0.files.contains(where: \.isPreselected) }
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Label("Left behind by removed apps", systemImage: "app.dashed")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ochre)
                Spacer()
                if isMeasured {
                    SizeText(total)
                        .font(.rakerMetric)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text("""
            Only what macOS knew as an app counts: one that had a sandbox or saved windows, or a background \
            agent whose program is gone. Files no installed app could use are chosen for you, and everything \
            goes to the Trash.
            """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.stageCertainLeftovers()
            } label: {
                Label("Remove Leftovers…", systemImage: "trash")
                    .padding(.horizontal, Spacing.xs)
            }
            .prominentActionStyle()
            .disabled(!hasCertain)
            .help("Put the leftovers Raker is certain of in the Tray, then review")
        }
        .padding(Spacing.l)
        .surfaceCard(cornerRadius: Radius.panel)
    }
}

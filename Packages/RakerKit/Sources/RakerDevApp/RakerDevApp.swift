import AppKit
import AppShell
import SwiftUI

/// Development runner for the SwiftUI shell, until the Xcode app target exists.
/// `Scripts/run-dev-app.sh` wraps it in an app bundle so macOS treats it as a normal app.
@main
struct RakerDevApp: App {
    @NSApplicationDelegateAdaptor(DevAppDelegate.self) private var appDelegate
    private let model = AppModel()

    var body: some Scene {
        RakerScenes(model: model)
    }
}

@MainActor
final class DevAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM and debugger launches have no app bundle to supply a Dock icon.
        if Bundle.main.bundleURL.pathExtension != "app" {
            NSApp.setActivationPolicy(.regular)
            if let url = Bundle.module.url(forResource: "Raker", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
            }
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

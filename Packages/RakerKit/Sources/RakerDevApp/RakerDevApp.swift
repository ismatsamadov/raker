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
        // A bare executable starts without a Dock icon or menu bar.
        if Bundle.main.bundleIdentifier == nil {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

import AppKit
import SwiftUI

@main
struct StokerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item is an AppKit NSStatusItem (see StatusItemController) so it can
    // open a popover on click and the menu on right-click. SwiftUI just needs some scene.
    var body: some Scene {
        // commandsRemoved: no "Settings…" / Cmd-, opening a blank window while the popover has focus.
        Settings { EmptyView() }.commandsRemoved()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshotter.run(outputDirectory: args[i + 1])
            return
        }
        model.start()
        if args.contains("--demo") { startDemo() }
    }

    /// `--demo` cycles through every mood (and every plug/unplug transition) every few seconds.
    private func startDemo() {
        let order: [Mood] = [.shovelling, .vacation, .panicking, .shovelling, .onBreak, .vacation, .full, .panicking, .full]
        var i = 0
        model.preview = order[0]
        Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                i = (i + 1) % order.count
                self?.model.preview = order[i]
            }
        }
    }
}

import AppKit

/// Plain AppKit entry point. A SwiftUI `App` needs at least one scene, and the only
/// windowless option, an empty `Settings` scene, gets shown as a blank "Stoker Settings"
/// window when macOS launches or reopens the app. The menu bar item is an AppKit
/// NSStatusItem anyway (see StatusItemController), so SwiftUI's lifecycle isn't needed.
@main
enum StokerApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = quitOnlyMenu()
        withExtendedLifetime(delegate) { app.run() }
    }

    /// The menu bar is hidden (LSUIElement), but its shortcuts still fire while the
    /// popover has focus. Keep Cmd-Q working there; deliberately no Settings item.
    @MainActor private static func quitOnlyMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Stoker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let main = NSMenu()
        main.addItem(appItem)
        return main
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

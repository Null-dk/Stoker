import AppKit
import SwiftUI

@main
struct StokerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
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

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Image(systemName: model.mood.symbol)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.headline)
        Text(model.detail)
        Divider()

        Button("Poke the Worker") { model.poke() }
        Toggle("Speech Bubbles", isOn: $model.chatty)
        Toggle("Sound", isOn: $model.soundEnabled)
        Picker("Volume", selection: $model.volume) {
            ForEach(VolumeLevel.allCases) { Text($0.title).tag($0) }
        }
        .disabled(!model.soundEnabled)
        Divider()

        Picker("Size", selection: $model.size) {
            ForEach(WorkerSize.allCases) { Text($0.title).tag($0) }
        }
        Picker("Position", selection: $model.corner) {
            ForEach(ScreenCorner.allCases.filter { $0 != .custom || model.customOrigin != nil }) {
                Text($0.title).tag($0)
            }
        }
        Button(model.isMoving ? "Done Moving" : "Move Worker…") { model.toggleMoving() }
        Toggle("Stay on Top of Windows", isOn: $model.alwaysOnTop)
        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))
        if let err = model.loginError {
            Text("Login item: \(err)")
        }
        Divider()

        Picker("Preview Mood", selection: $model.preview) {
            Text("Live (follow the battery)").tag(Mood?.none)
            Divider()
            ForEach(Mood.allCases) { Text($0.title).tag(Mood?.some($0)) }
        }
        Divider()
        Button("Quit Stoker") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

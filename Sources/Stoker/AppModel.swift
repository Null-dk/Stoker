import AppKit
import ServiceManagement
import SwiftUI

enum WorkerSize: Int, CaseIterable, Identifiable {
    case small = 2, medium = 3, large = 4, huge = 5
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        }
    }
}

enum ScreenCorner: String, CaseIterable, Identifiable {
    case bottomRight, bottomLeft, topRight, topLeft, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottomRight: "Bottom Right"
        case .bottomLeft: "Bottom Left"
        case .topRight: "Top Right"
        case .topLeft: "Top Left"
        case .custom: "Where I Dragged It"
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    /// A transparent window in a corner of the screen.
    case desktop
    /// Hidden in the menu bar; click the icon to see him.
    case menuBar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop: "On the Desktop"
        case .menuBar: "In the Menu Bar"
        }
    }
}

enum VolumeLevel: String, CaseIterable, Identifiable {
    case quiet, normal, loud
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var value: Float {
        switch self {
        case .quiet: 0.25
        case .normal: 0.55
        case .loud: 0.9
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published private(set) var status = PowerMonitor.read()
    @Published var preview: Mood? { didSet { push() } }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled"); sound.enabled = soundEnabled }
    }
    @Published var volume: VolumeLevel {
        didSet { defaults.set(volume.rawValue, forKey: "volume"); sound.volume = volume.value }
    }
    @Published var chatty: Bool { didSet { defaults.set(chatty, forKey: "chatty"); push() } }
    @Published var size: WorkerSize { didSet { defaults.set(size.rawValue, forKey: "size"); push() } }
    @Published var corner: ScreenCorner { didSet { defaults.set(corner.rawValue, forKey: "corner"); push() } }
    @Published var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop"); push() } }
    @Published var display: DisplayMode {
        didSet {
            defaults.set(display.rawValue, forKey: "display")
            // Moving only applies to the desktop window; drop it rather than leave it stuck on.
            if display == .menuBar { isMoving = false }
            push()
        }
    }
    @Published var isMoving = false { didSet { push() } }
    @Published var loginError: String?

    var customOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: "customX") != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: "customX"), y: defaults.double(forKey: "customY"))
        }
        set {
            if let p = newValue {
                defaults.set(p.x, forKey: "customX")
                defaults.set(p.y, forKey: "customY")
            } else {
                defaults.removeObject(forKey: "customX")
                defaults.removeObject(forKey: "customY")
            }
        }
    }

    let sound = SoundBoard()
    private let power = PowerMonitor()
    private var stage: StageController?
    private var statusItem: StatusItemController?

    init() {
        defaults.register(defaults: [
            "soundEnabled": true, "volume": VolumeLevel.normal.rawValue, "chatty": true,
            "size": WorkerSize.medium.rawValue, "corner": ScreenCorner.bottomRight.rawValue, "alwaysOnTop": true,
            "display": DisplayMode.desktop.rawValue,
        ])
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        volume = VolumeLevel(rawValue: defaults.string(forKey: "volume") ?? "") ?? .normal
        chatty = defaults.bool(forKey: "chatty")
        size = WorkerSize(rawValue: defaults.integer(forKey: "size")) ?? .medium
        corner = ScreenCorner(rawValue: defaults.string(forKey: "corner") ?? "") ?? .bottomRight
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        display = DisplayMode(rawValue: defaults.string(forKey: "display") ?? "") ?? .desktop
        sound.enabled = soundEnabled
        sound.volume = volume.value
    }

    var mood: Mood { preview ?? Mood(status) }

    func start() {
        let stage = StageController(model: self)
        self.stage = stage
        statusItem = StatusItemController(model: self, stage: stage)
        power.onChange = { [weak self] s in
            Task { @MainActor in
                self?.status = s
                self?.push()
            }
        }
        power.start()
        push()
    }

    func push() {
        stage?.sync()
        statusItem?.sync()
    }

    func toggleMoving() {
        if isMoving, let origin = stage?.windowOrigin {
            customOrigin = origin
            corner = .custom
        }
        isMoving.toggle()
    }

    func poke() {
        // Poking an invisible worker is no fun: open the popover first in menu bar mode.
        if display == .menuBar { statusItem?.showPopover() }
        stage?.poke()
    }

    // MARK: Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        objectWillChange.send()
    }

    // MARK: Menu text

    var headline: String {
        if !status.hasBattery && preview == nil { return "Shovelling forever (no battery)" }
        return "\(mood.title) · \(status.hasBattery ? "\(status.percent)%" : "AC")"
    }

    var detail: String {
        if preview != nil { return "Previewing — real state: \(Mood(status).title.lowercased())" }
        switch mood {
        case .shovelling:
            var parts: [String] = []
            if let w = status.watts { parts.append("\(w) W charger") }
            if let m = status.minutesToFull { parts.append("full in \(Self.duration(m))") }
            return parts.isEmpty ? "Charging" : parts.joined(separator: " · ")
        case .onBreak: return "Plugged in; macOS paused charging"
        case .full: return "Fully charged. Unplug to rescue the worker."
        case .vacation, .panicking:
            if let m = status.minutesToEmpty { return "On battery · \(Self.duration(m)) left" }
            return "On battery"
        }
    }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

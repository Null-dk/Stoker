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

/// What the brass plaque on the furnace shows.
enum PlaqueMode: String, CaseIterable, Identifiable {
    case percentage, time, alternate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .percentage: "Percentage"
        case .time: "Time Remaining"
        case .alternate: "Alternate Both"
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
    @Published var plaqueMode: PlaqueMode {
        didSet { defaults.set(plaqueMode.rawValue, forKey: "plaqueMode"); push() }
    }
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
            "display": DisplayMode.desktop.rawValue, "plaqueMode": PlaqueMode.percentage.rawValue,
        ])
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        volume = VolumeLevel(rawValue: defaults.string(forKey: "volume") ?? "") ?? .normal
        chatty = defaults.bool(forKey: "chatty")
        plaqueMode = PlaqueMode(rawValue: defaults.string(forKey: "plaqueMode") ?? "") ?? .percentage
        size = WorkerSize(rawValue: defaults.integer(forKey: "size")) ?? .medium
        corner = ScreenCorner(rawValue: defaults.string(forKey: "corner") ?? "") ?? .bottomRight
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        display = DisplayMode(rawValue: defaults.string(forKey: "display") ?? "") ?? .desktop
        sound.enabled = soundEnabled
        sound.volume = volume.value
        liveMood = Mood(status)
    }

    var mood: Mood { preview ?? liveMood }

    /// The battery-driven mood, after smoothing out what macOS reports right after plugging in.
    private(set) var liveMood: Mood = .shovelling
    /// When the charger was connected; nil on battery.
    private var pluggedInAt: Date?
    private var settleTimers: [Timer] = []
    /// The battery current lags behind the plug, so for a few seconds it can still read
    /// "draining", and Macs that don't say why they aren't charging briefly look paused.
    static let breakGrace: TimeInterval = 6
    /// "Not charging, no reason given" for longer than this is a pause after all.
    static let warmUpLimit: TimeInterval = 120

    private func updateLiveMood() {
        var raw = Mood(status)
        if !raw.isPluggedIn {
            pluggedInAt = nil
            settleTimers.forEach { $0.invalidate() }
            settleTimers = []
        } else if pluggedInAt == nil {
            pluggedInAt = Date()
            // The 30 s poll may not land in time; look again once each grace period is up.
            scheduleRecheck(after: Self.breakGrace + 0.1)
            scheduleRecheck(after: Self.warmUpLimit + 0.1)
        }
        let age = pluggedInAt.map { Date().timeIntervalSince($0) } ?? .infinity

        if age < Self.breakGrace && raw == .overworked {
            // A stale "draining" reading from before the plug went in.
            raw = status.isCharging ? .shovelling : status.notChargingReason == 0 ? .warmingUp : .onBreak
        }
        if raw == .warmingUp && age >= Self.warmUpLimit { raw = .onBreak }
        if raw == .onBreak && age < Self.breakGrace && !liveMood.isPluggedIn {
            // No reason to go on (older Macs): give charging a moment to start before he sits down.
            return
        }
        liveMood = raw
    }

    private func scheduleRecheck(after delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.status = PowerMonitor.read()
                self.updateLiveMood()
                self.push()
            }
        }
        // .common so it still fires while the settings menu is open.
        RunLoop.main.add(timer, forMode: .common)
        settleTimers.append(timer)
    }

    func start() {
        let stage = StageController(model: self)
        self.stage = stage
        statusItem = StatusItemController(model: self, stage: stage)
        power.onChange = { [weak self] s in
            Task { @MainActor in
                self?.status = s
                self?.updateLiveMood()
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
        if preview != nil { return "Previewing — real state: \(liveMood.title.lowercased())" }
        switch mood {
        case .shovelling:
            var parts: [String] = []
            if let w = status.watts { parts.append("\(w) W charger") }
            if let load = status.chargerLoad { parts.append("Mac using \(Int((load * 100).rounded()))% of it") }
            if let m = status.minutesToFull { parts.append("full in \(Self.duration(m))") }
            return parts.isEmpty ? "Charging" : parts.joined(separator: " · ")
        case .warmingUp: return "Plugged in; waiting for macOS to start charging"
        case .onBreak: return "Plugged in; macOS paused charging"
        case .overworked:
            var parts: [String] = []
            if let w = status.watts { parts.append("\(w) W charger can't keep up") }
            if let d = status.deficitWatts { parts.append("battery losing \(d) W") }
            return parts.isEmpty ? "Plugged in, but the battery is draining" : parts.joined(separator: " · ")
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

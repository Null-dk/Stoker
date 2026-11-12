import AppKit

/// The menu bar item. On the desktop it is a plain icon with the settings menu.
/// In menu bar mode it shows an animated mini worker: click to open the furnace in a
/// popover, right-click (or Control-click) for the settings menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private unowned let model: AppModel
    private unowned let stage: StageController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let popover = NSPopover()

    private var iconTimer: Timer?
    private var iconKey: (Mood, Effort?, DisplayMode)?
    private var iconFrame = 0
    private var screensAsleep = false
    private var menuOpen = false
    private var popoverClosedAt = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel, stage: StageController) {
        self.model = model
        self.stage = stage
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false

        let vc = NSViewController()
        vc.view = stage.popoverContent
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                Task { @MainActor in
                    self?.screensAsleep = n.name == NSWorkspace.screensDidSleepNotification
                    self?.iconKey = nil
                    self?.sync()
                }
            })
        }
    }

    func sync() {
        // Desktop mode keeps the native "click opens the menu" behaviour.
        // Leave the menu alone while it is being tracked (showMenu restores it on close).
        if !menuOpen { statusItem.menu = model.display == .desktop ? menu : nil }
        if model.display == .desktop, popover.isShown { popover.performClose(nil) }
        popover.contentSize = StageController.pixelSize(model.size)
        statusItem.button?.toolTip = model.display == .menuBar
            ? "Stoker: click to see the worker, right-click for settings"
            : "Stoker"
        updateIcon()
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu { showMenu() } else { togglePopover() }
    }

    private func showMenu() {
        if popover.isShown { popover.performClose(nil) }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = model.display == .desktop ? menu : nil
    }

    func togglePopover() {
        guard model.display == .menuBar else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(popoverClosedAt) > 0.3 {
            // A transient popover already closes on the mouse-down of this very click;
            // don't reopen it on the mouse-up.
            showPopover()
        }
    }

    func showPopover() {
        guard model.display == .menuBar, !popover.isShown, let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        // Count as visible straight away so sounds fired right after (like a poke) aren't dropped.
        stage.popoverShown = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidShow(_ notification: Notification) { stage.popoverShown = true }
    func popoverWillClose(_ notification: Notification) { popoverClosedAt = Date() }
    func popoverDidClose(_ notification: Notification) { stage.popoverShown = false }

    // MARK: Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let mood = model.mood
        let effort = Effort(model.status)
        let speedKey = mood == .shovelling ? effort : nil
        if let k = iconKey, k.0 == mood, k.1 == speedKey, k.2 == model.display { return }
        iconKey = (mood, speedKey, model.display)
        iconTimer?.invalidate()
        iconTimer = nil

        switch model.display {
        case .desktop:
            let img = NSImage(systemSymbolName: mood.symbol, accessibilityDescription: mood.title)
            img?.isTemplate = true
            button.image = img
            button.setAccessibilityLabel("Stoker: \(mood.title)")
        case .menuBar:
            let anim = MenuBarIcon.animation(for: mood, effort: effort)
            iconFrame = 0
            button.image = anim.frames.first
            button.setAccessibilityLabel("Stoker: \(mood.title)")
            // A frozen frame is fine while the screens are off.
            guard anim.frames.count > 1, !screensAsleep else { return }
            let timer = Timer(timeInterval: anim.frameDuration, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.iconFrame = (self.iconFrame + 1) % anim.frames.count
                    self.statusItem.button?.image = anim.frames[self.iconFrame]
                }
            }
            // .common so he keeps moving while a menu is open.
            RunLoop.main.add(timer, forMode: .common)
            iconTimer = timer
        }
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(info(model.headline))
        menu.addItem(info(model.detail))
        menu.addItem(.separator())

        menu.addItem(ActionItem("Poke the Worker") { [model] in model.poke() })
        menu.addItem(ActionItem("Speech Bubbles", checked: model.chatty) { [model] in model.chatty.toggle() })
        menu.addItem(ActionItem("Sound", checked: model.soundEnabled) { [model] in model.soundEnabled.toggle() })
        menu.addItem(submenu("Volume", enabled: model.soundEnabled, VolumeLevel.allCases.map { v in
            ActionItem(v.title, checked: model.volume == v) { [model] in model.volume = v }
        }))
        menu.addItem(submenu("Plaque Shows", PlaqueMode.allCases.map { p in
            ActionItem(p.title, checked: model.plaqueMode == p) { [model] in model.plaqueMode = p }
        }))
        menu.addItem(.separator())

        menu.addItem(submenu("Show Worker", DisplayMode.allCases.map { d in
            ActionItem(d.title, checked: model.display == d) { [model] in model.display = d }
        }))
        menu.addItem(submenu("Size", WorkerSize.allCases.map { s in
            ActionItem(s.title, checked: model.size == s) { [model] in model.size = s }
        }))
        if model.display == .desktop {
            let corners = ScreenCorner.allCases.filter { $0 != .custom || model.customOrigin != nil }
            menu.addItem(submenu("Position", corners.map { c in
                ActionItem(c.title, checked: model.corner == c) { [model] in model.corner = c }
            }))
            menu.addItem(ActionItem(model.isMoving ? "Done Moving" : "Move Worker…") { [model] in model.toggleMoving() })
            menu.addItem(ActionItem("Stay on Top of Windows", checked: model.alwaysOnTop) { [model] in
                model.alwaysOnTop.toggle()
            })
        }
        menu.addItem(ActionItem("Launch at Login", checked: model.launchAtLogin) { [model] in
            model.setLaunchAtLogin(!model.launchAtLogin)
        })
        if let err = model.loginError { menu.addItem(info("Login item: \(err)")) }
        menu.addItem(.separator())

        var moods: [NSMenuItem] = [ActionItem("Live (follow the battery)", checked: model.preview == nil) { [model] in
            model.preview = nil
        }]
        moods.append(.separator())
        moods += Mood.allCases.map { m in
            ActionItem(m.title, checked: model.preview == m) { [model] in model.preview = m }
        }
        menu.addItem(submenu("Preview Mood", moods))
        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit Stoker", key: "q") { NSApp.terminate(nil) })
    }

    private func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, enabled: Bool = true, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        sub.autoenablesItems = false
        items.forEach(sub.addItem)
        item.submenu = sub
        item.isEnabled = enabled
        return item
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", checked: Bool = false, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func fire() { handler() }
}

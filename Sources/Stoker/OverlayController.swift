import AppKit
import SpriteKit

/// A borderless, transparent, click-through window that never takes focus.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController: NSObject {
    private unowned let model: AppModel
    private let window: OverlayWindow
    private let skView: SKView
    private let scene: StokerScene
    private var hasEnteredScene = false
    private var placedFor: (WorkerSize, ScreenCorner)?
    private var observers: [NSObjectProtocol] = []

    var windowOrigin: CGPoint { window.frame.origin }

    init(model: AppModel) {
        self.model = model
        scene = StokerScene(size: StokerScene.logicalSize)
        let size = Self.pixelSize(model.size)
        window = OverlayWindow(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        skView = SKView(frame: NSRect(origin: .zero, size: size))
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 30
        skView.autoresizingMask = [.width, .height]
        window.contentView = skView

        scene.onSound = { [weak model] s, gain, pan in
            model?.sound.play(s, gain: gain, pan: pan)
        }
        skView.presentScene(scene)

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.placedFor = nil; self?.sync() }
        })
        observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePaused() }
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                Task { @MainActor in
                    self?.screensAsleep = n.name == NSWorkspace.screensDidSleepNotification
                    self?.updatePaused()
                }
            })
        }

        window.orderFrontRegardless()
    }

    private var screensAsleep = false

    private func updatePaused() {
        // Don't burn battery animating something nobody can see.
        skView.isPaused = screensAsleep || !window.occlusionState.contains(.visible)
    }

    static func pixelSize(_ s: WorkerSize) -> CGSize {
        CGSize(width: StokerScene.logicalSize.width * CGFloat(s.rawValue),
               height: StokerScene.logicalSize.height * CGFloat(s.rawValue))
    }

    func sync() {
        // Window level: floating above apps, or sitting on the desktop behind them.
        window.level = model.alwaysOnTop
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        // Interactivity
        window.ignoresMouseEvents = !model.isMoving
        scene.dragEnabled = model.isMoving
        scene.chatty = model.chatty

        // Size & position
        if placedFor == nil || placedFor! != (model.size, model.corner) {
            place()
            placedFor = (model.size, model.corner)
        }

        // Lower frame rate on battery
        skView.preferredFramesPerSecond = model.status.onAC ? 30 : 20

        let mood = model.mood
        scene.apply(mood: mood, status: model.status, animated: hasEnteredScene)
        hasEnteredScene = true
    }

    func poke() { scene.poke() }

    private func place() {
        let size = Self.pixelSize(model.size)
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let m: CGFloat = 8
        var origin: CGPoint
        switch model.corner {
        case .bottomRight: origin = CGPoint(x: vf.maxX - size.width - m, y: vf.minY + m)
        case .bottomLeft: origin = CGPoint(x: vf.minX + m, y: vf.minY + m)
        case .topRight: origin = CGPoint(x: vf.maxX - size.width - m, y: vf.maxY - size.height - m)
        case .topLeft: origin = CGPoint(x: vf.minX + m, y: vf.maxY - size.height - m)
        case .custom:
            origin = model.customOrigin ?? CGPoint(x: vf.maxX - size.width - m, y: vf.minY + m)
            // Pull back on-screen if the display arrangement changed.
            let frame = NSRect(origin: origin, size: size)
            if !NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
                origin = CGPoint(x: vf.maxX - size.width - m, y: vf.minY + m)
            }
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

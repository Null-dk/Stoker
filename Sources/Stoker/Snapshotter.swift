import AppKit
import SpriteKit

/// `Stoker --snapshot <dir>` renders each mood to a PNG (plus a sheet of worker poses) and exits.
/// Handy for checking the art without unplugging anything.
@MainActor
enum Snapshotter {
    private static var window: NSWindow?

    static func run(outputDirectory dir: String) {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        writeSheet(to: url.appendingPathComponent("poses.png"))
        writeMenuBarSheet(to: url.appendingPathComponent("menubar.png"))
        write(upscale(icon().makeImage(), by: 16), to: url.appendingPathComponent("icon_1024.png"))

        let scale: CGFloat = 4
        let size = CGSize(width: StokerScene.logicalSize.width * scale, height: StokerScene.logicalSize.height * scale)
        let view = SKView(frame: NSRect(origin: .zero, size: size))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = view
        win.level = .floating
        win.orderFrontRegardless()
        window = win

        let scene = StokerScene(size: StokerScene.logicalSize)
        scene.backgroundColor = NSColor(calibratedRed: 0.33, green: 0.4, blue: 0.5, alpha: 1)
        view.presentScene(scene)

        let shots: [(String, Mood, PowerStatus)] = [
            ("shovelling", .shovelling, PowerStatus(hasBattery: true, onAC: true, isCharging: true, percent: 64, watts: 96)),
            ("break", .onBreak, PowerStatus(hasBattery: true, onAC: true, isCharging: false, percent: 80, watts: 67)),
            ("full", .full, PowerStatus(hasBattery: true, onAC: true, isCharging: false, isCharged: true, percent: 100, watts: 67)),
            ("vacation", .vacation, PowerStatus(hasBattery: true, onAC: false, percent: 57)),
            ("panicking", .panicking, PowerStatus(hasBattery: true, onAC: false, percent: 12)),
        ]

        func step(_ i: Int) {
            guard i < shots.count else { NSApp.terminate(nil); return }
            let (name, mood, status) = shots[i]
            scene.apply(mood: mood, status: status, animated: false)
            scene.say(mood.lines(watts: status.watts).first ?? "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                if let tex = view.texture(from: scene) {
                    write(upscale(tex.cgImage(), by: 3), to: url.appendingPathComponent("\(name).png"))
                }
                step(i + 1)
            }
        }
        step(0)
    }

    private static func writeSheet(to url: URL) {
        var poses: [Pose] = WorkerArt.shovelCycle.frames
        poses += [WorkerArt.stand, WorkerArt.surprised, WorkerArt.stretch, WorkerArt.sit, WorkerArt.sitSip,
                  WorkerArt.recline, WorkerArt.reclineSip, WorkerArt.walk(0), WorkerArt.walk(1),
                  WorkerArt.walk(2), WorkerArt.walk(3), WorkerArt.wave(0), WorkerArt.wave(1)]
        let cols = 8
        let rows = (poses.count + cols - 1) / cols
        let cw = WorkerArt.width + 2, ch = WorkerArt.height + 2
        let sheet = PixelCanvas(cols * cw, rows * ch)
        sheet.fill(0, 0, sheet.width, sheet.height, RGBA(0x55667F))
        for (i, pose) in poses.enumerated() {
            let c = WorkerArt.render(pose)
            let ox = (i % cols) * cw + 1, oy = (i / cols) * ch + 1
            for y in 0..<c.height { for x in 0..<c.width { if let p = c.get(x, y) { sheet.set(ox + x, oy + y, p) } } }
        }
        write(upscale(sheet.makeImage(), by: 6), to: url)
    }

    /// Every menu bar icon frame, one row per mood, on light and dark menu bar backgrounds.
    private static func writeMenuBarSheet(to url: URL) {
        let crop = MenuBarIcon.crop
        let cw = Int(crop.width) + 4, ch = Int(crop.height) + 4
        let rows = Mood.allCases.map { MenuBarIcon.poses(for: $0) }
        let cols = rows.map(\.count).max() ?? 1
        let sheet = PixelCanvas(cols * cw, rows.count * ch * 2)
        sheet.fill(0, 0, sheet.width, sheet.height / 2, RGBA(0xE8E8EC))
        sheet.fill(0, sheet.height / 2, sheet.width, sheet.height / 2, RGBA(0x2A2A30))
        for half in 0..<2 {
            for (r, poses) in rows.enumerated() {
                for (i, pose) in poses.enumerated() {
                    let c = WorkerArt.render(pose)
                    let ox = i * cw + 2 - Int(crop.minX), oy = (half * rows.count + r) * ch + 2 - Int(crop.minY)
                    for y in 0..<c.height { for x in 0..<c.width { if let p = c.get(x, y) { sheet.set(ox + x, oy + y, p) } } }
                }
            }
        }
        write(upscale(sheet.makeImage(), by: 4), to: url)
    }

    /// 64×64 pixel-art app icon: the stoker mid-throw next to a roaring furnace door.
    private static func icon() -> PixelCanvas {
        let n = 64
        let c = PixelCanvas(n, n)
        // Rounded squircle background (macOS icon grid leaves ~10% margin)
        let m = 6, r: CGFloat = 11
        for y in m..<(n - m) {
            for x in m..<(n - m) {
                let cx = min(max(CGFloat(x) + 0.5, CGFloat(m) + r), CGFloat(n - m) - r)
                let cy = min(max(CGFloat(y) + 0.5, CGFloat(m) + r), CGFloat(n - m) - r)
                guard (P(CGFloat(x) + 0.5, CGFloat(y) + 0.5) - P(cx, cy)).length <= r else { continue }
                c.set(x, y, y < 46 ? RGBA(0x3A2C3F) : Pal.floor)
            }
        }
        c.fill(m + 2, 46, n - 2 * m - 4, 1, Pal.floorLight)
        // Furnace door with fire
        c.fill(38, 26, 18, 20, Pal.brick)
        c.fill(38, 26, 18, 1, Pal.ironLight)
        c.fill(39, 30, 16, 14, Pal.iron)
        c.fill(40, 31, 14, 12, Pal.soot)
        let fire = PropArt.fire(level: 3, frame: 1)
        for y in 0..<fire.height { for x in 0..<fire.width { if let p = fire.get(x, y) { c.set(40 + x, 31 + y, p) } } }
        // Worker
        let w = WorkerArt.render(WorkerArt.thrust)
        for y in 0..<w.height {
            for x in 0..<w.width { if let p = w.get(x, y) { c.set(x + 1, y + 11, p) } }
        }
        // Flying coal
        for (x, y) in [(42, 22), (45, 24), (47, 27)] { c.fill(x, y, 2, 2, Pal.coal); c.set(x, y, Pal.coalHi) }
        return c
    }

    private static func upscale(_ img: CGImage, by k: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: img.width * k, height: img.height * k, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width * k, height: img.height * k))
        return ctx.makeImage()!
    }

    private static func write(_ img: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

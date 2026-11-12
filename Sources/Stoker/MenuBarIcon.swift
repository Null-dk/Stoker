import AppKit

/// A tiny animated worker for the menu bar. Drawn from the same poses as the scene,
/// at one art pixel per device pixel on Retina (half a point), so he fits in the bar.
@MainActor
enum MenuBarIcon {
    struct Animation {
        let frames: [NSImage]
        let frameDuration: TimeInterval
    }

    static func animation(for mood: Mood, effort: Effort) -> Animation {
        let frames = images(for: mood)
        switch mood {
        case .shovelling:
            return Animation(frames: frames, frameDuration: effort.cycle / Double(frames.count))
        case .overworked:
            return Animation(frames: frames, frameDuration: Effort.overworkedCycle / Double(frames.count))
        case .onBreak, .vacation: return Animation(frames: frames, frameDuration: 0.6)
        case .warmingUp: return Animation(frames: frames, frameDuration: 0.25)
        case .full: return Animation(frames: frames, frameDuration: 0.35)
        case .panicking: return Animation(frames: frames, frameDuration: 0.12)
        }
    }

    /// Poses per mood. Repeats hold a pose longer so the sip/blink frames read as occasional.
    static func poses(for mood: Mood) -> [Pose] {
        switch mood {
        case .shovelling: WorkerArt.shovelCycle.frames
        case .overworked: WorkerArt.sweatyShovelCycle
        case .warmingUp: WorkerArt.waitTapCycle
        case .onBreak: Array(repeating: WorkerArt.sit, count: 5) + Array(repeating: WorkerArt.sitSip, count: 2)
        case .full: [WorkerArt.wave(0), WorkerArt.wave(1)]
        case .vacation: Array(repeating: WorkerArt.recline, count: 10) + Array(repeating: WorkerArt.reclineSip, count: 3)
        case .panicking: (0..<4).map { WorkerArt.walk($0) }
        }
    }

    private static var cache: [Mood: [NSImage]] = [:]

    private static func images(for mood: Mood) -> [NSImage] {
        if let c = cache[mood] { return c }
        let imgs = poses(for: mood).map { image(WorkerArt.render($0)) }
        cache[mood] = imgs
        return imgs
    }

    /// One crop shared by every mood so the icon never changes width (which would shove
    /// neighbouring menu bar items around).
    static let crop: CGRect = {
        var minX = WorkerArt.width, minY = WorkerArt.height, maxX = -1, maxY = -1
        for mood in Mood.allCases {
            for pose in poses(for: mood) {
                let c = WorkerArt.render(pose)
                for y in 0..<c.height {
                    for x in 0..<c.width where c.get(x, y) != nil {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
        }
        guard maxX >= minX else { return CGRect(x: 0, y: 0, width: WorkerArt.width, height: WorkerArt.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }()

    static func croppedImage(_ canvas: PixelCanvas) -> CGImage {
        canvas.makeImage().cropping(to: crop) ?? canvas.makeImage()
    }

    private static func image(_ canvas: PixelCanvas) -> NSImage {
        let cg = croppedImage(canvas)
        let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        img.isTemplate = false
        return img
    }
}

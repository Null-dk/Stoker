import AppKit
import SpriteKit

/// Procedurally painted pixel-art props. All functions return canvases/textures; callers cache.
enum PropArt {
    // MARK: Furnace (40×46). Door interior is cols 5…18, rows 28…39.

    static func furnace() -> PixelCanvas {
        let c = PixelCanvas(40, 46)
        var rng = SplitMix(7)

        // Brick body
        for y in 17...42 {
            let course = (y - 17) / 3
            let inCourse = (y - 17) % 3
            for x in 1...38 {
                if inCourse == 2 { c.set(x, y, Pal.mortar); continue }
                let shifted = x + (course % 2 == 0 ? 0 : 3)
                if shifted % 6 == 0 { c.set(x, y, Pal.mortar); continue }
                c.set(x, y, Pal.brick)
            }
            // Random darker bricks
            if inCourse == 0 {
                for bx in stride(from: course % 2 == 0 ? 1 : -2, through: 38, by: 6) where rng.unit() < 0.3 {
                    for x in max(1, bx)..<min(39, bx + 5) { c.set(x, y, Pal.brickShade); c.set(x, y + 1, Pal.brickShade) }
                }
            }
        }
        c.fill(1, 17, 1, 26, Pal.brickShade)
        c.fill(38, 17, 1, 26, Pal.mortar)

        // Top trim with rivets, plinth
        c.fill(0, 14, 40, 3, Pal.iron)
        c.fill(0, 14, 40, 1, Pal.ironLight)
        for x in stride(from: 2, to: 40, by: 4) { c.set(x, 15, Pal.ironDark) }
        c.fill(0, 43, 40, 3, Pal.iron)
        c.fill(0, 43, 40, 1, Pal.ironLight)
        c.fill(0, 45, 40, 1, Pal.ironDark)

        // Chimney
        c.fill(24, 2, 8, 12, Pal.iron)
        c.fill(25, 2, 1, 12, Pal.ironLight)
        c.fill(31, 2, 1, 12, Pal.ironDark)
        c.fill(24, 6, 8, 1, Pal.ironDark)
        c.fill(24, 10, 8, 1, Pal.ironDark)
        c.fill(23, 0, 10, 2, Pal.iron)
        c.fill(23, 0, 10, 1, Pal.ironLight)

        // Door frame + dark interior
        c.fill(4, 27, 16, 14, Pal.iron)
        c.fill(4, 27, 16, 1, Pal.ironLight)
        c.fill(5, 28, 14, 12, Pal.soot)
        for (x, y) in [(4, 27), (19, 27), (4, 40), (19, 40)] { c.set(x, y, Pal.ironDark) }
        // Door flap swung open to the left
        c.fill(0, 28, 4, 12, Pal.iron)
        c.fill(0, 28, 1, 12, Pal.ironLight)
        c.fill(3, 28, 1, 12, Pal.ironDark)
        c.set(1, 33, Pal.brass); c.set(2, 33, Pal.brass)

        // Brass plaque for the percentage
        c.fill(4, 19, 16, 7, Pal.brass)
        c.fill(4, 25, 16, 1, Pal.brassShade)
        c.fill(19, 19, 1, 7, Pal.brassShade)
        c.set(4, 19, nil); c.set(19, 19, nil); c.set(4, 25, nil); c.set(19, 25, nil)

        // Pressure gauge
        let gc = P(28.5, 22.5)
        for y in 18...27 {
            for x in 23...34 {
                let d = (P(CGFloat(x) + 0.5, CGFloat(y) + 0.5) - gc).length
                if d <= 2.4 { c.set(x, y, Pal.paper) } else if d <= 3.4 { c.set(x, y, Pal.ironDark) }
            }
        }
        c.set(28, 22, Pal.red); c.set(29, 21, Pal.red); c.set(30, 20, Pal.red)
        // Pipe from gauge up to the trim
        c.fill(28, 17, 1, 2, Pal.ironDark)
        return c
    }

    /// Flames that fit the furnace door (14×12). Level 0 = embers … 3 = roaring.
    static func fire(level: Int, frame: Int) -> PixelCanvas {
        let w = 14, h = 12
        let c = PixelCanvas(w, h)
        var rng = SplitMix(UInt64(level * 100 + frame + 1))
        let maxH: [CGFloat] = [1.5, 4.5, 7.5, 11.5]
        let top = maxH[max(0, min(3, level))]
        if level > 0 {
            for x in 0..<w {
                let bell = sin(.pi * (CGFloat(x) + 0.5) / CGFloat(w))
                let colH = Int((top * (0.45 + 0.55 * bell) + CGFloat(rng.int(-1...1))).rounded())
                guard colH > 0 else { continue }
                for yy in 0..<colH {
                    let rel = CGFloat(yy) / CGFloat(max(colH, 1)) + (1 - bell) * 0.35
                    let col: RGBA
                    if rel < 0.2 && level >= 2 { col = Pal.fireWhite }
                    else if rel < 0.45 { col = Pal.fireYellow }
                    else if rel < 0.75 { col = Pal.fireOrange }
                    else { col = Pal.fireRed }
                    c.set(x, h - 1 - yy, col)
                }
                // Occasional detached flicker
                if rng.unit() < 0.15 && colH + 2 < h { c.set(x, h - 1 - colH - 1, Pal.fireRed) }
            }
        }
        // Coal bed with embers
        for x in 0..<w {
            let r = rng.unit()
            let ember: RGBA = r < 0.35 ? Pal.ember : (r < 0.6 ? Pal.fireRed : (r < 0.75 ? Pal.fireOrange : Pal.coal))
            c.set(x, h - 1, level == 0 ? ember : (rng.unit() < 0.5 ? Pal.fireRed : Pal.ember))
            if level == 0 && rng.unit() < 0.35 { c.set(x, h - 2, rng.unit() < 0.5 ? Pal.ember : Pal.fireRed) }
        }
        return c
    }

    // MARK: Coal

    static func mound(width w: Int, height h: Int, seed: UInt64 = 3) -> PixelCanvas {
        let c = PixelCanvas(w, h)
        var rng = SplitMix(seed)
        var noise = (0..<w).map { _ in CGFloat(rng.unit() * 2 - 1) }
        noise = noise.indices.map { i in
            (noise[max(0, i - 1)] + noise[i] * 2 + noise[min(w - 1, i + 1)]) / 4
        }
        let cx = CGFloat(w - 1) / 2
        for x in 0..<w {
            let d = abs(CGFloat(x) - cx) / (CGFloat(w) / 2)
            let prof = CGFloat(h) * pow(max(0, 1 - d * d), 0.6)
            let colH = min(h, max(0, Int((prof + noise[x] * 1.4).rounded())))
            for yy in 0..<colH {
                let y = h - 1 - yy
                let col: RGBA
                if yy == colH - 1 { col = rng.unit() < 0.55 ? Pal.coalHi : Pal.coalMid }
                else {
                    let r = rng.unit()
                    col = r < 0.68 ? Pal.coal : (r < 0.92 ? Pal.coalMid : Pal.coalHi)
                }
                c.set(x, y, col)
            }
        }
        return c
    }

    /// Height of the mound surface (in pixels above its base) at a column; used to land falling coal.
    static func moundHeight(width w: Int, height h: Int, atColumn x: CGFloat) -> CGFloat {
        let cx = CGFloat(w - 1) / 2
        let d = abs(x - cx) / (CGFloat(w) / 2)
        return CGFloat(h) * pow(max(0, 1 - d * d), 0.6)
    }

    static func chunk(_ variant: Int) -> PixelCanvas {
        let c = PixelCanvas(2, 2)
        c.fill(0, 0, 2, 2, Pal.coal)
        c.set(variant % 2, 0, Pal.coalHi)
        if variant == 2 { c.set(1, 1, nil) }
        return c
    }

    // MARK: Charger

    static func plug() -> PixelCanvas {
        let c = PixelCanvas(10, 14)
        // Strain relief
        c.fill(3, 0, 4, 3, Pal.mugShade)
        c.fill(3, 0, 1, 3, Pal.paper)
        // Body
        c.fill(1, 3, 8, 8, Pal.paper)
        c.fill(1, 3, 8, 1, Pal.white)
        c.fill(8, 3, 1, 8, Pal.mugShade)
        c.fill(1, 10, 8, 1, Pal.mugShade)
        c.set(1, 3, nil); c.set(8, 3, nil)
        // Lightning bolt
        c.blit(["..#", ".#.", "###", ".#.", "#.."], x: 3, y: 5, palette: ["#": Pal.yellow])
        // USB-C tip
        c.fill(3, 11, 4, 3, Pal.metal)
        c.fill(6, 11, 1, 3, Pal.metalShade)
        c.fill(4, 12, 2, 1, Pal.ironDark)
        return c
    }

    static func cable(length: Int) -> PixelCanvas {
        let c = PixelCanvas(2, length)
        c.fill(0, 0, 2, length, Pal.mug)
        c.fill(1, 0, 1, length, Pal.mugShade)
        return c
    }

    // MARK: Break & vacation props

    static func shovel() -> PixelCanvas {
        let c = PixelCanvas(10, 24)
        WorkerArt.paintShovel(c, ShovelPose(grip: P(6.5, 2), tip: P(3.5, 23), loaded: false))
        return c
    }

    static func bucket() -> PixelCanvas {
        let c = PixelCanvas(10, 7)
        for r in 0..<7 {
            let inset = r < 3 ? 2 : 1
            let col = r == 0 ? Pal.metalLight : (r == 3 ? Pal.metalShade : Pal.metal)
            c.fill(inset, r, 10 - inset * 2, 1, col)
            c.set(10 - inset - 1, r, Pal.metalShade)
        }
        c.fill(0, 6, 10, 1, Pal.metalShade)
        return c
    }

    static func chair() -> PixelCanvas {
        let c = PixelCanvas(26, 18)
        // Wooden frame
        c.line(P(2, 0), P(9, 17), Pal.woodShade)
        c.line(P(3, 0), P(10, 17), Pal.wood)
        c.line(P(20, 11), P(22, 17), Pal.wood)
        c.line(P(8, 11), P(17, 17), Pal.woodShade)
        c.line(P(10, 12), P(20, 11), Pal.woodShade)
        // Striped fabric draped along the frame
        let path = [P(4.5, 1.5), P(11.5, 11.5), P(19.5, 10.5)]
        var dist: CGFloat = 0
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let len = (b - a).length
            var t: CGFloat = 0
            while t <= len {
                let p = a + (b - a).normalized * t
                let stripe = Int((dist + t) / 2.5) % 2 == 0
                c.capsule(p, p, radius: 1.3, stripe ? Pal.stripeA : Pal.stripeB)
                t += 0.5
            }
            dist += len
        }
        return c
    }

    static func parasol() -> PixelCanvas {
        let w = 32, h = 36
        let c = PixelCanvas(w, h)
        // Pole
        c.fill(15, 5, 1, 31, Pal.wood)
        c.fill(16, 5, 1, 31, Pal.woodShade)
        // Canopy dome
        let cx = CGFloat(w) / 2
        for y in 0..<8 {
            let half = CGFloat(w) / 2 * sqrt(max(0, CGFloat(y + 1) / 8))
            for x in 0..<w {
                let dx = CGFloat(x) + 0.5 - cx
                guard abs(dx) <= half else { continue }
                let seg = Int((dx + cx) / 4) % 2 == 0
                c.set(x, y, seg ? Pal.stripeA : Pal.stripeB)
            }
        }
        // Scalloped edge
        for x in 0..<w where x % 4 == 1 || x % 4 == 2 { c.set(x, 8, (x / 4) % 2 == 0 ? Pal.stripeA : Pal.stripeB) }
        c.set(15, 0, Pal.woodShade); c.set(16, 0, Pal.woodShade)
        return c
    }

    // MARK: Scene furniture

    static func platform() -> PixelCanvas {
        let w = 116, h = 6
        let c = PixelCanvas(w, h)
        c.fill(0, 0, w, h, Pal.floor)
        c.fill(0, 0, w, 1, Pal.floorLight)
        c.fill(0, h - 1, w, 1, Pal.floorDark)
        for x in stride(from: 9, to: w, by: 14) { c.fill(x, 1, 1, h - 2, Pal.floorDark) }
        for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] { c.set(x, y, nil) }
        return c
    }

    static func digits(_ text: String, color: RGBA = Pal.mortar) -> PixelCanvas {
        var w = PixelFont.width(text)
        if w % 2 == 1 { w += 1 }
        let c = PixelCanvas(max(2, w), 5)
        PixelFont.draw(text, on: c, x: 0, y: 0, color: color)
        return c
    }

    /// A speech bubble. Returns the canvas and where (x from left) the tail sits.
    static func bubble(_ text: String, tailX: Int = 5) -> PixelCanvas {
        let lines = PixelFont.wrap(text, maxChars: 18)
        let textW = lines.map(PixelFont.width).max() ?? 1
        var w = textW + 6
        if w % 2 == 1 { w += 1 }
        w = max(w, 12)
        let boxH = lines.count * 6 - 1 + 6
        let h = boxH + 3
        let c = PixelCanvas(w, h)
        c.fill(0, 0, w, boxH, Pal.outline)
        c.fill(1, 1, w - 2, boxH - 2, Pal.paper)
        for (x, y) in [(0, 0), (w - 1, 0), (0, boxH - 1), (w - 1, boxH - 1)] { c.set(x, y, nil) }
        for (i, line) in lines.enumerated() {
            let lw = PixelFont.width(line)
            PixelFont.draw(line, on: c, x: (w - lw) / 2, y: 3 + i * 6, color: Pal.outline)
        }
        let tx = max(2, min(w - 4, tailX))
        c.set(tx + 1, boxH - 1, Pal.paper)
        c.set(tx + 2, boxH - 1, Pal.paper)
        c.set(tx, boxH, Pal.outline); c.set(tx + 1, boxH, Pal.paper); c.set(tx + 2, boxH, Pal.outline)
        c.set(tx, boxH + 1, Pal.outline); c.set(tx + 1, boxH + 1, Pal.outline)
        c.set(tx, boxH + 2, Pal.outline)
        return c
    }

    // MARK: Particles

    static func disc(_ size: Int) -> SKTexture {
        let c = PixelCanvas(size, size)
        let r = CGFloat(size) / 2
        for y in 0..<size {
            for x in 0..<size where (P(CGFloat(x) + 0.5, CGFloat(y) + 0.5) - P(r, r)).length <= r + 0.1 {
                c.set(x, y, Pal.white)
            }
        }
        return c.texture()
    }

    static func glow() -> SKTexture {
        let size = 64
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
        let mid = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: CGFloat(size) / 2, options: [])
        return SKTexture(cgImage: ctx.makeImage()!)
    }
}

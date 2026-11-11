import SpriteKit

enum HeadStyle { case normal, closed, surprised, worried, shades }
enum HeldProp: Equatable { case none, mug, drink, flag(Int) }

struct ShovelPose {
    var grip: CGPoint
    var tip: CGPoint
    var loaded: Bool
}

/// A pose in "design" coordinates: feet rest on y≈29, the body is centred on x≈12, facing right.
struct Pose {
    var hip: CGPoint
    var shoulder: CGPoint
    var kneeRear: CGPoint, footRear: CGPoint
    var kneeNear: CGPoint, footNear: CGPoint
    var handRear: CGPoint = P(11, 19)
    var handNear: CGPoint = P(14, 19)
    var shovel: ShovelPose?
    var head: HeadStyle = .normal
    var prop: HeldProp = .none
    var sweat = false

    func lerp(_ o: Pose, _ t: CGFloat) -> Pose {
        var r = t < 0.5 ? self : o
        r.hip = hip.lerp(o.hip, t)
        r.shoulder = shoulder.lerp(o.shoulder, t)
        r.kneeRear = kneeRear.lerp(o.kneeRear, t)
        r.footRear = footRear.lerp(o.footRear, t)
        r.kneeNear = kneeNear.lerp(o.kneeNear, t)
        r.footNear = footNear.lerp(o.footNear, t)
        r.handRear = handRear.lerp(o.handRear, t)
        r.handNear = handNear.lerp(o.handNear, t)
        if let a = shovel, let b = o.shovel {
            r.shovel = ShovelPose(grip: a.grip.lerp(b.grip, t), tip: a.tip.lerp(b.tip, t),
                                  loaded: t < 0.5 ? a.loaded : b.loaded)
        }
        return r
    }
}

enum WorkerArt {
    static let width = 44
    static let height = 36
    /// Design coordinates are shifted down by this much so raised arms and flags fit.
    static let yOffset: CGFloat = 6
    /// Column of the feet; used as the sprite's horizontal anchor.
    static let feetX = 12

    // MARK: Poses

    static func standingLegs(_ p: inout Pose) {
        p.kneeRear = P(11, 24); p.footRear = P(10, 28)
        p.kneeNear = P(14, 24); p.footNear = P(15, 28)
    }

    static var stand: Pose {
        Pose(hip: P(12, 20), shoulder: P(12, 12),
             kneeRear: P(11, 24), footRear: P(10, 28), kneeNear: P(14, 24), footNear: P(15, 28))
    }

    // Shovelling keyframes.
    static var scoop: Pose {
        var p = stand
        p.hip = P(12, 21); p.shoulder = P(17, 14)
        p.kneeRear = P(12, 25); p.footRear = P(10, 28); p.kneeNear = P(16, 24); p.footNear = P(16, 28)
        p.shovel = ShovelPose(grip: P(14, 17), tip: P(33, 27), loaded: false)
        return p
    }
    static var push: Pose {
        var p = scoop
        p.hip = P(13, 21); p.shoulder = P(18, 14); p.kneeNear = P(17, 24)
        p.shovel = ShovelPose(grip: P(16, 18), tip: P(35, 27), loaded: true)
        return p
    }
    static var lift: Pose {
        var p = stand
        p.shoulder = P(14, 12)
        p.shovel = ShovelPose(grip: P(12, 18), tip: P(28, 15), loaded: true)
        return p
    }
    static var cock: Pose {
        var p = stand
        p.hip = P(11, 20); p.shoulder = P(12, 12)
        p.shovel = ShovelPose(grip: P(9, 19), tip: P(24, 11), loaded: true)
        return p
    }
    static var thrust: Pose {
        var p = stand
        p.hip = P(13, 20); p.shoulder = P(16, 12)
        p.kneeRear = P(11, 24); p.footRear = P(9, 28); p.kneeNear = P(16, 24); p.footNear = P(17, 28)
        p.shovel = ShovelPose(grip: P(16, 16), tip: P(38, 11), loaded: false)
        return p
    }

    /// Frames for one shovel cycle plus the indices where sounds/coal release happen.
    static let shovelCycle: (frames: [Pose], scrapeAt: Int, releaseAt: Int) = {
        let segments: [(Pose, Pose, Int)] = [
            (scoop, push, 3), (push, lift, 3), (lift, cock, 3), (cock, thrust, 2), (thrust, thrust, 2), (thrust, scoop, 3),
        ]
        var frames = [scoop]
        for (a, b, n) in segments {
            for i in 1...n { frames.append(a.lerp(b, CGFloat(i) / CGFloat(n))) }
        }
        frames.removeLast() // same as the first frame
        return (frames, 1, 11)
    }()

    static var surprised: Pose {
        var p = stand
        p.handRear = P(9, 10); p.handNear = P(17, 9); p.head = .surprised
        return p
    }
    static var stretch: Pose {
        var p = stand
        p.handRear = P(9, 4); p.handNear = P(16, 4); p.head = .closed
        return p
    }

    static var sit: Pose {
        Pose(hip: P(12, 22), shoulder: P(12, 14),
             kneeRear: P(16, 22), footRear: P(15, 28), kneeNear: P(17, 22), footNear: P(17, 28),
             handRear: P(16, 18), handNear: P(17, 18), prop: .mug)
    }
    static var sitSip: Pose {
        var p = sit
        p.handRear = P(15, 13); p.handNear = P(16, 12); p.head = .closed
        return p
    }

    static var recline: Pose {
        Pose(hip: P(11, 23), shoulder: P(7, 16),
             kneeRear: P(16, 21), footRear: P(21, 26), kneeNear: P(17, 20), footNear: P(22, 25),
             handRear: P(4, 10), handNear: P(12, 19), head: .shades, prop: .drink)
    }
    static var reclineSip: Pose {
        var p = recline
        p.handNear = P(11, 13)
        return p
    }

    static func walk(_ phase: Int) -> Pose {
        var p = stand
        p.head = .worried; p.sweat = true
        p.handRear = P(14, 15); p.handNear = P(16, phase % 2 == 0 ? 15 : 14)
        switch phase % 4 {
        case 0: p.kneeRear = P(10, 24); p.footRear = P(8, 28); p.kneeNear = P(14, 24); p.footNear = P(16, 28)
        case 1: p.hip.y = 19; p.shoulder.y = 11
            p.kneeRear = P(12, 24); p.footRear = P(11, 28); p.kneeNear = P(14, 23); p.footNear = P(13, 27)
        case 2: p.kneeRear = P(14, 24); p.footRear = P(16, 28); p.kneeNear = P(10, 24); p.footNear = P(8, 28)
        default: p.hip.y = 19; p.shoulder.y = 11
            p.kneeRear = P(11, 23); p.footRear = P(11, 27); p.kneeNear = P(13, 24); p.footNear = P(13, 28)
        }
        return p
    }

    static func wave(_ phase: Int) -> Pose {
        var p = stand
        p.head = phase % 2 == 0 ? .worried : .surprised
        p.handNear = phase % 2 == 0 ? P(17, 7) : P(19, 8)
        p.handRear = P(9, phase % 2 == 0 ? 10 : 9)
        p.prop = .flag(phase)
        return p
    }

    // MARK: Rendering

    private static var cache: [String: SKTexture] = [:]

    static func texture(_ pose: Pose, key: String? = nil) -> SKTexture {
        if let key, let t = cache[key] { return t }
        let t = render(pose).texture()
        if let key { cache[key] = t }
        return t
    }

    static func render(_ pose: Pose) -> PixelCanvas {
        let c = PixelCanvas(width, height)
        let o = P(0, yOffset)
        var p = pose
        p.hip = p.hip + o; p.shoulder = p.shoulder + o
        p.kneeRear = p.kneeRear + o; p.footRear = p.footRear + o
        p.kneeNear = p.kneeNear + o; p.footNear = p.footNear + o
        p.handRear = p.handRear + o; p.handNear = p.handNear + o
        if var s = p.shovel {
            s.grip = s.grip + o; s.tip = s.tip + o
            p.shovel = s
            let u = (s.tip - s.grip).normalized
            let len = (s.tip - s.grip).length
            p.handRear = s.grip + u * 1.5
            p.handNear = s.grip + u * (len * 0.45)
        }

        drawLeg(c, hip: p.hip + P(-1, 0), knee: p.kneeRear, foot: p.footRear,
                pants: Pal.overallsShade, boot: Pal.bootShade)
        drawArm(c, shoulder: p.shoulder + P(-0.5, 1.5), hand: p.handRear,
                sleeve: Pal.shirtShade, skin: Pal.skinShade)
        drawTorso(c, p)
        drawLeg(c, hip: p.hip + P(1.5, 0), knee: p.kneeNear, foot: p.footNear,
                pants: Pal.overalls, boot: Pal.boot)
        drawHead(c, p)
        if let s = p.shovel { paintShovel(c, s) }
        drawArm(c, shoulder: p.shoulder + P(1.5, 1.5), hand: p.handNear, sleeve: Pal.shirt, skin: Pal.skin)
        drawHand(c, p.handRear, Pal.skinShade)
        drawHand(c, p.handNear, Pal.skin)
        drawProp(c, p)
        return c
    }

    private static func drawLeg(_ c: PixelCanvas, hip: CGPoint, knee: CGPoint, foot: CGPoint, pants: RGBA, boot: RGBA) {
        let k = knee + P(0.5, 0), f = foot + P(0.5, 0)
        c.capsule(hip, k, radius: 1.05, pants)
        c.capsule(k, f, radius: 1.05, pants)
        let fx = Int(foot.x.rounded(.down)), fy = Int(foot.y.rounded(.down))
        c.fill(fx - 1, fy, 4, 2, boot)
        c.fill(fx - 1, fy + 1, 4, 1, Pal.bootShade)
    }

    /// Two-bone IK with elbows bending downward.
    private static func elbow(_ s: CGPoint, _ h: CGPoint, l1: CGFloat = 4.5, l2: CGFloat = 4.5) -> CGPoint {
        let d = (h - s).length
        if d >= l1 + l2 - 0.01 || d < 0.01 { return s.lerp(h, 0.5) }
        let a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
        let hgt = max(0, l1 * l1 - a * a).squareRoot()
        let u = (h - s).normalized
        let base = s + u * a
        let perp = P(-u.y, u.x)
        let e1 = base + perp * hgt, e2 = base - perp * hgt
        return e1.y > e2.y ? e1 : e2
    }

    private static func drawArm(_ c: PixelCanvas, shoulder: CGPoint, hand: CGPoint, sleeve: RGBA, skin: RGBA) {
        let e = elbow(shoulder, hand)
        c.capsule(e, hand, radius: 0.85, skin)
        c.capsule(shoulder, e, radius: 0.95, sleeve)
    }

    private static func drawHand(_ c: PixelCanvas, _ h: CGPoint, _ skin: RGBA) {
        let x = Int((h.x - 0.5).rounded(.down)), y = Int((h.y - 0.5).rounded(.down))
        c.fill(x, y, 2, 2, skin)
    }

    private static func drawTorso(_ c: PixelCanvas, _ p: Pose) {
        let top = Int(p.shoulder.y.rounded(.down)), bottom = Int(p.hip.y.rounded(.down))
        let n = max(1, bottom - top)
        let S = Pal.shirt, s = Pal.shirtShade, B = Pal.overalls, b = Pal.overallsShade, R = Pal.scarf
        for r in 0...n {
            let t = CGFloat(r) / CGFloat(n)
            let cx = Int((p.shoulder.x + (p.hip.x - p.shoulder.x) * t).rounded(.down))
            let row: [RGBA]
            switch r {
            case 0: row = [s, R, R, R, R, s]
            case 1: row = [s, S, B, S, S, B]
            case 2: row = [s, S, B, B, B, B]
            case n: row = [b, b, B, B, B, b]
            default: row = r == 4 ? [b, B, B, b, b, B] : [b, B, B, B, B, B]
            }
            for (i, col) in row.enumerated() { c.set(cx - 2 + i, top + r, col) }
        }
    }

    private static func drawHead(_ c: PixelCanvas, _ p: Pose) {
        var rows = [
            "..cCCC..",
            ".cCCCCCC",
            ".hSSSKS.",
            ".hsSSSSS",
            "..SMMMM.",
            "..sSSS..",
            "...sS...",
        ]
        switch p.head {
        case .normal: break
        case .closed: rows[2] = ".hSSSsS."
        case .surprised:
            rows[0] = "...cCCC."; rows[1] = "..cCCCCC"
            rows[2] = ".hSSWKS."; rows[5] = "..sSKS.."
        case .worried: rows[2] = ".hSSWKS."; rows[5] = "..sSSK.."
        case .shades: rows[2] = ".hSGGGG."; rows[3] = ".hsSGGSS"
        }
        let x0 = Int(p.shoulder.x.rounded(.down)) - 3, y0 = Int(p.shoulder.y.rounded(.down)) - 7
        c.blit(rows, x: x0, y: y0, palette: [
            "c": Pal.capShade, "C": Pal.cap, "h": Pal.hair, "S": Pal.skin, "s": Pal.skinShade,
            "K": Pal.outline, "M": Pal.mustache, "W": Pal.white, "G": Pal.glasses,
        ])
        if p.sweat {
            c.set(x0, y0 + 2, Pal.sweat)
            c.set(x0, y0 + 3, Pal.sweat)
            c.set(x0 - 1, y0 + 3, Pal.white)
        }
    }

    static func paintShovel(_ c: PixelCanvas, _ s: ShovelPose) {
        let u = (s.tip - s.grip).normalized
        let perp = P(-u.y, u.x)
        let up = perp.y < 0 ? perp : perp * -1
        let bladeLen: CGFloat = 6
        let bladeStart = s.tip - u * bladeLen
        // Handle and D-grip
        c.capsule(s.grip - u * 1.5, bladeStart, radius: 0.55, Pal.wood)
        c.capsule(s.grip - u * 2.5, s.grip - u * 1.5, radius: 0.9, Pal.woodShade)
        // Blade
        c.capsule(bladeStart + u * 0.5, s.tip, radius: 1.25, Pal.metal)
        c.capsule(bladeStart + u * 0.5 - up * 0.9, s.tip - up * 0.9, radius: 0.5, Pal.metalShade)
        c.set(bladeStart + u * 1.5 + up * 0.6, Pal.metalLight)
        c.set(bladeStart + u * 2.5 + up * 0.6, Pal.metalLight)
        if s.loaded {
            let lumps: [(CGFloat, CGFloat, RGBA)] = [
                (1.0, 1.6, Pal.coal), (2.0, 1.8, Pal.coalMid), (3.0, 1.8, Pal.coal), (4.0, 1.6, Pal.coalHi),
                (5.0, 1.5, Pal.coal), (2.4, 2.8, Pal.coal), (3.4, 2.8, Pal.coalHi), (1.6, 2.6, Pal.coalMid),
            ]
            for (along, off, col) in lumps { c.set(bladeStart + u * along + up * off, col) }
        }
    }

    private static func drawProp(_ c: PixelCanvas, _ p: Pose) {
        let hx = Int(p.handNear.x.rounded(.down)), hy = Int(p.handNear.y.rounded(.down))
        switch p.prop {
        case .none: break
        case .mug:
            c.fill(hx + 1, hy - 2, 3, 3, Pal.mug)
            c.fill(hx + 1, hy - 2, 3, 1, Pal.coffee)
            c.set(hx + 3, hy, Pal.mugShade)
            c.set(hx + 4, hy - 1, Pal.mug)
        case .drink:
            c.fill(hx + 1, hy - 3, 2, 3, Pal.drinkGlass)
            c.fill(hx + 1, hy - 2, 2, 2, Pal.juice)
            c.set(hx + 2, hy - 4, Pal.umbrellaPink)
            c.set(hx + 3, hy - 4, Pal.umbrellaPink)
            c.set(hx + 3, hy - 5, Pal.umbrellaPink)
        case .flag(let phase):
            c.line(P(CGFloat(hx), CGFloat(hy)), P(CGFloat(hx), CGFloat(hy - 9)), Pal.woodShade)
            let w = 6, h = 4
            for x in 0..<w {
                let dy = (phase % 2 == 0) ? (x % 3 == 1 ? 1 : 0) : (x % 3 == 2 ? 1 : 0)
                for y in 0..<h { c.set(hx + 1 + x, hy - 9 + y + dy, y == h - 1 ? Pal.shirtShade : Pal.white) }
            }
        }
    }
}

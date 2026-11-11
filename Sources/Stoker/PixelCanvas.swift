import AppKit
import SpriteKit

struct RGBA: Equatable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    init(_ hex: UInt32, alpha: UInt8 = 255) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        a = alpha
    }
}

enum Pal {
    static let outline = RGBA(0x1D1A24)
    static let skin = RGBA(0xF2C29B), skinShade = RGBA(0xC98E6A)
    static let cap = RGBA(0x4F4F63), capShade = RGBA(0x34343F)
    static let hair = RGBA(0x3A2A20), mustache = RGBA(0x5A3B28)
    static let shirt = RGBA(0xE6E2D6), shirtShade = RGBA(0xB3AE9F)
    static let overalls = RGBA(0x3E6DB5), overallsShade = RGBA(0x2C4F86)
    static let scarf = RGBA(0xC8433A)
    static let boot = RGBA(0x5A3A28), bootShade = RGBA(0x3E281C)
    static let metal = RGBA(0xA7ADB8), metalShade = RGBA(0x6D737E), metalLight = RGBA(0xDCE0E6)
    static let wood = RGBA(0xA06C3A), woodShade = RGBA(0x6E4826)
    static let coal = RGBA(0x24232B), coalMid = RGBA(0x383843), coalHi = RGBA(0x5E6072)
    static let brick = RGBA(0x9A4632), brickShade = RGBA(0x7A3426), mortar = RGBA(0x4E2A22)
    static let iron = RGBA(0x3B3F4A), ironLight = RGBA(0x5B616E), ironDark = RGBA(0x24262E)
    static let fireWhite = RGBA(0xFFF4C2), fireYellow = RGBA(0xFFC93E)
    static let fireOrange = RGBA(0xFF7A2A), fireRed = RGBA(0xD8381E)
    static let ember = RGBA(0x8A2A16), soot = RGBA(0x140C0A)
    static let brass = RGBA(0xD4A94E), brassShade = RGBA(0x8F6B2A)
    static let white = RGBA(0xFFFFFF), paper = RGBA(0xFBF7EA)
    static let sweat = RGBA(0x8FD3FF)
    static let floor = RGBA(0x5A4A3E), floorLight = RGBA(0x7A6552), floorDark = RGBA(0x3E3229)
    static let stripeA = RGBA(0xE2483D), stripeB = RGBA(0xF6EFE0)
    static let glasses = RGBA(0x111118)
    static let mug = RGBA(0xE8E1D2), mugShade = RGBA(0xB5AC98), coffee = RGBA(0x5A3A22)
    static let drinkGlass = RGBA(0xBFE6F2), juice = RGBA(0xF29A3A), umbrellaPink = RGBA(0xFF5FA2)
    static let red = RGBA(0xD9372B), yellow = RGBA(0xFFD33D)
}

/// Deterministic RNG so generated art looks the same every launch.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
}

/// A tiny raster we paint pixel art into. (0,0) is the top-left pixel.
final class PixelCanvas {
    let width: Int
    let height: Int
    private var data: [RGBA?]

    init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
        data = Array(repeating: nil, count: width * height)
    }

    var size: CGSize { CGSize(width: width, height: height) }

    func set(_ x: Int, _ y: Int, _ c: RGBA?) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        data[y * width + x] = c
    }

    func set(_ p: CGPoint, _ c: RGBA?) {
        set(Int(p.x.rounded(.down)), Int(p.y.rounded(.down)), c)
    }

    func get(_ x: Int, _ y: Int) -> RGBA? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return data[y * width + x]
    }

    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA?) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, c) } }
    }

    /// 1px Bresenham line.
    func line(_ a: CGPoint, _ b: CGPoint, _ c: RGBA) {
        var x0 = Int(a.x.rounded(.down)), y0 = Int(a.y.rounded(.down))
        let x1 = Int(b.x.rounded(.down)), y1 = Int(b.y.rounded(.down))
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            set(x0, y0, c)
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }

    /// Fills every pixel whose centre lies within `radius` of segment a–b. Good for chunky limbs.
    func capsule(_ a: CGPoint, _ b: CGPoint, radius r: CGFloat, _ c: RGBA) {
        let minX = Int((min(a.x, b.x) - r - 1).rounded(.down)), maxX = Int((max(a.x, b.x) + r + 1).rounded(.up))
        let minY = Int((min(a.y, b.y) - r - 1).rounded(.down)), maxY = Int((max(a.y, b.y) + r + 1).rounded(.up))
        let abx = b.x - a.x, aby = b.y - a.y
        let len2 = max(abx * abx + aby * aby, 0.0001)
        for y in minY...maxY {
            for x in minX...maxX {
                let px = CGFloat(x) + 0.5, py = CGFloat(y) + 0.5
                let t = max(0, min(1, ((px - a.x) * abx + (py - a.y) * aby) / len2))
                let qx = a.x + abx * t - px, qy = a.y + aby * t - py
                if qx * qx + qy * qy <= r * r { set(x, y, c) }
            }
        }
    }

    /// Paints rows of characters using `palette`; characters not in the palette are skipped.
    func blit(_ rows: [String], x: Int, y: Int, palette: [Character: RGBA]) {
        for (ry, row) in rows.enumerated() {
            for (rx, ch) in row.enumerated() {
                if let c = palette[ch] { set(x + rx, y + ry, c) }
            }
        }
    }

    func makeImage() -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<data.count {
            guard let c = data[i] else { continue }
            let a = Int(c.a)
            bytes[i * 4] = UInt8(Int(c.r) * a / 255)
            bytes[i * 4 + 1] = UInt8(Int(c.g) * a / 255)
            bytes[i * 4 + 2] = UInt8(Int(c.b) * a / 255)
            bytes[i * 4 + 3] = c.a
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    func texture() -> SKTexture {
        let t = SKTexture(cgImage: makeImage())
        t.filteringMode = .nearest
        return t
    }
}

/// A 3×5 upper-case pixel font.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
        "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
        "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
        "W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
        "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
        "!": [".#.", ".#.", ".#.", "...", ".#."], "?": ["##.", "..#", ".#.", "...", ".#."],
        ".": ["...", "...", "...", "...", ".#."], ",": ["...", "...", "...", ".#.", "#.."],
        "'": [".#.", ".#.", "...", "...", "..."], "%": ["#.#", "..#", ".#.", "#..", "#.#"],
        "-": ["...", "...", "###", "...", "..."], ":": ["...", ".#.", "...", ".#.", "..."],
        " ": ["...", "...", "...", "...", "..."],
    ]

    static func width(_ s: String) -> Int { max(0, s.count * 4 - 1) }

    static func draw(_ s: String, on c: PixelCanvas, x: Int, y: Int, color: RGBA) {
        for (i, ch) in s.uppercased().enumerated() {
            guard let g = glyphs[ch] else { continue }
            c.blit(g, x: x + i * 4, y: y, palette: ["#": color])
        }
    }

    /// Greedy word wrap.
    static func wrap(_ text: String, maxChars: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.uppercased().split(separator: " ") {
            if current.isEmpty { current = String(word) }
            else if current.count + 1 + word.count <= maxChars { current += " " + word }
            else { lines.append(current); current = String(word) }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var length: CGFloat { (x * x + y * y).squareRoot() }
    var normalized: CGPoint { let l = max(length, 0.0001); return CGPoint(x: x / l, y: y / l) }
    func lerp(_ o: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: x + (o.x - x) * t, y: y + (o.y - y) * t) }
}

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

import SpriteKit

/// The furnace room. Scene coordinates are "art pixels" (120×72); the view scales them up crisply.
final class StokerScene: SKScene {
    static let logicalSize = CGSize(width: 120, height: 72)
    static let floorY: CGFloat = 6
    static let workerHomeX: CGFloat = 30
    static let doorPoint = CGPoint(x: 84, y: 17)
    static let plugX: CGFloat = 52
    static let plugLoweredY: CGFloat = 46
    static let plugRaisedY: CGFloat = 86

    /// (effect, gain, pan)
    var onSound: ((Sfx, Float, Float) -> Void)?
    /// Called on a click when not dragging (only reachable when hosted in the menu bar popover).
    var onClick: (() -> Void)?
    var chatty = true
    var plaqueMode: PlaqueMode = .percentage {
        didSet { if plaqueMode != oldValue { showingTime = plaqueMode == .time; refreshPlaque() } }
    }
    var dragEnabled = false { didSet { moveHint.isHidden = !dragEnabled } }

    private(set) var mood: Mood?
    private var percent = 100
    private var hasBattery = true
    private var watts: Int?
    private var minutesLeft: Int?
    private var deficit: Int?
    /// In alternate mode, whether the plaque is currently on its time side.
    private var showingTime = false
    private var plaqueText = ""
    private var cycle: TimeInterval = 1.3

    private let platform = SKSpriteNode()
    private let parasol = SKSpriteNode()
    private let furnace = SKSpriteNode()
    private let fire = SKSpriteNode()
    private let glow = SKSpriteNode()
    private let plaque = SKSpriteNode()
    private let chair = SKSpriteNode()
    private let bucket = SKSpriteNode()
    private let shovelStuck = SKSpriteNode()
    private let worker = SKSpriteNode()
    private let pile = SKSpriteNode()
    private let plug = SKNode()
    private let bubble = SKSpriteNode()
    private let moveHint = SKNode()
    private let smoke = SKEmitterNode()
    private let steam = SKEmitterNode()

    private var fireLevel = -1
    private var glowBase: CGFloat = 0.4
    private var flare: CGFloat = 0
    private var pileStep = 0

    // MARK: Cached textures

    private static let fireTextures: [[SKTexture]] = (0...3).map { level in
        (0..<4).map { PropArt.fire(level: level, frame: $0).texture() }
    }
    private static let chunkTextures = (0..<3).map { PropArt.chunk($0).texture() }
    private static let sparkTexture = PropArt.disc(1)
    private static let shovelTexture = PropArt.shovel().texture()
    private static let shovelFrames = WorkerArt.shovelCycle.frames.map { WorkerArt.render($0).texture() }
    private static let sweatyShovelFrames = WorkerArt.sweatyShovelCycle.map { WorkerArt.render($0).texture() }
    private static let pileSteps: [(texture: SKTexture, w: Int, h: Int, cx: CGFloat)] = (0...12).map { i in
        let t = CGFloat(i) / 12
        var w = Int((22 + 50 * t).rounded())
        if w % 2 == 1 { w += 1 }
        let h = Int((9 + 10 * t).rounded())
        return (PropArt.mound(width: w, height: h, seed: 3).texture(), w, h, (52 - 8 * t).rounded())
    }

    private func tex(_ name: String) -> SKTexture {
        let pose: Pose
        switch name {
        case "stand": pose = WorkerArt.stand
        case "surprised": pose = WorkerArt.surprised
        case "stretch": pose = WorkerArt.stretch
        case "sit": pose = WorkerArt.sit
        case "sitSip": pose = WorkerArt.sitSip
        case "recline": pose = WorkerArt.recline
        case "reclineSip": pose = WorkerArt.reclineSip
        case "walk0": pose = WorkerArt.walk(0)
        case "walk1": pose = WorkerArt.walk(1)
        case "walk2": pose = WorkerArt.walk(2)
        case "walk3": pose = WorkerArt.walk(3)
        case "wave0": pose = WorkerArt.wave(0)
        default: pose = WorkerArt.wave(1)
        }
        return WorkerArt.texture(pose, key: name)
    }

    // MARK: Setup

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .aspectFit
        anchorPoint = .zero
        build()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func setArt(_ node: SKSpriteNode, _ canvas: PixelCanvas) {
        node.texture = canvas.texture()
        node.size = canvas.size
    }

    private func place(_ node: SKNode, _ x: CGFloat, _ y: CGFloat, z: CGFloat, hidden: Bool = false) {
        node.position = CGPoint(x: x, y: y)
        node.zPosition = z
        node.isHidden = hidden
        addChild(node)
    }

    private func build() {
        setArt(platform, PropArt.platform())
        platform.anchorPoint = CGPoint(x: 0.5, y: 0)
        place(platform, 60, 0, z: 0)

        setArt(parasol, PropArt.parasol())
        parasol.anchorPoint = CGPoint(x: 0.5, y: 0)
        place(parasol, 16, Self.floorY, z: 1, hidden: true)

        smoke.particleTexture = PropArt.disc(4)
        smoke.particleBirthRate = 0
        smoke.particleLifetime = 3.2
        smoke.particleLifetimeRange = 1.2
        smoke.particlePositionRange = CGVector(dx: 5, dy: 0)
        smoke.emissionAngle = .pi / 2
        smoke.emissionAngleRange = 0.35
        smoke.particleSpeed = 9
        smoke.particleSpeedRange = 4
        smoke.xAcceleration = 3
        smoke.particleAlpha = 0.75
        smoke.particleAlphaRange = 0.15
        smoke.particleAlphaSpeed = -0.22
        smoke.particleScale = 0.7
        smoke.particleScaleRange = 0.3
        smoke.particleScaleSpeed = 0.45
        smoke.particleColor = NSColor(white: 0.42, alpha: 1)
        smoke.particleColorBlendFactor = 1
        place(smoke, 100, 51, z: 1.5)

        setArt(furnace, PropArt.furnace())
        furnace.anchorPoint = .zero
        place(furnace, 72, Self.floorY, z: 2)

        fire.anchorPoint = CGPoint(x: 0.5, y: 0)
        fire.size = CGSize(width: 14, height: 12)
        place(fire, 84, 12, z: 3)

        glow.texture = PropArt.glow()
        glow.size = CGSize(width: 36, height: 30)
        glow.color = NSColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        place(glow, 84, 18, z: 4)
        glow.run(.repeatForever(.sequence([
            .run { [weak self] in
                guard let self else { return }
                self.glow.alpha = self.glowBase * CGFloat.random(in: 0.8...1.1) + self.flare
                self.flare *= 0.6
            },
            .wait(forDuration: 0.1),
        ])))

        plaque.anchorPoint = CGPoint(x: 0.5, y: 0)
        place(plaque, 84, 27, z: 4)
        plaque.run(.repeatForever(.sequence([
            .wait(forDuration: Self.plaqueFlipInterval),
            .run { [weak self] in
                guard let self, self.plaqueMode == .alternate || self.mood == .overworked else { return }
                self.showingTime.toggle()
                self.refreshPlaque()
            },
        ])))

        setArt(chair, PropArt.chair())
        chair.anchorPoint = CGPoint(x: 0.5, y: 0)
        place(chair, 31, Self.floorY, z: 5, hidden: true)

        setArt(bucket, PropArt.bucket())
        bucket.anchorPoint = CGPoint(x: 0.5, y: 0)
        place(bucket, 30, Self.floorY, z: 5, hidden: true)

        shovelStuck.texture = Self.shovelTexture
        shovelStuck.size = CGSize(width: 10, height: 24)
        shovelStuck.anchorPoint = CGPoint(x: 0.5, y: 0)
        place(shovelStuck, 60, 11, z: 6, hidden: true)

        worker.anchorPoint = CGPoint(x: CGFloat(WorkerArt.feetX) / CGFloat(WorkerArt.width), y: 0)
        worker.size = CGSize(width: WorkerArt.width, height: WorkerArt.height)
        worker.texture = tex("stand")
        place(worker, Self.workerHomeX, Self.floorY, z: 7)

        pile.anchorPoint = CGPoint(x: 0.5, y: 0)
        place(pile, 52, Self.floorY, z: 8)
        showPileStep(0)

        let plugBody = SKSpriteNode()
        setArt(plugBody, PropArt.plug())
        plugBody.anchorPoint = CGPoint(x: 0.5, y: 0)
        plug.addChild(plugBody)
        let cable = SKSpriteNode()
        setArt(cable, PropArt.cable(length: 60))
        cable.anchorPoint = CGPoint(x: 0.5, y: 0)
        cable.position = CGPoint(x: 0, y: 14)
        plug.addChild(cable)
        place(plug, Self.plugX, Self.plugRaisedY, z: 9)

        steam.particleTexture = PropArt.disc(2)
        steam.particleBirthRate = 0
        steam.particleLifetime = 1.4
        steam.particleSpeed = 5
        steam.emissionAngle = .pi / 2
        steam.emissionAngleRange = 0.3
        steam.particleAlpha = 0.7
        steam.particleAlphaSpeed = -0.5
        steam.particleScaleSpeed = 0.6
        steam.particleColor = .white
        steam.particleColorBlendFactor = 1
        steam.xAcceleration = 1
        place(steam, 37, 20, z: 9)

        bubble.anchorPoint = .zero
        place(bubble, 0, 0, z: 20, hidden: true)

        buildMoveHint()
        place(moveHint, 0, 0, z: 30, hidden: true)
    }

    private func buildMoveHint() {
        let tint = SKSpriteNode(color: NSColor(white: 0, alpha: 0.25), size: Self.logicalSize)
        tint.anchorPoint = .zero
        moveHint.addChild(tint)
        let rect = CGRect(x: 0.5, y: 0.5, width: Self.logicalSize.width - 1, height: Self.logicalSize.height - 1)
        let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            .copy(dashingWithPhase: 0, lengths: [3, 2])
        let border = SKShapeNode(path: path)
        border.strokeColor = .white
        border.lineWidth = 0.6
        moveHint.addChild(border)
        let text = "DRAG ME"
        let c = PixelCanvas(PixelFont.width(text) + 5, 9)
        c.fill(0, 0, c.width, c.height, Pal.outline)
        PixelFont.draw(text, on: c, x: 2, y: 2, color: Pal.paper)
        let label = SKSpriteNode()
        setArt(label, c)
        label.anchorPoint = CGPoint(x: 0.5, y: 0)
        label.position = CGPoint(x: 60, y: 61)
        moveHint.addChild(label)
    }

    // MARK: Public API

    func apply(mood new: Mood, status: PowerStatus, animated: Bool) {
        percent = status.percent
        hasBattery = status.hasBattery
        watts = status.watts
        minutesLeft = Self.minutesLeft(status)
        deficit = status.deficitWatts
        refreshPlaque()

        let newCycle = Self.cycleDuration(watts: status.watts)
        let cycleChanged = abs(newCycle - cycle) > 0.01
        cycle = newCycle

        let wasOverworked = mood == .overworked
        guard new != mood else {
            if action(forKey: "transition") == nil {
                if new == .shovelling && cycleChanged { startShovelling() }
                if new == .vacation { setFire(fireLevel(for: .vacation)) }
            }
            return
        }
        let old = mood
        mood = new
        removeAction(forKey: "transition")
        if wasOverworked != (new == .overworked) { refreshPlaque(force: true) }
        if animated, let old { runTransition(from: old, to: new) } else { enter(new, animated: false) }
    }

    /// Say something right now, regardless of the chatter setting.
    func poke() {
        guard let m = mood, let line = m.lines(watts: watts, deficit: deficit).randomElement() else { return }
        say(line)
        sound(.pop, 0.3)
    }

    // MARK: Plaque

    static let plaqueFlipInterval: TimeInterval = 4

    /// Minutes until full while charging, or until empty on battery. Nil when macOS has
    /// no estimate yet, or when there's nothing to count (full, or charging paused).
    static func minutesLeft(_ s: PowerStatus) -> Int? {
        // Same precedence as Mood: at 100% macOS may still report "charging" while topping off.
        guard s.hasBattery, !s.isCharged, s.percent < 100 else { return nil }
        if s.isCharging { return s.minutesToFull }
        if !s.onAC { return s.minutesToEmpty }
        return nil
    }

    /// "1:23" fits the plaque the same as "100%" does. Capped at 9:59 to stay four characters.
    static func clock(_ minutes: Int) -> String {
        let m = min(max(0, minutes), 9 * 60 + 59)
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    static func plaqueText(mode: PlaqueMode, showingTime: Bool, percent: Int, hasBattery: Bool, minutesLeft: Int?,
                           deficit: Int? = nil) -> String {
        guard hasBattery else { return "AC" }
        // Losing power while plugged in: always alternate with how much is leaking out, whatever the mode.
        if let d = deficit { return showingTime ? "-\(min(d, 99))W" : "\(percent)%" }
        let wantsTime = mode == .time || (mode == .alternate && showingTime)
        // No estimate (just plugged in or unplugged): fall back to the percentage.
        if wantsTime, let m = minutesLeft { return clock(m) }
        return "\(percent)%"
    }

    private func refreshPlaque(force: Bool = false) {
        let losing = mood == .overworked ? deficit : nil
        let text = Self.plaqueText(mode: plaqueMode, showingTime: showingTime, percent: percent,
                                   hasBattery: hasBattery, minutesLeft: minutesLeft, deficit: losing)
        guard force || text != plaqueText else { return }
        plaqueText = text
        // Red while the battery drains on the charger, so "57%" doesn't look like good news.
        setArt(plaque, PropArt.digits(text, color: losing == nil ? Pal.mortar : Pal.red))
    }

    /// Flat out: faster than even the biggest charger, because it still isn't enough.
    static let overworkedCycle: TimeInterval = 0.6

    /// Faster chargers make for frantic shovelling.
    static func cycleDuration(watts: Int?) -> TimeInterval {
        guard let w = watts else { return 1.3 }
        return max(0.75, min(1.7, 1.75 - Double(w - 20) / 90))
    }

    override func mouseDown(with event: NSEvent) {
        if dragEnabled { view?.window?.performDrag(with: event) } else { onClick?() }
    }

    // MARK: Moods

    private func fireLevel(for m: Mood) -> Int {
        switch m {
        case .shovelling: 3
        case .onBreak: 1
        case .overworked: percent > 20 ? 1 : 0
        case .full: 2
        case .vacation: percent > 50 ? 1 : 0
        case .panicking: 0
        }
    }

    private func enter(_ m: Mood, animated: Bool) {
        worker.removeAction(forKey: "act")
        worker.removeAction(forKey: "pace")
        worker.xScale = 1
        worker.position = CGPoint(x: Self.workerHomeX, y: Self.floorY)
        steam.particleBirthRate = 0

        show(bucket, m == .onBreak, animated: animated)
        show(chair, m == .vacation, animated: animated)
        show(parasol, m == .vacation, animated: animated)
        show(shovelStuck, m == .onBreak || m == .vacation || m == .panicking, animated: animated)
        growMountain(m == .full, animated: animated)
        setPlug(lowered: m.isPluggedIn, animated: animated)
        // A weak charger only trickles coal in.
        setPouring(m == .shovelling || m == .overworked || m == .full,
                   interval: m == .full ? 0.07 : m == .overworked ? 0.9 : 0.22)
        setFire(fireLevel(for: m))

        switch m {
        case .shovelling, .overworked:
            startShovelling()
        case .onBreak:
            worker.texture = tex("sit")
            steam.particleBirthRate = 2.5
            worker.run(.repeatForever(.sequence([
                .wait(forDuration: 4, withRange: 3),
                .run { [weak self] in
                    guard let self else { return }
                    self.steam.particleBirthRate = 0
                    self.worker.texture = self.tex("sitSip")
                    self.sound(.sip, 0.35)
                },
                .wait(forDuration: 1.3),
                .run { [weak self] in
                    guard let self else { return }
                    self.worker.texture = self.tex("sit")
                    self.steam.particleBirthRate = 2.5
                },
            ])), withKey: "act")
        case .full:
            worker.run(.repeatForever(.animate(with: [tex("wave0"), tex("wave1")], timePerFrame: 0.35)), withKey: "act")
            if animated {
                run(.sequence([
                    .wait(forDuration: 3.4),
                    .run { [weak self] in
                        self?.sound(.whistle, 0.5, 0.4)
                        self?.say("IT'S FULL!!")
                    },
                ]), withKey: "transition")
            }
        case .vacation:
            worker.texture = tex("recline")
            worker.run(.repeatForever(.sequence([
                .wait(forDuration: 7, withRange: 4),
                .run { [weak self] in
                    guard let self else { return }
                    self.worker.texture = self.tex("reclineSip")
                    self.sound(.sip, 0.3)
                },
                .wait(forDuration: 1.2),
                .run { [weak self] in
                    guard let self else { return }
                    self.worker.texture = self.tex("recline")
                },
            ])), withKey: "act")
        case .panicking:
            let frames = (0..<4).map { tex("walk\($0)") }
            worker.run(.repeatForever(.animate(with: frames, timePerFrame: 0.12)), withKey: "act")
            let speed: CGFloat = 11
            let left: CGFloat = 22, right: CGFloat = 40
            worker.run(.sequence([
                .moveTo(x: right, duration: TimeInterval((right - Self.workerHomeX) / speed)),
                .repeatForever(.sequence([
                    .run { [weak self] in self?.worker.xScale = -1 },
                    .moveTo(x: left, duration: TimeInterval((right - left) / speed)),
                    .run { [weak self] in self?.worker.xScale = 1 },
                    .moveTo(x: right, duration: TimeInterval((right - left) / speed)),
                ])),
            ]), withKey: "pace")
        }
        scheduleChatter()
    }

    private func startShovelling() {
        let c = WorkerArt.shovelCycle
        let overworked = mood == .overworked
        let frames = overworked ? Self.sweatyShovelFrames : Self.shovelFrames
        let tpf = (overworked ? Self.overworkedCycle : cycle) / Double(frames.count)
        var seq: [SKAction] = []
        for (i, t) in frames.enumerated() {
            seq.append(.setTexture(t))
            if i == c.scrapeAt { seq.append(.run { [weak self] in self?.sound(.scrape, 0.3, -0.3) }) }
            if i == c.releaseAt { seq.append(.run { [weak self] in self?.throwCoal() }) }
            seq.append(.wait(forDuration: tpf))
        }
        worker.removeAction(forKey: "act")
        worker.run(.repeatForever(.sequence(seq)), withKey: "act")
    }

    // MARK: Transitions

    private func runTransition(from old: Mood, to new: Mood) {
        if old.isPluggedIn && !new.isPluggedIn { unplugged(from: old, to: new) }
        else if !old.isPluggedIn && new.isPluggedIn { pluggedIn(to: new) }
        else { enter(new, animated: true) }
    }

    private func unplugged(from old: Mood, to new: Mood) {
        worker.removeAction(forKey: "act")
        setPouring(false)
        setPlug(lowered: false, animated: true)
        sound(.plug, 0.6)
        growMountain(false, animated: true)
        show(bucket, false, animated: true)
        steam.particleBirthRate = 0

        var steps: [SKAction] = [.wait(forDuration: 0.3)]
        if old.isShovelling {
            steps.append(.run { [weak self] in self?.throwShovel() })
            steps.append(.wait(forDuration: 0.9))
        }
        steps.append(.run { [weak self] in
            guard let self else { return }
            self.worker.texture = self.tex("stretch")
            self.say("FINALLY!", duration: 1.8)
            self.sound(.sigh, 0.6)
        })
        steps.append(.wait(forDuration: 1.6))
        steps.append(.run { [weak self] in self?.enter(new, animated: true) })
        run(.sequence(steps), withKey: "transition")
    }

    private func pluggedIn(to new: Mood) {
        setPlug(lowered: true, animated: true)
        sound(.plug, 0.6)
        var steps: [SKAction] = [
            .wait(forDuration: 0.45),
            .run { [weak self] in
                guard let self else { return }
                self.worker.removeAction(forKey: "act")
                self.worker.removeAction(forKey: "pace")
                self.worker.xScale = 1
                self.worker.position = CGPoint(x: Self.workerHomeX, y: Self.floorY)
                self.worker.texture = self.tex("surprised")
                self.worker.run(.sequence([
                    .moveBy(x: 0, y: 4, duration: 0.12), .moveBy(x: 0, y: -4, duration: 0.12),
                ]))
                self.show(self.chair, false, animated: true)
                self.show(self.parasol, false, animated: true)
                self.say("!", duration: 1.0)
                self.sound(.gasp, 0.5)
            },
            .wait(forDuration: 1.0),
        ]
        if new.isShovelling {
            steps.append(.run { [weak self] in self?.fetchShovel() })
            steps.append(.wait(forDuration: 0.4))
        }
        steps.append(.run { [weak self] in self?.enter(new, animated: true) })
        run(.sequence(steps), withKey: "transition")
    }

    // MARK: Effects

    private func throwCoal() {
        let release = CGPoint(x: worker.position.x - CGFloat(WorkerArt.feetX) + 38.5,
                              y: Self.floorY + CGFloat(WorkerArt.height) - 1 - (11 + WorkerArt.yOffset) + 0.5)
        for k in 0..<3 {
            let n = SKSpriteNode(texture: Self.chunkTextures[k])
            n.size = CGSize(width: 2, height: 2)
            n.zPosition = 9
            let start = release + P(CGFloat.random(in: -1...1), CGFloat.random(in: -1...1))
            let end = Self.doorPoint + P(CGFloat.random(in: -3...3), CGFloat.random(in: -2...2))
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + CGFloat.random(in: 7...11)))
            n.position = start
            addChild(n)
            let dur = 0.32 + 0.04 * Double(k)
            n.run(.sequence([
                .group([.follow(path, asOffset: false, orientToPath: false, duration: dur),
                        .rotate(byAngle: .pi * 2, duration: dur)]),
                .run { [weak self] in if k == 0 { self?.impact() } },
                .removeFromParent(),
            ]))
        }
    }

    private func impact() {
        sparks(at: Self.doorPoint)
        flare = 0.35
        fire.run(.sequence([.scaleY(to: 1.25, duration: 0.06), .scaleY(to: 1, duration: 0.3)]))
        sound(.thud, 0.45, 0.4)
        if Bool.random() { sound(.crackle, 0.3, 0.45) }
    }

    private func sparks(at p: CGPoint) {
        let e = SKEmitterNode()
        e.particleTexture = Self.sparkTexture
        e.numParticlesToEmit = 10
        e.particleBirthRate = 300
        e.particleLifetime = 0.45
        e.particleLifetimeRange = 0.2
        e.emissionAngle = .pi / 2 + 0.5
        e.emissionAngleRange = 1.4
        e.particleSpeed = 26
        e.particleSpeedRange = 10
        e.yAcceleration = -70
        e.particleAlphaSpeed = -1.5
        e.particleColorBlendFactor = 1
        e.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [NSColor(red: 1, green: 0.95, blue: 0.6, alpha: 1),
                             NSColor(red: 1, green: 0.55, blue: 0.15, alpha: 1),
                             NSColor(red: 0.85, green: 0.2, blue: 0.1, alpha: 1)],
            times: [0, 0.5, 1])
        e.position = p
        e.zPosition = 10
        addChild(e)
        e.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
    }

    private func flyingShovel(from: CGPoint, to: CGPoint, duration: TimeInterval, spins: CGFloat,
                              completion: @escaping () -> Void) {
        let s = SKSpriteNode(texture: Self.shovelTexture)
        s.size = CGSize(width: 10, height: 24)
        s.position = from
        s.zPosition = 9
        addChild(s)
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + 22))
        s.run(.sequence([
            .group([.follow(path, asOffset: false, orientToPath: false, duration: duration),
                    .rotate(byAngle: -.pi * 2 * spins, duration: duration)]),
            .run(completion),
            .removeFromParent(),
        ]))
    }

    private func throwShovel() {
        worker.texture = tex("stand")
        let target = shovelStuck.position + P(0, 12)
        flyingShovel(from: CGPoint(x: worker.position.x + 8, y: 22), to: target, duration: 0.7, spins: 2) { [weak self] in
            guard let self else { return }
            self.shovelStuck.isHidden = false
            self.shovelStuck.setScale(1)
            self.sound(.clang, 0.5, -0.1)
            self.sparks(at: target + P(0, -6))
        }
    }

    private func fetchShovel() {
        guard !shovelStuck.isHidden else { return }
        shovelStuck.removeAction(forKey: "vis")
        shovelStuck.isHidden = true
        let from = shovelStuck.position + P(0, 12)
        flyingShovel(from: from, to: CGPoint(x: worker.position.x + 6, y: 20), duration: 0.35, spins: 1) {}
    }

    private func setFire(_ level: Int) {
        guard level != fireLevel else { return }
        fireLevel = level
        let frames = Self.fireTextures[level]
        fire.removeAction(forKey: "flicker")
        fire.texture = frames[0]
        fire.run(.repeatForever(.animate(with: frames, timePerFrame: level >= 2 ? 0.11 : 0.2)), withKey: "flicker")
        glowBase = [0.12, 0.3, 0.5, 0.72][level]
        smoke.particleBirthRate = [0.3, 1.5, 3.5, 7][level]
    }

    private func setPlug(lowered: Bool, animated: Bool) {
        let y = lowered ? Self.plugLoweredY : Self.plugRaisedY
        plug.removeAction(forKey: "move")
        guard animated else { plug.position.y = y; return }
        let a = SKAction.moveTo(y: y, duration: lowered ? 0.45 : 0.25)
        a.timingMode = lowered ? .easeOut : .easeIn
        plug.run(a, withKey: "move")
    }

    private func setPouring(_ on: Bool, interval: TimeInterval = 0.22) {
        removeAction(forKey: "pour")
        guard on else { return }
        run(.repeatForever(.sequence([
            .run { [weak self] in self?.dribble() },
            .wait(forDuration: interval, withRange: interval * 0.6),
        ])), withKey: "pour")
    }

    private func dribble() {
        guard plug.position.y < Self.plugLoweredY + 1 else { return }
        let n = SKSpriteNode(texture: Self.chunkTextures.randomElement()!)
        n.size = CGSize(width: 2, height: 2)
        n.zPosition = 8.5
        n.position = CGPoint(x: Self.plugX + CGFloat(Int.random(in: -1...0)), y: Self.plugLoweredY - 1)
        let landX = Self.plugX + CGFloat(Int.random(in: -3...3))
        let landY = pileSurface(at: landX)
        let fall = SKAction.move(to: CGPoint(x: landX, y: landY),
                                 duration: max(0.15, sqrt(2 * Double(n.position.y - landY) / 220)))
        fall.timingMode = .easeIn
        addChild(n)
        n.run(.sequence([fall, .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    private func pileSurface(at x: CGFloat) -> CGFloat {
        let s = Self.pileSteps[pileStep]
        let col = x - (s.cx - CGFloat(s.w) / 2)
        return Self.floorY + PropArt.moundHeight(width: s.w, height: s.h, atColumn: col) - 1
    }

    private func showPileStep(_ i: Int) {
        pileStep = i
        let s = Self.pileSteps[i]
        pile.texture = s.texture
        pile.size = CGSize(width: s.w, height: s.h)
        pile.position = CGPoint(x: s.cx, y: Self.floorY)
    }

    private func growMountain(_ grow: Bool, animated: Bool) {
        pile.removeAction(forKey: "grow")
        let target = grow ? Self.pileSteps.count - 1 : 0
        guard animated, target != pileStep else { showPileStep(target); return }
        let steps = grow ? Array(pileStep...target) : Array((target...pileStep).reversed())
        var actions: [SKAction] = []
        for i in steps {
            actions.append(.run { [weak self] in self?.showPileStep(i) })
            actions.append(.wait(forDuration: grow ? 0.26 : 0.04))
        }
        pile.run(.sequence(actions), withKey: "grow")
    }

    private func show(_ node: SKNode, _ visible: Bool, animated: Bool) {
        node.removeAction(forKey: "vis")
        if visible {
            guard node.isHidden || node.xScale < 1 else { return }
            node.isHidden = false
            if animated {
                node.setScale(0.01)
                node.run(.sequence([.scale(to: 1.15, duration: 0.15), .scale(to: 1, duration: 0.08)]), withKey: "vis")
                sound(.pop, 0.25)
            } else {
                node.setScale(1)
            }
        } else {
            guard !node.isHidden else { return }
            if animated {
                node.run(.sequence([.scale(to: 0.01, duration: 0.15), .hide(), .scale(to: 1, duration: 0)]), withKey: "vis")
            } else {
                node.isHidden = true
            }
        }
    }

    // MARK: Speech

    private func headPoint() -> CGPoint {
        let x = worker.position.x
        switch mood {
        case .vacation where action(forKey: "transition") == nil: return CGPoint(x: x - 5, y: 28)
        case .onBreak: return CGPoint(x: x, y: 30)
        case .shovelling, .overworked: return CGPoint(x: x + 3, y: 31)
        default: return CGPoint(x: x, y: 32)
        }
    }

    func say(_ text: String, duration: TimeInterval = 3.2) {
        let head = headPoint()
        var tail = 5
        let probe = PropArt.bubble(text, tailX: tail)
        var x = head.x - CGFloat(tail) - 1
        let maxX = Self.logicalSize.width - CGFloat(probe.width) - 1
        if x > maxX { tail += Int(x - maxX); x = maxX }
        if x < 1 { tail -= Int(1 - x); x = 1 }
        let canvas = PropArt.bubble(text, tailX: tail)
        setArt(bubble, canvas)
        bubble.position = CGPoint(x: x.rounded(), y: min(head.y + 1, Self.logicalSize.height - CGFloat(canvas.height)))
        bubble.removeAllActions()
        bubble.isHidden = false
        bubble.alpha = 1
        bubble.run(.sequence([.wait(forDuration: duration), .fadeOut(withDuration: 0.25), .hide()]))
    }

    private func scheduleChatter() {
        removeAction(forKey: "chatter")
        run(.repeatForever(.sequence([
            .wait(forDuration: 45, withRange: 30),
            .run { [weak self] in
                guard let self, self.chatty, self.action(forKey: "transition") == nil,
                      let line = self.mood?.lines(watts: self.watts, deficit: self.deficit).randomElement() else { return }
                self.say(line)
            },
        ])), withKey: "chatter")
    }

    private func sound(_ s: Sfx, _ gain: Float = 1, _ pan: Float = 0) {
        onSound?(s, gain, pan)
    }
}

import AVFoundation

enum Sfx: CaseIterable {
    case scrape, thud, crackle, clang, sigh, whistle, pop, plug, sip, gasp
}

/// Plays procedurally synthesized effects. The audio engine pauses itself when idle to save power.
final class SoundBoard {
    var enabled = true
    var volume: Float = 0.55 { didSet { engine.mainMixerNode.outputVolume = volume } }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [Sfx: AVAudioPCMBuffer] = [:]
    private var idleTimer: Timer?

    init() {
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = volume
        for s in Sfx.allCases { buffers[s] = makeBuffer(Synth.render(s)) }
    }

    func play(_ s: Sfx, gain: Float = 1, pan: Float = 0) {
        guard enabled, volume > 0, let buffer = buffers[s] else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.volume = gain
        p.pan = pan
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        p.play()

        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.engine.pause()
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            b.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return b
    }
}

/// Tiny synthesizer for the furnace-room foley.
enum Synth {
    static let sampleRate: Double = 44_100

    struct OnePole {
        var a: Float
        var y: Float = 0
        init(_ hz: Double) { a = Float(1 - exp(-2 * .pi * hz / Synth.sampleRate)) }
        mutating func lp(_ x: Float) -> Float { y += a * (x - y); return y }
        mutating func hp(_ x: Float) -> Float { x - lp(x) }
    }

    static func render(_ s: Sfx) -> [Float] {
        var rng = SplitMix(UInt64(Sfx.allCases.firstIndex(of: s)! + 11))
        func noise() -> Float { Float(rng.unit() * 2 - 1) }
        func frames(_ seconds: Double) -> Int { Int(seconds * sampleRate) }
        let sr = Float(sampleRate)
        var out: [Float]

        switch s {
        case .scrape:
            let n = frames(0.26)
            out = .init(repeating: 0, count: n)
            var hp = OnePole(500), lp = OnePole(3800), grit = OnePole(70)
            for i in 0..<n {
                let t = Float(i) / sr
                let env = min(1, t / 0.015) * max(0, 1 - t / 0.26)
                let g = 0.5 + 1.5 * abs(grit.lp(noise()))
                let wobble = 0.75 + 0.25 * sin(2 * .pi * 19 * t)
                out[i] = lp.lp(hp.hp(noise())) * env * g * wobble * 0.9
            }

        case .thud:
            let n = frames(0.32)
            out = .init(repeating: 0, count: n)
            var phase: Float = 0
            var lp = OnePole(350)
            for i in 0..<n {
                let t = Float(i) / sr
                let f = 95 - 45 * min(1, t / 0.2)
                phase += 2 * .pi * f / sr
                out[i] = sin(phase) * exp(-t * 13) * 0.9 + lp.lp(noise()) * exp(-t * 28) * 1.2
            }

        case .crackle:
            let n = frames(0.8)
            out = .init(repeating: 0, count: n)
            var env: Float = 0
            let decay = exp(-1 / (0.003 * sr))
            var hp = OnePole(1500), rumble = OnePole(120)
            for i in 0..<n {
                let t = Float(i) / sr
                if Float(rng.unit()) < 0.0014 * (1 - t / 0.8) { env = Float(0.25 + rng.unit() * 0.75) }
                env *= decay
                out[i] = hp.hp(noise()) * env * 0.9 + rumble.lp(noise()) * 0.5 * (1 - t / 0.8)
            }

        case .clang:
            let n = frames(1.1)
            out = .init(repeating: 0, count: n)
            let partials: [(Float, Float, Float)] = [(523, 1, 4), (1187, 0.6, 6), (1650, 0.5, 7.5), (2489, 0.35, 9), (3312, 0.2, 12)]
            for i in 0..<n {
                let t = Float(i) / sr
                var v: Float = 0
                for (f, a, d) in partials { v += a * sin(2 * .pi * f * t) * exp(-t * d) }
                out[i] = v * 0.3 + (t < 0.006 ? noise() * 0.6 : 0)
            }

        case .sigh:
            let dur: Float = 1.25
            let n = frames(Double(dur))
            out = .init(repeating: 0, count: n)
            var breath = OnePole(1400), voice = OnePole(650)
            var phase: Float = 0
            for i in 0..<n {
                let t = Float(i) / sr
                let env = sin(.pi / 2 * min(1, t / 0.15)) * (t < 0.45 ? 1 : max(0, 1 - (t - 0.45) / (dur - 0.45)))
                breath.a = Float(1 - exp(-2 * .pi * Double(1400 - 900 * t / dur) / sampleRate))
                let f0 = 150 - 55 * t / dur
                phase += f0 / sr
                let saw = 2 * (phase - floor(phase)) - 1
                out[i] = (breath.lp(noise()) * 1.4 + voice.lp(saw) * 0.35) * env
            }

        case .whistle:
            let dur: Float = 1.4
            let n = frames(Double(dur))
            out = .init(repeating: 0, count: n)
            var air = OnePole(3000)
            var phases: [Float] = [0, 0, 0]
            let tones: [Float] = [587.3, 740, 880]
            for i in 0..<n {
                let t = Float(i) / sr
                let env = min(1, t / 0.08) * (t > dur - 0.3 ? max(0, (dur - t) / 0.3) : 1)
                let slide = 0.93 + 0.07 * min(1, t / 0.12)
                let vib = 1 + 0.008 * sin(2 * .pi * 5.5 * t)
                var v: Float = 0
                for k in 0..<3 {
                    phases[k] += 2 * .pi * tones[k] * slide * vib / sr
                    v += sin(phases[k]) + 0.25 * sin(2 * phases[k])
                }
                out[i] = (v * 0.11 + air.hp(noise()) * 0.06) * env
            }

        case .pop:
            let n = frames(0.1)
            out = .init(repeating: 0, count: n)
            var phase: Float = 0
            for i in 0..<n {
                let t = Float(i) / sr
                phase += 2 * .pi * (250 + 650 * exp(-t * 40)) / sr
                out[i] = sin(phase) * exp(-t * 35) * 0.6
            }

        case .plug:
            let n = frames(0.16)
            out = .init(repeating: 0, count: n)
            var hp = OnePole(2000)
            for i in 0..<n {
                let t = Float(i) / sr
                let click = (t < 0.004 || (t > 0.055 && t < 0.06)) ? Float(1) : 0
                out[i] = hp.hp(noise()) * click * 0.9 + sin(2 * .pi * 2100 * t) * exp(-t * 60) * 0.25
            }

        case .sip:
            let n = frames(0.5)
            out = .init(repeating: 0, count: n)
            var lo = OnePole(2600), hi = OnePole(600)
            for i in 0..<n {
                let t = Float(i) / sr
                let am = pow(max(0, sin(2 * .pi * 9 * t)), 3)
                let x = lo.lp(noise())
                out[i] = (x - hi.lp(x)) * am * 1.6 * (1 - t / 0.5)
            }

        case .gasp:
            let n = frames(0.3)
            out = .init(repeating: 0, count: n)
            var hp = OnePole(800), lp = OnePole(4000)
            for i in 0..<n {
                let t = Float(i) / sr
                let env = t < 0.25 ? t / 0.25 : max(0, 1 - (t - 0.25) / 0.05)
                out[i] = lp.lp(hp.hp(noise())) * env * 0.8
            }
        }

        // Normalize gently so effects sit at similar loudness.
        let peak = out.map(abs).max() ?? 1
        if peak > 0 { let k = 0.8 / peak; for i in out.indices { out[i] *= k } }
        return out
    }
}

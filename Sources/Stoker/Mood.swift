import Foundation

/// How hard he shovels: how close the Mac is to using everything the charger gives.
/// Stepped rather than continuous so the animation doesn't restart on every small change.
enum Effort: Int, CaseIterable {
    case relaxed, steady, hard, frantic

    init(_ s: PowerStatus) {
        // No telemetry (older Macs): a steady middle pace.
        guard let load = s.chargerLoad else { self = .steady; return }
        switch load {
        case ..<0.5: self = .relaxed
        case ..<0.75: self = .steady
        case ..<0.9: self = .hard
        default: self = .frantic
        }
    }

    /// Seconds per shovel swing.
    var cycle: TimeInterval {
        switch self {
        case .relaxed: 1.6
        case .steady: 1.25
        case .hard: 0.95
        case .frantic: 0.7
        }
    }

    /// Beyond frantic: the charger is maxed out and the battery is draining anyway.
    static let overworkedCycle: TimeInterval = 0.6
}

/// What the little stoker is up to, derived from the power status.
enum Mood: String, CaseIterable, Identifiable {
    /// Plugged in and charging: shovel coal into the furnace.
    case shovelling
    /// Just plugged in and macOS hasn't started charging yet: shovel in hand, waiting for the coal.
    case warmingUp
    /// Plugged in but macOS paused charging (optimized charging, charge limit, heat…): coffee break.
    case onBreak
    /// Plugged in, but the charger is too weak: shovelling flat out while the fire still dies down.
    case overworked
    /// Plugged in at 100%: the coal keeps coming and buries the worker.
    case full
    /// On battery: shovel thrown away, beach chair out.
    case vacation
    /// On battery and low: pacing and sweating next to a dying furnace.
    case panicking

    var id: String { rawValue }

    init(_ s: PowerStatus) {
        guard s.hasBattery else { self = .shovelling; return }
        if s.onAC {
            // Check "full" first: at 100% macOS often keeps reporting IsCharging while it tops
            // off the last bit, sometimes even alongside FullyCharged.
            if s.isCharged || s.percent >= 100 { self = .full }
            else if s.isLosingPower { self = .overworked }
            else if s.isCharging { self = .shovelling }
            else if s.isWarmingUp { self = .warmingUp }
            else { self = .onBreak }
        } else {
            self = s.percent <= 20 ? .panicking : .vacation
        }
    }

    var isPluggedIn: Bool { self != .vacation && self != .panicking }

    /// Moods where he's holding the shovel and working.
    var isShovelling: Bool { self == .shovelling || self == .overworked }

    /// Moods where he has the shovel in hand, working or not.
    var holdsShovel: Bool { isShovelling || self == .warmingUp }

    var title: String {
        switch self {
        case .shovelling: "Shovelling coal"
        case .warmingUp: "Warming up"
        case .onBreak: "On a union break"
        case .overworked: "Can't keep up"
        case .full: "Buried in coal"
        case .vacation: "On vacation"
        case .panicking: "Panicking"
        }
    }

    var symbol: String {
        switch self {
        case .shovelling: "flame.fill"
        case .warmingUp: "hourglass"
        case .onBreak: "cup.and.saucer.fill"
        case .overworked: "flame"
        case .full: "mountain.2.fill"
        case .vacation: "beach.umbrella.fill"
        case .panicking: "exclamationmark.triangle.fill"
        }
    }

    /// Things the worker mutters now and then. Upper case only: the pixel font has no lower case.
    func lines(watts: Int?, deficit: Int? = nil, effort: Effort = .steady) -> [String] {
        switch self {
        case .shovelling:
            var l = ["MORE COAL!", "ANOTHER DAY, ANOTHER WATT", "MY BACK...", "SHOVEL SHOVEL SHOVEL",
                     "WHO KEEPS USING CHROME?", "ELECTRONS DON'T GROW ON TREES"]
            if let w = watts {
                l.append(w >= 90 ? "\(w)W?! SO MUCH COAL!" : "\(w)W. I'M ON IT")
            }
            switch effort {
            case .relaxed: l += ["NICE AND EASY", "EASY SHIFT TODAY"]
            case .steady: break
            case .hard: l += ["PUTTING MY BACK INTO IT", "BUSY DAY, BOSS?"]
            case .frantic: l += ["BARELY KEEPING UP!", "DON'T OPEN ANOTHER TAB"]
            }
            return l
        case .warmingUp:
            return ["WAITING ON MACOS...", "ANY SECOND NOW", "COAL'S ON ITS WAY", "WARMING UP THE BOILER",
                    "READY WHEN YOU ARE", "TAP TAP TAP"]
        case .onBreak:
            return ["UNION BREAK", "OPTIMIZED CHARGING, BABY", "COFFEE FIRST", "BOSS SAID WAIT",
                    "BATTERY HEALTH IS SELF CARE"]
        case .overworked:
            var l = ["I NEED A BIGGER SHOVEL", "IT'S GOING OUT FASTER THAN IT GOES IN", "PLUGGED IN AND STILL LOSING",
                     "CLOSE SOMETHING, BOSS", "WHO KEEPS USING CHROME?", "I'M SHOVELLING AS FAST AS I CAN",
                     "MORE COAL! NO, MORE THAN THAT!"]
            if let w = watts {
                l.append("\(w)W?! IS THIS A PHONE CHARGER?")
                l.append("ONLY \(w)W? I NEED A BIGGER SHOVEL")
            }
            if let d = deficit { l.append("-\(d)W. WE'RE SINKING") }
            return l
        case .full:
            return ["IT'S FULL!!", "STOP THE COAL!", "HELP", "100%. HAPPY NOW?", "UNPLUG ME PLEASE"]
        case .vacation:
            return ["AHHH...", "WAKE ME AT 20%", "NO CABLE, NO WORK", "ZZZ", "THIS IS THE LIFE"]
        case .panicking:
            return ["IS IT COLD IN HERE?", "BOSS? THE CABLE?", "PLUG ME IN!!", "THE FIRE'S GOING OUT!",
                    "WHERE'S THE CHARGER?!"]
        }
    }
}

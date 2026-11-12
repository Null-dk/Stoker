import Foundation

/// What the little stoker is up to, derived from the power status.
enum Mood: String, CaseIterable, Identifiable {
    /// Plugged in and charging: shovel coal into the furnace.
    case shovelling
    /// Plugged in but macOS paused charging (optimized charging, charge limit, heat…): coffee break.
    case onBreak
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
            else if s.isCharging { self = .shovelling }
            else { self = .onBreak }
        } else {
            self = s.percent <= 20 ? .panicking : .vacation
        }
    }

    var isPluggedIn: Bool { self == .shovelling || self == .onBreak || self == .full }

    var title: String {
        switch self {
        case .shovelling: "Shovelling coal"
        case .onBreak: "On a union break"
        case .full: "Buried in coal"
        case .vacation: "On vacation"
        case .panicking: "Panicking"
        }
    }

    var symbol: String {
        switch self {
        case .shovelling: "flame.fill"
        case .onBreak: "cup.and.saucer.fill"
        case .full: "mountain.2.fill"
        case .vacation: "beach.umbrella.fill"
        case .panicking: "exclamationmark.triangle.fill"
        }
    }

    /// Things the worker mutters now and then. Upper case only: the pixel font has no lower case.
    func lines(watts: Int?) -> [String] {
        switch self {
        case .shovelling:
            var l = ["MORE COAL!", "ANOTHER DAY, ANOTHER WATT", "MY BACK...", "SHOVEL SHOVEL SHOVEL",
                     "WHO KEEPS USING CHROME?", "ELECTRONS DON'T GROW ON TREES"]
            if let w = watts {
                l.append(w >= 90 ? "\(w)W?! SLOW DOWN!" : "\(w)W. I'M ON IT")
            }
            return l
        case .onBreak:
            return ["UNION BREAK", "OPTIMIZED CHARGING, BABY", "COFFEE FIRST", "BOSS SAID WAIT",
                    "BATTERY HEALTH IS SELF CARE"]
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

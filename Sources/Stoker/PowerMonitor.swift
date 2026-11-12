import Foundation
import IOKit.ps

/// A snapshot of what macOS reports about the battery and charger.
struct PowerStatus: Equatable {
    var hasBattery = false
    var onAC = true
    var isCharging = false
    var isCharged = false
    var percent = 100
    var watts: Int?
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    /// Battery current in mA from the smart battery: positive while charging, negative while draining.
    var amperage: Int?
    /// Power flowing into (+) or out of (−) the battery, in mW.
    var batteryMilliwatts: Int?
    /// What the Mac itself is using right now, in mW, not counting battery charging.
    var systemMilliwatts: Int?

    /// How much of the charger the Mac is using: 0.5 is half, above 1 means the battery tops it up.
    var chargerLoad: Double? {
        guard onAC, let w = watts, w > 0, let mw = systemMilliwatts, mw > 0 else { return nil }
        return Double(mw) / Double(w * 1000)
    }

    /// Plugged in, but the Mac uses more than the charger delivers, so the battery drains anyway.
    /// A deliberate pause (optimized charging, charge limit) holds the current near zero instead.
    /// Goes by the current alone: under load macOS can keep saying "charging" while it drains.
    var isLosingPower: Bool {
        guard hasBattery, onAC, let a = amperage else { return false }
        return a <= Self.drainThreshold
    }

    /// Below this current (mA) the battery is really draining, not just idling around zero.
    static let drainThreshold = -100

    /// How many watts the battery is losing while plugged in, rounded, at least 1.
    var deficitWatts: Int? {
        guard isLosingPower else { return nil }
        let mw = batteryMilliwatts.map(abs) ?? 0
        return max(1, Int((Double(mw) / 1000).rounded()))
    }
}

/// Listens for IOKit power-source notifications and reports changes.
final class PowerMonitor {
    var onChange: ((PowerStatus) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var last: PowerStatus?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        // Percent changes don't always trigger a notification; poll gently as a backup.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        let status = Self.read()
        guard status != last else { return }
        last = status
        onChange?(status)
    }

    static func read() -> PowerStatus {
        var s = PowerStatus()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return s }

        if let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            s.onAC = (providing as String) == kIOPSACPowerValue
        }

        let sources = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]) ?? []
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            s.hasBattery = true
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            s.percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            s.percent = Swift.min(100, Swift.max(0, s.percent))
            s.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            s.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                s.onAC = state == kIOPSACPowerValue
            }
            if let t = desc[kIOPSTimeToFullChargeKey] as? Int, t > 0 { s.minutesToFull = t }
            if let t = desc[kIOPSTimeToEmptyKey] as? Int, t > 0 { s.minutesToEmpty = t }
        }

        if s.hasBattery { readSmartBattery(into: &s) }

        if s.onAC, let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            s.watts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }
        return s
    }

    /// Battery current and power aren't in the IOPS dictionaries, so read them from IORegistry.
    /// macOS refreshes these roughly every half minute.
    private static func readSmartBattery(into s: inout PowerStatus) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }

        s.amperage = signed(dict["InstantAmperage"]) ?? signed(dict["Amperage"])
        let data = dict["BatteryData"] as? [String: Any]
        let telemetry = dict["PowerTelemetryData"] as? [String: Any]
        s.systemMilliwatts = signed(telemetry?["SystemLoad"])
        if let mw = signed(data?["BatteryPower"]) {
            s.batteryMilliwatts = mw
        } else if let a = s.amperage, let mv = signed(dict["Voltage"]) {
            s.batteryMilliwatts = a * mv / 1000
        }
    }

    /// The registry stores negative currents as 64-bit two's complement; reading the raw bits
    /// as Int64 gives the signed value whether the number arrives signed or unsigned.
    private static func signed(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: n.int64Value)
    }
}

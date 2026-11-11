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

        if s.onAC, let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            s.watts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }
        return s
    }
}

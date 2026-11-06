import Foundation
import IOKit.ps

/// Watches whether the Mac is running on battery (or in Low Power Mode).
final class PowerMonitor {
    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = false
    var onChange: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.refresh()
            monitor.onChange?()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
            self?.onChange?()
        }
    }

    deinit {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
    }

    private func refresh() {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        if let snapshot, let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() {
            isOnBattery = (type as String) == kIOPSBatteryPowerValue
        } else {
            isOnBattery = false   // desktops without a battery
        }
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

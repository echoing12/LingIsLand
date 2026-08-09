import Combine
import Foundation
import IOKit.ps

/// 电池管理器：监听电量与充电状态变化，插拔电源时弹电池 HUD
@MainActor
final class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    @Published private(set) var level: Float = 1.0   // 0...1
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false

    private var source: CFRunLoopSource?
    private var didInitialRefresh = false
    /// 上一次快照是否已满（闩锁：只在「由未满变满」的那一跳弹一次充满通知）
    private var wasFull = false

    private init() {
        refresh()
        startMonitoring()
    }

    func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else { return }

        let newLevel = Float(intValue(desc, kIOPSCurrentCapacityKey as String) ?? 100)
            / Float(max(1, intValue(desc, kIOPSMaxCapacityKey as String) ?? 100))
        let newPlugged = (desc[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
        let newCharging = desc["Is Charging"] as? Bool ?? false

        let pluggedChanged = newPlugged != isPluggedIn
        let chargingStarted = newPlugged && newCharging && !isCharging
        // 是否已充满：系统充满瞬间常把 isCharging 一并置 false，故不能依赖 isCharging，
        // 用 wasFull 闩锁「未满 → 满」的跳变，保证通知只弹一次
        let nowFull = newPlugged && newLevel >= 0.99

        isPluggedIn = newPlugged
        isCharging = newCharging
        level = newLevel

        // 插/拔电源瞬间弹电池 HUD（跳过首次快照，避免启动时误弹）
        if pluggedChanged && didInitialRefresh {
            HUDManager.shared.show(
                .battery,
                value: CGFloat(newLevel),
                icon: newCharging || newPlugged ? "bolt.fill" : "battery.75percent"
            )
        }

        // 岛内通知（仅开岛时可见）
        if didInitialRefresh {
            if chargingStarted {
                NotificationManager.shared.post(
                    icon: "bolt.fill", title: "正在充电", message: String(format: "电量 %.0f%%", newLevel * 100)
                )
            } else if pluggedChanged && !newPlugged {
                NotificationManager.shared.post(icon: "plug", title: "已断开电源", message: "开始使用电池")
            } else if nowFull && !wasFull {
                NotificationManager.shared.post(icon: "battery.100percent", title: "已充满", message: "拔掉电源保护电池")
            }
        }
        wasFull = nowFull
        didInitialRefresh = true
    }

    private func intValue(_ desc: [String: Any], _ key: String) -> Int? {
        if let v = desc[key] as? Int { return v }
        if let v = desc[key] as? NSNumber { return v.intValue }
        return nil
    }

    private func startMonitoring() {
        guard source == nil,
              let src = IOPSNotificationCreateRunLoopSource({ _ in
                  DispatchQueue.main.async { BatteryManager.shared.refresh() }
              }, nil)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }
}

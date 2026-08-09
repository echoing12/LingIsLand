import AppKit
import ApplicationServices
import Foundation

/// 媒体键拦截器：CGEventTap 拦截音量/静音/亮度键，吃掉系统事件（抑制系统 HUD），
/// 改由自绘 HUD 展示。需要「辅助功能」权限。
final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    /// kCGEventSystemDefined = 14（不同 SDK 里命名不一，直接用裸值最稳）
    private static let systemDefinedEvent = CGEventType(rawValue: 14)!

    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - 权限

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统授权引导。返回时不一定已授权（系统处理是异步的）。
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 启停

    func start() {
        // 设置里关闭了 HUD 替换则不拦截
        let hudEnabled = UserDefaults.standard.object(forKey: AppSettings.hudReplacement) as? Bool ?? true
        guard eventTap == nil, Self.isTrusted, hudEnabled else {
            if !Self.isTrusted { print("⚠️ 辅助功能权限未授权，媒体键拦截未启动") }
            return
        }

        let mask = CGEventMask(1 << Self.systemDefinedEvent.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handle(cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.runLoopSource = nil
        self.eventTap = nil
    }

    // MARK: - 事件处理

    private func handle(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard cgEvent.type != .null,
              let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)

        // 0xA = 按下，0xB = 抬起；只处理按下
        guard stateByte == 0xA,
              let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(cgEvent)
        }

        switch keyType {
        case .soundUp:
            Task { @MainActor in VolumeManager.shared.increase() }
        case .soundDown:
            Task { @MainActor in VolumeManager.shared.decrease() }
        case .mute:
            Task { @MainActor in VolumeManager.shared.toggleMute() }
        case .brightnessUp, .brightnessDown:
            // 亮度不可控时放行给系统，避免"按键无效"
            guard BrightnessManager.isAvailable else {
                return Unmanaged.passRetained(cgEvent)
            }
            let up = keyType == .brightnessUp
            Task { @MainActor in
                BrightnessManager.shared.setRelative(delta: up ? BrightnessManager.shared.step : -BrightnessManager.shared.step)
            }
        }

        return nil   // 吞掉事件，系统不再显示自带 HUD
    }
}

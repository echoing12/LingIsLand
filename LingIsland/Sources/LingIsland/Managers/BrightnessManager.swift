import AppKit
import Combine
import Foundation
import ObjectiveC.runtime

/// 亮度管理器：通过 CoreBrightness 私有框架的 ObjC 客户端读写屏幕亮度
/// （参考 Atoll 的 CoreBrightnessDisplayClient 实现，多 macOS 版本可用）
@MainActor
final class BrightnessManager: ObservableObject {
    static let shared = BrightnessManager()

    @Published private(set) var brightness: Float = 0.5   // 0...1

    /// 亮度控制是否可用。init 时确定、此后不变，nonisolated 以便事件拦截回调读取。
    nonisolated(unsafe) static var isAvailable = false

    let step: Float = 1.0 / 16.0

    private var clientInstance: NSObject?
    private let getSelector = NSSelectorFromString("brightnessForDisplay:")
    private let setSelector = NSSelectorFromString("setBrightness:forDisplay:")

    /// Apple 各版本用过的类名，从新到旧尝试
    private static let candidateClassNames = [
        "CBBrightnessProxy",
        "CBDisplayBrightnessClient",
        "BrightnessSystemClient",
        "DisplayBrightnessClient",
    ]

    private init() {
        loadClient()
    }

    // MARK: - 控制

    func refresh() {
        guard let value = currentBrightness() else { return }
        brightness = value
    }

    func setRelative(delta: Float) {
        guard Self.isAvailable else { return }
        let target = min(1, max(0, brightness + delta))
        guard setBrightness(target) else { return }
        brightness = target
        HUDManager.shared.show(.brightness, value: CGFloat(target))
        PetMoodManager.shared.trigger(.brightnessChanged(magnitude: abs(delta)))
    }

    // MARK: - CoreBrightness 客户端

    private func loadClient() {
        let bundlePaths = [
            "/System/Library/PrivateFrameworks/CoreBrightness.framework",
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
        ]
        var loaded = false
        for path in bundlePaths where !loaded {
            if let bundle = Bundle(path: path) { loaded = bundle.load() }
        }
        guard loaded else {
            print("⚠️ 加载 CoreBrightness.framework 失败，亮度 HUD 降级为放行系统")
            return
        }

        var resolved: NSObject.Type?
        for name in Self.candidateClassNames {
            if let cls = NSClassFromString(name) as? NSObject.Type {
                resolved = cls
                break
            }
        }
        guard let cls = resolved else {
            print("⚠️ 未找到 CoreBrightness 亮度客户端类，亮度 HUD 降级")
            return
        }

        clientInstance = cls.init()
        Self.isAvailable = clientInstance != nil && currentBrightness() != nil
        if Self.isAvailable { refresh() }
    }

    private func currentBrightness() -> Float? {
        guard let clientInstance,
              let getter: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
        else { return nil }
        let value = getter(clientInstance, getSelector, Self.builtInDisplayID)
        guard value >= 0, value <= 1 else { return nil }
        return value
    }

    @discardableResult
    private func setBrightness(_ value: Float) -> Bool {
        guard let clientInstance,
              let setter: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
        else { return false }
        return setter(clientInstance, setSelector, value, Self.builtInDisplayID).boolValue
    }

    private static let builtInDisplayID: UInt64 = 0

    private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

    private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector)
        else { return nil }
        let imp = method_getImplementation(method)
        return unsafeBitCast(imp, to: T.self)
    }
}

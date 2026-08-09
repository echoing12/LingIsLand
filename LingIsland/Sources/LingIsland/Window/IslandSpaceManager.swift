import AppKit

/// 把灵动岛窗口提到最高 CGSSpace 层级的私有 API 封装
/// 移植自 boring.notch（原出处 https://github.com/avaidyam/Parrot/，MPL-2.0）
final class IslandSpaceManager {
    static let shared = IslandSpaceManager()
    let notchSpace: CGSSpace

    private init() {
        notchSpace = CGSSpace(level: 2147483647) // Int32.max，最顶层
    }
}

public final class CGSSpace {
    private let identifier: CGSSpaceID
    /// CGSSpaceCreate 失败返回 0，后续私有 API 调用会崩溃；失败时降级为普通置顶窗口
    private let isValid: Bool

    public var windows: Set<NSWindow> = [] {
        didSet {
            guard isValid else { return }
            let remove = oldValue.subtracting(self.windows)
            let add = self.windows.subtracting(oldValue)

            CGSRemoveWindowsFromSpaces(_CGSDefaultConnection(),
                                       remove.map { $0.windowNumber } as NSArray,
                                       [self.identifier])
            CGSAddWindowsToSpaces(_CGSDefaultConnection(),
                                  add.map { $0.windowNumber } as NSArray,
                                  [self.identifier])
        }
    }

    /// 初始化的 CGSSpace 必须在退出时销毁！
    public init(level: Int = 0) {
        let flag = 0x1 // 必须为 1，否则 Finder 会绘制桌面图标
        let cid = _CGSDefaultConnection()
        let id = CGSSpaceCreate(cid, flag, nil)
        self.identifier = id
        self.isValid = id != 0
        if isValid {
            CGSSpaceSetAbsoluteLevel(cid, id, level)
            CGSShowSpaces(cid, [id])
        } else {
            print("⚠️ CGSSpaceCreate 失败，灵动岛提层降级为普通置顶窗口")
        }
    }

    deinit {
        guard isValid else { return }
        let cid = _CGSDefaultConnection()
        CGSHideSpaces(cid, [self.identifier])
        CGSSpaceDestroy(cid, self.identifier)
    }
}

// MARK: - 私有 API 声明

fileprivate typealias CGSConnectionID = UInt
fileprivate typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
fileprivate func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
fileprivate func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceDestroy")
fileprivate func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)

@_silgen_name("CGSSpaceSetAbsoluteLevel")
fileprivate func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)

@_silgen_name("CGSAddWindowsToSpaces")
fileprivate func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
fileprivate func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSHideSpaces")
fileprivate func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)

@_silgen_name("CGSShowSpaces")
fileprivate func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)

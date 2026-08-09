import AppKit
import CoreGraphics

/// 所有尺寸常量与真实刘海测量
enum NotchGeometry {
    // 开岛面板尺寸（功能区长度已压缩，左侧让出幽灵专属区）
    static let openWidth: CGFloat = 560
    static let openHeight: CGFloat = 190

    // 开岛时的顶部 tab 条高度
    static let openHeaderHeight: CGFloat = 32

    // 窗口固定尺寸（透明背景，仅内容动画，避免窗口 resize 抖动）
    // 高度多留出 HUD 浮层的空间（HUD 显示在胶囊下方）
    static let windowWidth: CGFloat = openWidth + 24
    static let windowHeight: CGFloat = openHeight + 70

    // HUD 浮层：胶囊底边到 HUD 胶囊的间距
    static let hudGap: CGFloat = 8

    // 圆角：开岛(上/下) —— 参考 boring.notch
    // 闭岛为「黑色胶囊」：两端圆角取高度一半，由 IslandView 按 real notch 高度计算
    static let openTopRadius: CGFloat = 19
    static let openBottomRadius: CGFloat = 24

    // 幽灵（始终在黑色胶囊/面板内部，不脱离黑色部位）
    static let petGap: CGFloat = 12          // 幽灵到胶囊边 / 内容区的间距
    static let petSizeClosed: CGFloat = 34
    static let petSizeOpen: CGFloat = 72     // 开岛更大更灵动
    /// 面板内容边距（功能区左右/底部留白）
    static let panelPadding: CGFloat = 12
    /// 闭岛胶囊为容纳幽灵，比刘海向两侧延伸的宽度
    static let petClosedOverhang: CGFloat = petSizeClosed + petGap
    /// 开岛面板左侧幽灵专属区宽度
    static let petZoneWidth: CGFloat = petSizeOpen + petGap * 2

    // 悬停展开延迟
    static let hoverOpenDelay: TimeInterval = 0.4
    static let hoverCloseDelay: TimeInterval = 0.15

    /// 精确测量真实刘海尺寸（用辅助区域宽度推算）
    @MainActor
    static func closedSize(screen: NSScreen) -> CGSize {
        var width: CGFloat = 185 // 兜底：无法测量时的常见刘海宽度
        var height: CGFloat = 34

        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            width = screen.frame.width - left - right + 4
        }
        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        }
        return CGSize(width: max(width, 120), height: max(height, 28))
    }
}

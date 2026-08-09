import AppKit
import Combine
import SwiftUI

enum IslandState {
    case closed
    case open
}

enum IslandTab: String, CaseIterable {
    case media = "媒体"
    case stats = "监控"
    case shelf = "文件"
}

/// 灵动岛状态机：closed/open 驱动尺寸与布局，弹簧动画由视图侧 .animation(value:) 驱动
@MainActor
final class IslandViewModel: ObservableObject {
    @Published var islandState: IslandState = .closed
    @Published var currentTab: IslandTab = .media
    @Published private(set) var closedSize: CGSize

    /// 拖拽文件 / 刚完成暂存期间抑制悬停自动关闭
    @Published var suppressAutoClose = false
    private var autoCloseSuppressionTask: Task<Void, Never>?

    /// 当前所在屏幕
    var screen: NSScreen?

    init(screen: NSScreen? = nil) {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        self.screen = target
        self.closedSize = target.map(NotchGeometry.closedSize) ?? CGSize(width: 185, height: 34)
    }

    /// 开岛
    func open() {
        guard islandState != .open else { return }
        islandState = .open
        PetMoodManager.shared.trigger(.islandOpened)
    }

    /// 关岛
    func close() {
        guard islandState != .closed else { return }
        islandState = .closed
        PetMoodManager.shared.trigger(.islandClosed)
    }

    /// 切换到某个 tab
    func switchTab(_ tab: IslandTab) {
        guard currentTab != tab else { return }
        currentTab = tab
    }

    /// 一段时间内抑制悬停自动关闭（拖文件进来 / 刚入架时防止松手瞬间误关）
    func suppressAutoCloseFor(_ seconds: TimeInterval = 2.5) {
        suppressAutoClose = true
        autoCloseSuppressionTask?.cancel()
        autoCloseSuppressionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.suppressAutoClose = false
        }
    }

    /// 屏幕或分辨率变化时更新测量数据
    func updateScreen(_ screen: NSScreen?) {
        guard let screen else { return }
        self.screen = screen
        self.closedSize = NotchGeometry.closedSize(screen: screen)
    }
}

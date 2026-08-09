import SwiftUI

/// 系统 HUD 管理器：显示自绘 HUD（音量/亮度/电池），1.2s 后自动隐藏
@MainActor
final class HUDManager: ObservableObject {
    static let shared = HUDManager()

    @Published private(set) var current: HUDItem?

    struct HUDItem: Identifiable {
        let id = UUID()
        let type: HUDType
        let value: CGFloat   // 0...1
        let icon: String
    }

    let visibleDuration: TimeInterval = 1.2

    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ type: HUDType, value: CGFloat, icon: String? = nil) {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            current = HUDItem(type: type, value: value, icon: icon ?? type.iconName)
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.visibleDuration ?? 1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self?.current = nil
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { current = nil }
    }
}

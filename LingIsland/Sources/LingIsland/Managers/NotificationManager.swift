import SwiftUI

/// 岛内通知：一条瞬态 toast（充电状态等），开岛时在内容区顶部显示，自动消失
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    struct IslandNotification: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let message: String
    }

    @Published private(set) var current: IslandNotification?

    let visibleDuration: TimeInterval = 2.5

    private var hideTask: Task<Void, Never>?

    private init() {}

    func post(icon: String, title: String, message: String) {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            current = IslandNotification(icon: icon, title: title, message: message)
        }
        PetMoodManager.shared.trigger(.notificationReceived)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.visibleDuration ?? 2.5))
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

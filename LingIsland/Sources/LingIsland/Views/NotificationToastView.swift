import SwiftUI

/// 岛内通知 toast：图标 + 标题 + 消息，出现在内容区顶部，自动消失
struct NotificationToastView: View {
    let notification: NotificationManager.IslandNotification

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notification.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(notification.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(notification.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

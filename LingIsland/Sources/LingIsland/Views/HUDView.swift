import SwiftUI

/// 自绘 HUD 胶囊：图标 + 进度条 + 数值，浮在刘海下方
struct HUDView: View {
    let item: HUDManager.HUDItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22)

            Capsule()
                .fill(.white.opacity(0.18))
                .frame(width: 90, height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 90 * clamp01(item.value), height: 6)
                }

            Text("\(Int((item.value * 100).rounded()))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(.black.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .transition(.scale(scale: 0.7, anchor: .top).combined(with: .opacity))
    }

    private func clamp01(_ v: CGFloat) -> CGFloat {
        min(1, max(0.02, v))
    }
}

import SwiftUI

/// 简易设置窗：几个开关 + 版本信息，@AppStorage 持久化
struct SettingsView: View {
    @AppStorage(AppSettings.showPet) private var showPet = true
    @AppStorage(AppSettings.hoverToOpen) private var hoverToOpen = true
    @AppStorage(AppSettings.hudReplacement) private var hudReplacement = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("显示小幽灵", isOn: $showPet)

            Toggle("悬停展开灵动岛", isOn: $hoverToOpen)

            Toggle("替换系统音量/亮度 HUD", isOn: $hudReplacement)
                .onChange(of: hudReplacement) { _, enabled in
                    if enabled {
                        MediaKeyInterceptor.shared.start()
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                }

            Divider()

            Text("灵岛 v0.1 · 用爱发电")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 280)
    }
}

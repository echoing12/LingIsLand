# 灵岛 (LingIsland) 👻

把 MacBook 的刘海变成 iPhone 式灵动岛 + 一只会陪你的小幽灵萌宠。

- 闭岛：黑色胶囊盖住刘海，把小幽灵**包含在胶囊内**（胶囊比刘海稍宽以容纳它）
- 开岛：面板展开（媒体 / 监控 / 文件 三 tab），幽灵**留在岛上左侧**（黑色内部），变大变灵动，开岛时幽灵直接飘下来
- 支持在**全屏 App** 上方显示（CGSSpace 窗口提层）
- 零第三方依赖，仅系统框架 + 少量私有 API

## 功能

| 功能 | 说明 |
|---|---|
| 🎵 媒体控制 | Apple Music / Spotify 封面、标题、进度条、播放/暂停/切歌 |
| 🔊 系统 HUD | 按音量/亮度/静音键 → 系统 HUD 被替换为灵动岛自绘 HUD，狐狸同步反应 |
| 📊 系统监控 | CPU / 内存 / 网络 / 磁盘 实时 sparkline |
| 📥 文件暂存 | 把文件拖向屏幕顶部自动开岛到文件 tab，暂存后点按取回 |
| 🔋 电池通知 | 插拔电源 / 充满时弹通知与电池 HUD |
| 👻 萌宠心情 | 漂浮眨眼·裙摆起伏 / 播放开心挥手+星星 / 开岛直接飘下来变大变灵动 / 拖文件好奇歪头 / 深夜犯困飘 zZ Z / 眼睛追随光标 / **点击戳它：压扁弹起+boo!+爆星星** / **双击：跳起舞来♪**（放音乐时也会跟着跳）/ **会说话：开岛问好·道别·切歌/拖文件/收通知都有台词气泡** |

## 支持与打赏

如果灵岛让你开心，欢迎 [请作者喝杯奶茶 ☕](https://echoing12.github.io/LingIsLand/#donate)——微信 / 支付宝赞赏码都在落地页的打赏区。

## 构建与运行

```bash
cd LingIsland
swift build          # 编译验证
./scripts/make_app.sh   # 打包为 dist/LingIsland.app
./scripts/make_dmg.sh   # 打包为可拖拽安装的 dist/LingIsland-<版本>.dmg
open dist/LingIsland.app
```

App 图标取自落地页吉祥物（`Resources/AppIcon.svg`），改图形后用 `./scripts/make_icon.sh` 重新生成 `.icns`。

## 首次使用

1. **辅助功能权限**：要替换系统音量/亮度 HUD，需在菜单栏「灵岛」图标 → 「开启辅助功能权限」里授权一次（系统偏好设置 → 隐私与安全性 → 辅助功能）。不授权也能正常使用其它全部功能。
2. **菜单栏**：小幽灵图标可打开/关闭灵动岛、发送测试通知、设置、退出。

## 架构速览

```
Sources/LingIsland/
├── Window/        IslandSpaceManager（CGSSpace 提层）· IslandWindow · NotchGeometry
├── ViewModel/     IslandViewModel（状态机：closed/open + tab）
├── Views/         IslandView（胶囊+幽灵+HUD+通知层）· MediaPlayerView · StatsView · ShelfView · SettingsView
│   └── Pet/       GhostView（矢量幽灵）· PetMood · PetMoodManager（心情状态机）
├── Managers/      MediaManager · VolumeManager · BrightnessManager · BatteryManager
│                  StatsManager · ShelfManager · NotificationManager · MediaKeyInterceptor
└── Models/        PlaybackState · HUDModels
Sources/MediaRemoteAdapter/    MediaRemote 私有框架薄封装（子进程，JSON lines 输出）
```

媒体信息读取经 `MediaRemoteAdapter` 子进程隔离私有 API（兼容 macOS 15.4+，参考 [boring.notch](https://github.com/nicemicro/boring.notch)），框架二进制来自 boring.notch（BSD 3-Clause，见 `LingIsland/Resources/THIRD_PARTY_NOTICE.md`）。

## 已知限制

- 音量/亮度 HUD 替换需要辅助功能权限
- 显示亮度控制走 CoreBrightness 私有 API（Apple Silicon 可用，失败时优雅放行系统）
- 屏幕录制权限不需要（不碰摄像头/录屏）

## 版权声明

© 2026 灵岛（LingIsland）· **保留所有权利（All Rights Reserved）** · 未经作者书面许可，不得复制、修改、分发或用于商业用途。
第三方组件（`MediaRemoteAdapter.framework`，BSD 3-Clause）版权归其原作者所有，见 `LingIsland/Resources/THIRD_PARTY_NOTICE.md`。

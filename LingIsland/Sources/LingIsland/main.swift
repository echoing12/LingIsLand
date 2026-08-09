import AppKit

// 手动启动 NSApplication —— 比 SwiftUI @main 更稳，SPM executable 也完全兼容
let app = NSApplication.shared
// 顶层 main 不在 MainActor 隔离区，但 NSApplication 初始化运行在主线程上
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory) // 无 Dock 图标，纯辅助工具
app.run()

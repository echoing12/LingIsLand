import AppKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.lingisland.app", category: "AppDelegate")

/// 对外链接：打赏页 = 落地页（GitHub Pages）的打赏区锚点
enum AppLinks {
    static let donate = URL(string: "https://echoing12.github.io/LingIsLand/#donate")!
}

/// 应用入口代理：创建灵动岛窗口、菜单栏、启动各功能管理器
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: IslandWindow?
    var statusItem: NSStatusItem?
    var settingsWindow: NSPanel?

    let viewModel = IslandViewModel()
    let petManager = PetMoodManager.shared
    let hudManager = HUDManager.shared
    let notificationManager = NotificationManager.shared

    /// 全局文件拖拽监听：非激活窗口上 .onDrop 不可靠，用它感知「拖文件到顶部」
    private var dragDetector: DragDetector?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createIslandWindow()
        setupDragDetector()
        setupMenuBar()
        MediaManager.shared.start()
        _ = BatteryManager.shared
        startMediaKeyInterceptor()

        // 多屏 / 分辨率变化时重新定位
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        viewModel.updateScreen(NSScreen.screens.first)
        if let win = window {
            positionWindow(win)
            dragDetector?.updateRegion(win.frame)
        }
    }

    private func startMediaKeyInterceptor() {
        if MediaKeyInterceptor.isTrusted {
            MediaKeyInterceptor.shared.start()
        } else {
            // 未授权时不拦截（系统 HUD 正常工作），菜单里引导授权
            log.info("辅助功能未授权：媒体键 HUD 拦截关闭，可在菜单栏「灵岛」菜单中授权")
        }
    }

    // MARK: - 灵动岛窗口

    private func createIslandWindow() {
        let rect = NSRect(
            x: 0, y: 0,
            width: NotchGeometry.windowWidth,
            height: NotchGeometry.windowHeight
        )
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        let win = IslandWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        let rootView = IslandView()
            .environmentObject(viewModel)
            .environmentObject(petManager)
            .environmentObject(hudManager)
            .environmentObject(notificationManager)

        win.contentView = NSHostingView(rootView: rootView)
        win.orderFrontRegardless()

        IslandSpaceManager.shared.notchSpace.windows.insert(win)
        positionWindow(win)

        self.window = win
    }

    private func positionWindow(_ win: NSWindow) {
        guard let screen = viewModel.screen else { return }
        let f = screen.frame
        win.setFrameOrigin(
            NSPoint(x: f.midX - win.frame.width / 2, y: f.maxY - win.frame.height)
        )
    }

    /// 全局监听文件拖拽：带着文件拖进顶部窗口区域 → 自动开岛到文件 tab；在岛内松手 → 收下文件
    private func setupDragDetector() {
        guard let win = window else { return }

        let detector = DragDetector(notchRegion: win.frame)
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.viewModel.islandState != .open {
                    self.viewModel.open()
                }
                self.viewModel.switchTab(.shelf)
                // 拖拽期间抑制悬停自动关闭，方便把文件对准面板
                self.viewModel.suppressAutoCloseFor(3)
            }
        }
        detector.onDragExitsNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.viewModel.suppressAutoClose = false
            }
        }
        detector.onDropInNotchRegion = { [weak self] urls in
            Task { @MainActor in
                guard let self else { return }
                for url in urls {
                    ShelfManager.shared.add(url)
                }
                if !urls.isEmpty {
                    PetMoodManager.shared.trigger(.fileDropped)
                }
                // 松手后短暂保持打开，让用户看到文件已入架
                self.viewModel.suppressAutoCloseFor(2.5)
            }
        }

        detector.startMonitoring()
        dragDetector = detector
    }

    // MARK: - 菜单栏

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "ghost", accessibilityDescription: "灵岛")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 / 关闭灵动岛", action: #selector(toggleIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(NSMenuItem(title: "打赏支持 ☕", action: #selector(openDonate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "发送测试通知", action: #selector(sendTestNotification), keyEquivalent: ""))

        if !MediaKeyInterceptor.isTrusted {
            let item = NSMenuItem(title: "开启辅助功能权限（拦截音量/亮度 HUD）", action: #selector(requestAccessibility), keyEquivalent: "")
            item.isEnabled = !MediaKeyInterceptor.isTrusted
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出灵岛", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu

        self.statusItem = item
    }

    @objc private func requestAccessibility() {
        if MediaKeyInterceptor.requestTrust() {
            // 授权后重启事件拦截
            MediaKeyInterceptor.shared.start()
        }
    }

    /// 打赏：打开落地页打赏区（收款码在网页端，不入 app 包）
    @objc private func openDonate() {
        NSWorkspace.shared.open(AppLinks.donate)
    }

    @objc private func sendTestNotification() {
        viewModel.open()
        NotificationManager.shared.post(
            icon: "sparkles",
            title: "测试通知",
            message: "灵岛已就绪 ✨"
        )
    }

    @objc private func toggleIsland() {
        if viewModel.islandState == .open {
            viewModel.close()
        } else {
            viewModel.open()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "灵岛设置"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SettingsView())
            panel.center()
            settingsWindow = panel
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaManager.shared.stop()
        IslandSpaceManager.shared.notchSpace.windows.removeAll()
    }
}

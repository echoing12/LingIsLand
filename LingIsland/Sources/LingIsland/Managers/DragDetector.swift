import AppKit
import UniformTypeIdentifiers

/// 文件拖拽监听：轮询拖拽粘贴板 + 左键按下状态，感知「拖文件到屏幕顶部」。
///
/// 为什么不用 NSEvent.addGlobalMonitorForEvents：实测在这台 macOS 26 机器上，
/// 全局鼠标事件监听收不到任何事件（疑似新系统对鼠标事件的节流/投递回归），
/// 而 CGEventTap 又需要「输入监听/辅助功能」权限。轮询 `NSPasteboard(name: .drag)`
/// 的 changeCount + `CGEventSource.buttonState` 判断左键是否按住，既不依赖事件投递，
/// 也不需要任何权限。
final class DragDetector {
    // MARK: - 回调

    /// 拖拽带着文件内容进入灵动岛区域
    var onDragEntersNotchRegion: (() -> Void)?
    /// 拖拽带着文件内容离开灵动岛区域
    var onDragExitsNotchRegion: (() -> Void)?
    /// 在灵动岛区域内松手放下，附带被拖的文件 URL
    var onDropInNotchRegion: (([URL]) -> Void)?

    // MARK: - 状态

    private var timer: Timer?
    private var lastChangeCount = -1
    private var isContentDragging = false
    private var hasEnteredNotchRegion = false

    private var notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

    /// 屏幕 / 分辨率变化时更新监听区域（随窗口重定位）
    func updateRegion(_ region: CGRect) {
        notchRegion = region
    }

    /// 拖拽粘贴板里是否有文件 URL（只对文件拖拽开岛，拖文本/纯链接不误开）
    private var hasValidDragContent: Bool {
        dragPasteboard.types?.contains(.fileURL) ?? false
    }

    // MARK: - 监听

    func startMonitoring() {
        stopMonitoring()
        lastChangeCount = dragPasteboard.changeCount
        log("startMonitoring region=\(notchRegion) lastCC=\(lastChangeCount)")

        // 0.1s 一轮（10Hz）足够跟手，且空闲时不触发昂贵的系统调用（见 poll 的尽早退出）
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    // MARK: - 轮询

    private func poll() {
        let current = dragPasteboard.changeCount
        // 无新拖拽内容且当前不在内容拖拽中 → 尽早返回，省掉 pressedMouseButtons 系统调用
        // （非文件拖拽也会改 changeCount，但 hasValidDragContent 会把它们过滤掉，无需跟踪其左键）
        if current == lastChangeCount && !isContentDragging {
            return
        }

        // NSEvent.pressedMouseButtons 是非阻塞查询；CGEventSource.buttonState 有已知的阻塞问题
        let leftDown = NSEvent.pressedMouseButtons & 0x1 != 0

        // 左键没按住：拖拽结束（或从未在拖）
        if !leftDown {
            if isContentDragging && hasEnteredNotchRegion {
                let urls = readDraggedFileURLs()
                if !urls.isEmpty {
                    log("DROP urls=\(urls.map(\.lastPathComponent))")
                    onDropInNotchRegion?(urls)
                }
            }
            isContentDragging = false
            hasEnteredNotchRegion = false
            lastChangeCount = current
            return
        }

        // 左键按住中：粘贴板内容变化 → 新一轮文件拖拽开始
        if current != lastChangeCount {
            lastChangeCount = current
            if hasValidDragContent && !isContentDragging {
                isContentDragging = true
                hasEnteredNotchRegion = false
                log("contentDrag detected types=\(dragPasteboard.types?.map(\.rawValue) ?? [])")
            }
        }

        guard isContentDragging else { return }
        let mouse = NSEvent.mouseLocation
        let contains = notchRegion.contains(mouse)
        if contains && !hasEnteredNotchRegion {
            hasEnteredNotchRegion = true
            log("ENTER region mouse=\(mouse)")
            onDragEntersNotchRegion?()
        } else if !contains && hasEnteredNotchRegion {
            hasEnteredNotchRegion = false
            log("EXIT region mouse=\(mouse)")
            onDragExitsNotchRegion?()
        }
    }

    // MARK: - 读取文件

    /// 松手时从拖拽粘贴板里读出被拖的文件 URL
    private func readDraggedFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = dragPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return []
        }
        return urls
    }

    // print 到非 tty 会块缓冲，日志用 FileHandle 实时写
    private func log(_ msg: String) {
        FileHandle.standardOutput.write(Data("[DragDetector] \(msg)\n".utf8))
    }

    deinit {
        stopMonitoring()
    }
}

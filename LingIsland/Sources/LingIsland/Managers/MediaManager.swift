import AppKit
import Combine
import Foundation
import os

/// 媒体控制管理器：常驻启动 /usr/bin/perl + mediaremote.pl（stream 模式）解析"现在播放"信息，
/// 播放控制走一次性 send/seek 调用，私有 API 全部隔离在 perl + 适配器内。
/// 必须用 /usr/bin/perl：macOS 15.4+ 起 MediaRemote 只放行 bundle id 以 com.apple. 开头的进程，
/// 而 /usr/bin/perl 的 bundle id 是 com.apple.perl5。
private let log = Logger(subsystem: "com.lingisland.app", category: "MediaManager")

@MainActor
final class MediaManager: ObservableObject {
    static let shared = MediaManager()

    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var albumArt: NSImage?
    @Published var bundleIdentifier = ""
    @Published var playbackRate: Double = 1.0

    var appName: String { Self.displayName(for: bundleIdentifier) }
    /// 播放进度 0...1
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    private var streamProcess: Process?
    private var streamPipe: Pipe?
    private var tickerTask: Task<Void, Never>?
    private var lastTitle = ""
    private var lastPlaying = false

    /// 适配器异常退出后的重启退避状态（防止崩溃后无限 2s 重拉）
    private var restartAttempts = 0
    private let maxRestartAttempts = 5
    /// 主动停止（应用退出）后不再重启
    private var isStopping = false

    // 播放时间锚点（用于 ticker 推进 elapsed）
    private var anchorElapsed: TimeInterval = 0
    private var anchorDate = Date()

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard streamProcess == nil else { return }
        isStopping = false
        guard let scriptURL = Self.locateScript(),
              let frameworkDir = Self.locateFrameworkDir() else {
            log.warning("找不到 mediaremote.pl 或 MediaRemoteAdapter.framework")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkDir.path, "stream"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardInput = Pipe()
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.streamProcess = nil
                self?.restartStream()
            }
        }
        do {
            try process.run()
            self.streamProcess = process
            self.streamPipe = pipe
            restartAttempts = 0   // 启动成功，重置退避计数
            startReading()
            startTicker()
        } catch {
            log.error("启动 MediaRemoteAdapter 失败: \(error, privacy: .public)")
        }
    }

    func stop() {
        isStopping = true
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        tickerTask?.cancel()
        streamProcess?.terminate()
        streamProcess = nil
        streamPipe = nil
    }

    /// 适配器异常退出后重启：指数退避（2s → 5s → 15s），达上限停止，避免崩溃风暴
    private func restartStream() {
        guard !isStopping, streamProcess == nil else { return }
        guard restartAttempts < maxRestartAttempts else {
            log.warning("MediaRemoteAdapter 连续失败 \(self.restartAttempts) 次，停止自动重启")
            return
        }
        restartAttempts += 1
        let delay: TimeInterval
        switch restartAttempts {
        case 1: delay = 2
        case 2: delay = 5
        default: delay = 15
        }
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !isStopping, streamProcess == nil else { return }
            start()
        }
    }

    // MARK: - 读取 JSON lines

    private func startReading() {
        guard let pipe = streamPipe else { return }
        let handle = pipe.fileHandleForReading
        var buffer = ""

        // readabilityHandler 由 Foundation 在后台串行队列回调，读管道不阻塞主线程。
        // 之前用 Task { } 继承 MainActor，把 handle.read(upToCount:) 的同步阻塞读跑在
        // 主线程上：适配器没歌可报时管道静默 → 主线程永久卡死 → 悬停转圈、拖拽/点击全失效。
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            buffer += String(data: data, encoding: .utf8) ?? ""
            var lines: [String] = []
            while let range = buffer.range(of: "\n") {
                let line = String(buffer[..<range.lowerBound])
                buffer.removeSubrange(...range.lowerBound)
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append(line)
                }
            }
            guard !lines.isEmpty, let self else { return }
            let updates: [NowPlayingUpdate] = lines.compactMap { line in
                guard let d = line.data(using: .utf8),
                      let update = try? JSONDecoder().decode(NowPlayingUpdate.self, from: d)
                else { return nil }
                return update
            }
            guard !updates.isEmpty else { return }
            Task { @MainActor in
                for update in updates {
                    self.apply(update.payload)
                }
            }
        }
    }

    private func startTicker() {
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard let self, self.isPlaying else { continue }
                let delta = Date().timeIntervalSince(self.anchorDate) * self.playbackRate
                self.elapsed = self.anchorElapsed + delta
                if self.duration > 0, self.elapsed > self.duration {
                    self.elapsed = self.duration
                }
            }
        }
    }

    // MARK: - 应用数据

    private func apply(_ p: NowPlayingPayload) {
        if let t = p.title { title = t }
        if let a = p.artist { artist = a }
        if let al = p.album { album = al }
        if let d = p.duration { duration = d }
        if let rate = p.playbackRate { playbackRate = rate }
        if let playing = p.playing { isPlaying = playing }
        if let bid = p.parentApplicationBundleIdentifier ?? p.bundleIdentifier, !bid.isEmpty {
            bundleIdentifier = bid
        }
        if let art = p.artworkData,
           let data = Data(base64Encoded: art.trimmingCharacters(in: .whitespacesAndNewlines)),
           let img = NSImage(data: data) {
            albumArt = img
        } else if p.playing == false {
            // 停止播放时清掉旧封面，避免残留上一首歌的图
            albumArt = nil
        }
        if let e = p.elapsedTime {
            anchorElapsed = e
            anchorDate = Date()
            elapsed = e
        }

        if isPlaying != lastPlaying {
            lastPlaying = isPlaying
            PetMoodManager.shared.trigger(.mediaPlaying(isPlaying))
        }
        if !title.isEmpty, title != lastTitle {
            if !lastTitle.isEmpty { PetMoodManager.shared.trigger(.trackChanged) }
            lastTitle = title
        }
    }

    // MARK: - 播放控制

    func togglePlayPause() {
        send(command: 2)
    }

    func nextOrPrevious(backward: Bool) {
        send(command: backward ? 5 : 4)
    }

    func seek(to time: TimeInterval) {
        runAdapter(["seek", String(format: "%.3f", time)])
        anchorElapsed = time
        anchorDate = Date()
        elapsed = time
    }

    private func send(command: Int) {
        runAdapter(["send", "\(command)"])
        if command == 2 {
            isPlaying.toggle()
            PetMoodManager.shared.trigger(.mediaPlaying(isPlaying))
        }
    }

    private func runAdapter(_ extra: [String]) {
        guard let scriptURL = Self.locateScript(), let frameworkDir = Self.locateFrameworkDir() else { return }
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = [scriptURL.path, frameworkDir.path] + extra
            p.standardOutput = Pipe()
            p.standardInput = Pipe()
            try? p.run()
            p.waitUntilExit()
        }
    }

    // MARK: - 路径定位

    static func locateScript() -> URL? {
        // 1. app bundle 内 Resources
        if let bundleURL = Bundle.main.url(forResource: "mediaremote", withExtension: "pl") {
            return bundleURL
        }
        // 2. 与主程序同目录（SPM debug 构建）
        let exeDir = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let adjacent = exeDir.appendingPathComponent("mediaremote.pl")
        if FileManager.default.fileExists(atPath: adjacent.path) { return adjacent }
        return nil
    }

    /// 返回 framework 目录（perl 脚本内部自己解析实际 dylib 路径）
    static func locateFrameworkDir() -> URL? {
        // 1. app bundle 内 PrivateFrameworks。
        //    不要用 Bundle.main.privateFrameworksPath —— 实测它在 macOS 26 上返回
        //    Contents/Frameworks，而 make_app.sh 把框架放进 Contents/PrivateFrameworks，
        //    会导致打包后误判 framework 不存在、媒体管道起不来。这里显式构造路径。
        let bundleFw = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PrivateFrameworks/MediaRemoteAdapter.framework")
        if FileManager.default.fileExists(atPath: bundleFw.path) { return bundleFw }
        // 2. 兜底：privateFrameworksPath 指向的位置（部分打包方式会放 Contents/Frameworks）
        if let fw = Bundle.main.privateFrameworksPath {
            let u = URL(fileURLWithPath: fw).appendingPathComponent("MediaRemoteAdapter.framework")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        // 3. 开发时：包目录下 Resources/
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/MediaRemoteAdapter.framework")
        if FileManager.default.fileExists(atPath: dev.path) { return dev }
        return nil
    }

    static func displayName(for bundleID: String) -> String {
        switch bundleID {
        case "com.apple.Music": return "Apple Music"
        case "com.spotify.client": return "Spotify"
        case "com.apple.music": return "音乐"
        default:
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first?.localizedName ?? ""
        }
    }
}

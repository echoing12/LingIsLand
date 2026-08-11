import Darwin
import Foundation

// MediaRemoteAdapter —— 对 MediaRemoteAdapter.framework 的薄封装
//
// 注意：macOS 15.4+ 起 MediaRemote 只放行 bundle id 以 com.apple. 开头的进程读取
// Now Playing。本二进制由应用 spawn，bundle id 非 com.apple.*，dlopen 框架后会被
// MediaRemote 拒绝（"Operation not permitted"），无法读到数据。已废弃，改由
// /usr/bin/perl 运行 Resources/mediaremote.pl（perl 的 bundle id 是 com.apple.perl5）。
// 保留本文件仅作防御性备份。
//
// 用法:
//   MediaRemoteAdapter <framework路径> stream
//   MediaRemoteAdapter <framework路径> send <命令ID>
//   MediaRemoteAdapter <framework路径> seek <秒>
//   MediaRemoteAdapter <framework路径> test
//
// stream 模式常驻运行，把"现在播放"信息以 JSON lines 打印到 stdout。
// send / seek 为一次性命令（media 应用状态变更后，stream 进程会收到通知自动刷新）。

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(
        "usage: MediaRemoteAdapter <framework> <stream|send|seek|test> [param]\n".data(using: .utf8)!)
    exit(2)
}

let frameworkPath = args[1]
let mode = args[2]

guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
    FileHandle.standardError.write("dlopen failed: \(String(cString: dlerror()))\n".data(using: .utf8)!)
    exit(1)
}

typealias VoidFn = @convention(c) () -> Void

func load(_ name: String) -> VoidFn? {
    guard let sym = dlsym(handle, name) else { return nil }
    return unsafeBitCast(sym, to: VoidFn.self)
}

switch mode {
case "stream":
    // 全量输出（非 diff），50ms 防抖
    setenv("MEDIAREMOTEADAPTER_OPTION_no_diff", "1", 1)
    setenv("MEDIAREMOTEADAPTER_OPTION_debounce", "50", 1)

    // 父进程退出 → stdin 读到 EOF → 自己退出，避免泄漏孤儿进程。
    // 用 readabilityHandler：EOF 时回调一次且 availableData 为空，不会忙等烧 CPU。
    DispatchQueue.global().async {
        let handle = FileHandle.standardInput
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { exit(0) }
        }
    }

    guard let f = load("adapter_stream_env") else { exit(1) }
    f() // 阻塞常驻
    exit(0)

case "send":
    guard args.count >= 4 else { exit(2) }
    setenv("MEDIAREMOTEADAPTER_PARAM_adapter_send_0_command", args[3], 1)
    guard let f = load("adapter_send_env") else { exit(1) }
    f()

case "seek":
    guard args.count >= 4 else { exit(2) }
    let micros = Int((Double(args[3]) ?? 0) * 1_000_000)
    setenv("MEDIAREMOTEADAPTER_PARAM_adapter_seek_0_position", "\(micros)", 1)
    guard let f = load("adapter_seek_env") else { exit(1) }
    f()

case "test":
    guard let f = load("adapter_test") else { exit(1) }
    f()

default:
    exit(2)
}

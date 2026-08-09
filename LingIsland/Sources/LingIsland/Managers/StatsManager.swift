import Combine
import Darwin
import Foundation

/// 系统监控管理器：定时采样 CPU / 内存 / 网络 / 磁盘，保留历史数据画 sparkline
@MainActor
final class StatsManager: ObservableObject {
    static let shared = StatsManager()

    // 当前值
    @Published private(set) var cpuUsage: Double = 0       // %
    @Published private(set) var memoryUsage: Double = 0    // %
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var networkDown: Double = 0    // MB/s
    @Published private(set) var networkUp: Double = 0
    @Published private(set) var diskUsage: Double = 0      // %
    @Published private(set) var diskUsedGB: Double = 0

    // 30 点历史（sparkline）
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var networkHistory: [Double] = []

    /// sparkline 窗口大小
    let historyCount = 30
    /// 采样间隔
    let sampleInterval: TimeInterval = 2.0

    private var timerTask: Task<Void, Never>?

    // 差分状态
    private var previousCPULoad: host_cpu_load_info?
    private var previousNetwork = (down: UInt64(0), up: UInt64(0), at: Date())

    private init() {}

    // MARK: - 生命周期

    /// 监控 tab 出现时调用
    func start() {
        guard timerTask == nil else { return }
        sample()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.sampleInterval ?? 2.0))
                self?.sample()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - 采样

    func sample() {
        let cpu = sampleCPU()
        cpuUsage = cpu
        append(&cpuHistory, cpu)

        let mem = sampleMemory()
        memoryUsage = mem.usage
        memoryUsedGB = mem.usedGB
        append(&memoryHistory, mem.usage)

        let net = sampleNetwork()
        networkDown = net.down
        networkUp = net.up
        append(&networkHistory, net.down)

        let disk = sampleDisk()
        diskUsage = disk.usage
        diskUsedGB = disk.usedGB
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > historyCount {
            history.removeFirst(history.count - historyCount)
        }
    }

    // MARK: - CPU（host_statistics 差分）

    private func sampleCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpuUsage }

        if let previous = previousCPULoad {
            let user = Double(info.cpu_ticks.0 - previous.cpu_ticks.0)
            let system = Double(info.cpu_ticks.1 - previous.cpu_ticks.1)
            let idle = Double(info.cpu_ticks.2 - previous.cpu_ticks.2)
            let nice = Double(info.cpu_ticks.3 - previous.cpu_ticks.3)
            let total = user + system + idle + nice
            previousCPULoad = info
            guard total > 0 else { return cpuUsage }
            return min(100, max(0, (user + system + nice) / total * 100))
        } else {
            // 首次采样无差分基准，直接按累计占比估算
            previousCPULoad = info
            let total = Double(info.cpu_ticks.0 + info.cpu_ticks.1 + info.cpu_ticks.2 + info.cpu_ticks.3)
            guard total > 0 else { return 0 }
            return min(100, max(0, Double(info.cpu_ticks.0 + info.cpu_ticks.1 + info.cpu_ticks.3) / total * 100))
        }
    }

    // MARK: - 内存（host_statistics64）

    private func sampleMemory() -> (usage: Double, usedGB: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (memoryUsage, memoryUsedGB) }

        let pageSize = Double(vm_kernel_page_size)
        let total = Double(stats.active_count + stats.inactive_count + stats.wire_count
                           + stats.free_count + stats.speculative_count + stats.compressor_page_count) * pageSize
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        guard total > 0 else { return (memoryUsage, memoryUsedGB) }
        return (used / total * 100, used / 1e9)
    }

    // MARK: - 网络（getifaddrs 差分）

    private func sampleNetwork() -> (down: Double, up: Double) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let ifaddrPtr else { return (networkDown, networkUp) }
        defer { freeifaddrs(ifaddrPtr) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = ifaddrPtr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            if flags & IFF_UP != 0,
               flags & IFF_RUNNING != 0,                       // 过滤未运行的桥接/虚拟口
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: current.pointee.ifa_name)
                // 只认常见物理网卡，排除 Thunderbolt 桥（en5+）等，避免同一份流量被重复计入
                if Self.isNetworkInterface(name),
                   let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    down += UInt64(data.pointee.ifi_ibytes)
                    up += UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = current.pointee.ifa_next
        }

        let now = Date()
        let interval = max(now.timeIntervalSince(previousNetwork.at), 0.1)
        let downRate = Double(down - previousNetwork.down) / interval / 1e6   // MB/s
        let upRate = Double(up - previousNetwork.up) / interval / 1e6
        previousNetwork = (down, up, now)
        return (max(0, downRate), max(0, upRate))
    }

    /// 常见物理网络接口：Wi-Fi（en0）/ 有线（en1）。Thunderbolt 桥（en5+）、虚拟适配器等
    /// 会重复计入同一份流量，需排除。
    private static func isNetworkInterface(_ name: String) -> Bool {
        name == "en0" || name == "en1"
    }

    // MARK: - 磁盘（卷容量）

    private func sampleDisk() -> (usage: Double, usedGB: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity else {
            return (diskUsage, diskUsedGB)
        }
        let used = Double(total - available)
        guard total > 0 else { return (diskUsage, diskUsedGB) }
        return (used / Double(total) * 100, used / 1e9)
    }
}

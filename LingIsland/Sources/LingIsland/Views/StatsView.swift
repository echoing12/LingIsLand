import SwiftUI

/// 系统监控面板：CPU / 内存 / 网络 / 磁盘 四宫格 + sparkline
struct StatsView: View {
    @ObservedObject private var stats = StatsManager.shared

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            statCard(
                title: "CPU",
                icon: "cpu",
                value: "\(Int(stats.cpuUsage.rounded()))%",
                history: stats.cpuHistory,
                color: .white
            )
            statCard(
                title: "内存",
                icon: "memorychip",
                value: String(format: "%.1f GB", stats.memoryUsedGB),
                history: stats.memoryHistory,
                color: .cyan
            )
            statCard(
                title: "网络",
                icon: stats.networkDown > 0.05 ? "arrow.down.right" : "arrow.right",
                value: String(format: "↓ %.1f MB/s", stats.networkDown),
                history: stats.networkHistory,
                color: .mint
            )
            statCard(
                title: "磁盘",
                icon: "internaldrive",
                value: String(format: "%.0f GB", stats.diskUsedGB),
                history: nil,
                color: .orange
            )
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func statCard(title: String, icon: String, value: String, history: [Double]?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            if let history {
                Sparkline(values: history, color: color)
                    .frame(height: 26)
            } else {
                ProgressView(value: stats.diskUsage, total: 100)
                    .tint(color)
                    .scaleEffect(y: 1.4)
                    .frame(height: 26)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 简单折线 sparkline
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let paths = Self.buildPaths(values: values, size: geo.size)
            ZStack {
                paths.fill.fill(
                    LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                paths.line.stroke(
                    color.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// 由历史数据生成填充与折线路径（普通函数，避免进 ViewBuilder 上下文）
    private static func buildPaths(values: [Double], size: CGSize) -> (fill: Path, line: Path) {
        let w = size.width
        let h = size.height
        let maxV = max(1, values.max() ?? 1)
        let points: [CGPoint] = values.enumerated().map { i, v in
            let x = values.count > 1 ? CGFloat(i) / CGFloat(values.count - 1) * w : w
            let y = h - CGFloat(v / maxV) * h
            return CGPoint(x: x, y: y)
        }

        var fillPath = Path()
        var linePath = Path()
        if let first = points.first {
            fillPath.move(to: CGPoint(x: first.x, y: h))
            for p in points { fillPath.addLine(to: p) }
            fillPath.addLine(to: CGPoint(x: points.last?.x ?? w, y: h))
            fillPath.closeSubpath()
            linePath.move(to: first)
            for pt in points.dropFirst() { linePath.addLine(to: pt) }
        }
        return (fillPath, linePath)
    }
}

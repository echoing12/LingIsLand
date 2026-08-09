import SwiftUI

/// 幽灵绘制的常量（64×64 逻辑画布，父视图负责 scaleEffect 缩放）
enum GhostMetrics {
    static let canvas: CGFloat = 64

    static let bodyTop = Color(red: 1.00, green: 0.99, blue: 1.00)        // 头顶白
    static let bodyBottom = Color(red: 0.80, green: 0.85, blue: 0.98)     // 底部淡蓝紫
    static let arm = Color(red: 0.90, green: 0.93, blue: 1.00)            // 手臂
    static let dark = Color(red: 0.22, green: 0.26, blue: 0.44)           // 眼/嘴（柔和深蓝紫）
    static let blush = Color(red: 1.00, green: 0.63, blue: 0.72)          // 腮红（也当舌头）
    static let sparkle = Color(red: 1.00, green: 0.86, blue: 0.45)        // 星星金色

    static let skirtWaveAmplitude: CGFloat = 3                            // 裙摆起伏幅度
}

/// 矢量小幽灵：心情 + 姿态驱动所有参数化动画，点击会卖萌互动
struct GhostView: View {
    @ObservedObject var moodManager: PetMoodManager

    @State private var isBlinking = false
    @State private var breathPhase = false
    @State private var floatPhase = false
    @State private var swayPhase = false
    @State private var skirtPhase = false
    @State private var armPhase = false
    @State private var jumpPulse: CGFloat = 0
    @State private var dropOffset: CGFloat = 0      // 开岛「飘下来」的位移
    @State private var previousPose: PetPose = .crouch
    @State private var eyeShift = CGSize.zero       // 眼睛追随光标
    @State private var zzzFloat = false
    // 跳舞
    @State private var danceRock = false            // 快速左右摆
    @State private var danceBob: CGFloat = 0        // 上下颠 0...1
    // 点击互动
    @State private var squish: CGFloat = 0          // 压扁 → 弹起
    @State private var booVisible = false
    @State private var booFloat: CGFloat = -8       // "boo!" 气泡上飘
    @State private var burstActive = false
    @State private var burstDist: CGFloat = 0       // 点击爆出的小星星

    private var mood: PetMood { moodManager.mood }
    private var pose: PetPose { moodManager.pose }
    private var dancing: Bool { moodManager.dancing }

    var body: some View {
        ZStack {
            ghostArtwork
            if mood == .sleepy { zzzOverlay }
        }
        .frame(width: GhostMetrics.canvas, height: GhostMetrics.canvas)
        .scaleEffect(x: xScale, y: yScale, anchor: .bottom)
        .rotationEffect(.degrees(swayAngle), anchor: .bottom)
        .offset(y: floatOffset + dropOffset + jumpPulse * -9 + danceBobOffset)
        .onAppear {
            startLoopAnimations()
        }
        // 无限循环动画统一用 .task 托管：视图消失自动取消，避免重新出现时任务重复堆积
        .task { await runBlinkLoop() }
        .task { await runSkirtLoop() }
        .task { await runArmLoop() }
        .task { await runMouseTracking() }
        .onChange(of: mood) { _, newMood in
            if newMood == .excited, previousPose == .sit {
                // 已坐姿时的兴奋小跳（切歌等）；开岛带来的 excited 由 performDrop 负责
                triggerJump()
            }
            if newMood == .sleepy {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    zzzFloat = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { zzzFloat = false }
            }
        }
        .onChange(of: pose) { oldPose, newPose in
            previousPose = oldPose
            if newPose == .sit {
                performDrop()   // 开岛：从岛上飘下来落到专属道
            } else {
                triggerJump()   // 闭岛：轻跳一下回到岛上
            }
        }
        .onChange(of: moodManager.dancing) { _, dancing in
            if dancing {
                startDance()
            } else {
                stopDance()
            }
        }
        .gesture(
            TapGesture(count: 2)
                .onEnded { moodManager.trigger(.petDoubleTapped) }
                .exclusively(before: TapGesture().onEnded { reactToTap() })
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mood)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pose)
    }

    // MARK: - 点击互动

    /// 被戳一下：压扁 → 弹起 → 冒 "boo!" 气泡 + 爆星星，心情变顽皮
    private func reactToTap() {
        moodManager.trigger(.petTapped)

        withAnimation(.spring(response: 0.10, dampingFraction: 0.85)) { squish = 1 }
        Task {
            try? await Task.sleep(for: .seconds(0.10))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.42)) { squish = 0 }

            booVisible = true
            withAnimation(.spring(response: 0.30, dampingFraction: 0.65)) { booFloat = -26 }
            burstActive = true
            withAnimation(.easeOut(duration: 0.5)) { burstDist = 22 }

            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.25)) {
                booVisible = false
                booFloat = -8
            }
            burstActive = false
            burstDist = 0
        }
    }

    // MARK: - 光标追踪

    /// 轮询鼠标位置，眼睛微微朝光标方向转（犯困/开心/顽皮时除外）。
    /// 不用 NSEvent.addGlobalMonitorForEvents：macOS 26 上全局鼠标事件投递失效
    /// （见 DragDetector 注释），且该 API 还需额外「输入监听」权限。轮询 NSEvent.mouseLocation
    /// 不依赖事件投递、零权限，实测可用。50ms 一轮，值不变时不触发重绘。
    private func runMouseTracking() async {
        while !Task.isCancelled {
            pollMousePosition()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func pollMousePosition() {
        guard let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let dx = (mouse.x - screen.frame.midX) / (screen.frame.width / 2)
        let dy = (mouse.y - screen.frame.midY) / (screen.frame.height / 2)
        let newShift = CGSize(
            width: CGFloat(max(-0.4, min(0.4, dx))) * 2.4,
            height: CGFloat(max(-0.4, min(0.4, dy))) * 2.4
        )
        if newShift != eyeShift { eyeShift = newShift }
    }

    /// 犯困时头顶飘的 z z Z
    private var zzzOverlay: some View {
        HStack(spacing: 1) {
            Text("z").font(.system(size: 6, weight: .bold)).opacity(0.4)
            Text("z").font(.system(size: 8, weight: .bold)).opacity(0.65)
            Text("Z").font(.system(size: 11, weight: .bold)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .offset(x: 20, y: zzzFloat ? -24 : -14)
        .opacity(zzzFloat ? 0.35 : 1.0)
        .transition(.opacity)
        .zIndex(20)
    }

    // MARK: - 比例

    private var poseScale: CGFloat { pose == .crouch ? 0.85 : 1.0 }
    private var breathScale: CGFloat { breathPhase ? 1.02 : 1.0 }
    private var xScale: CGFloat {
        let base = poseScale * (1 - squish * 0.15)
        return dancing ? base * (1 + danceBob * 0.05) : base
    }
    private var yScale: CGFloat {
        let base = poseScale * breathScale * (1 - squish * 0.35)
        return dancing ? base * (1 - danceBob * 0.06) : base
    }

    /// 跳舞上下颠：danceBob 0...1 → -2.5...2.5
    private var danceBobOffset: CGFloat { (danceBob * 2 - 1) * 2.5 }

    /// 漂浮位移：开岛时幅度更大更灵动（跳舞时收小，让颠的节奏主导）
    private var floatAmp: CGFloat { dancing ? 1.0 : (pose == .sit ? 3.5 : 2.0) }
    private var floatOffset: CGFloat { floatPhase ? floatAmp : -floatAmp }

    /// 裙摆起伏：相位取 ±1，配合 skirtWaveAmplitude 控制起伏深度
    private var skirtWave: CGFloat { skirtPhase ? 1 : -1 }

    /// 左右摇摆：开岛更活泼
    private var swayAmp: Double { pose == .sit ? 4.5 : 2.5 }
    private var swayAngle: Double {
        if dancing { return danceRock ? 16 : -16 }
        let amp = mood == .sleepy ? swayAmp * 0.4 : swayAmp
        return swayPhase ? amp : -amp
    }

    // MARK: - 幽灵本体

    private var ghostArtwork: some View {
        ZStack {
            glow
            arms
            bodyShape
            faceGroup
            sparkleLayer
            if dancing { danceNotes }
            booBubble
            burstLayer
        }
    }

    /// 背后柔光晕（开岛时更亮）
    private var glow: some View {
        Circle()
            .fill(RadialGradient(
                colors: [.white.opacity(pose == .sit ? 0.32 : 0.18), .clear],
                center: .center, startRadius: 1, endRadius: 30))
            .frame(width: 60, height: 60)
            .offset(y: -2)
    }

    /// 两侧小手臂：挥舞 / 举起 / 垂落
    private var arms: some View {
        ZStack {
            Capsule()
                .fill(GhostMetrics.arm)
                .frame(width: 5, height: 12)
                .rotationEffect(.degrees(armAngle), anchor: .center)
                .offset(x: -21, y: 9)   // 相对画布中心 (32,32) 移到左侧 (11,41)
            Capsule()
                .fill(GhostMetrics.arm)
                .frame(width: 5, height: 12)
                .rotationEffect(.degrees(-armAngle), anchor: .center)
                .offset(x: 21, y: 9)    // 右侧镜像
        }
    }

    private var armAngle: Double {
        if dancing { return danceRock ? 32 : -32 }   // 跳舞：快速挥舞
        switch mood {
        case .happy, .playful: return armPhase ? 30 : -30    // 挥舞
        case .excited: return -52                             // 举起欢呼
        case .sleepy: return 50                               // 垂落
        case .surprised: return 12
        case .curious: return 8
        default: return 5
        }
    }

    /// 身体：圆顶 + 底部波浪裙摆（裙摆随心情变速起伏）
    private var bodyShape: some View {
        Path { p in
            let left: CGFloat = 10
            let right: CGFloat = 54
            let bottom: CGFloat = 52
            p.move(to: CGPoint(x: left, y: bottom))
            p.addQuadCurve(to: CGPoint(x: 25, y: 10), control: CGPoint(x: 5, y: 33))      // 左侧
            p.addQuadCurve(to: CGPoint(x: 39, y: 10), control: CGPoint(x: 32, y: 1))      // 头顶穹顶
            p.addQuadCurve(to: CGPoint(x: right, y: bottom), control: CGPoint(x: 59, y: 33)) // 右侧
            // 底边 4 段波浪裙摆（右 → 左，交替起伏）
            let segs = 4
            let w = (right - left) / CGFloat(segs)
            for i in 0..<segs {
                let x0 = right - w * CGFloat(i)
                let x1 = right - w * CGFloat(i + 1)
                let flip: CGFloat = i % 2 == 0 ? 1 : -1
                let depth = GhostMetrics.skirtWaveAmplitude * skirtWave * flip
                p.addQuadCurve(to: CGPoint(x: x1, y: bottom),
                               control: CGPoint(x: (x0 + x1) / 2, y: bottom + depth))
            }
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: [GhostMetrics.bodyTop, GhostMetrics.bodyBottom],
                             startPoint: .top, endPoint: .bottom))
    }

    /// 头部高光（玻璃感的小月牙）
    private var glare: some View {
        Ellipse()
            .fill(.white.opacity(0.85))
            .frame(width: 8, height: 16)
            .rotationEffect(.degrees(-38))
            .offset(x: -13, y: -6)
            .opacity(0.55)
    }

    private var faceGroup: some View {
        ZStack {
            // 头部高光
            glare
            // 腮红
            Ellipse()
                .fill(GhostMetrics.blush.opacity(0.7))
                .frame(width: 7, height: 4)
                .offset(x: -13, y: 4)
            Ellipse()
                .fill(GhostMetrics.blush.opacity(0.7))
                .frame(width: 7, height: 4)
                .offset(x: 13, y: 4)

            // 眼睛（追光标：犯困/开心/顽皮时不追）
            let shift = (mood == .sleepy || mood == .happy || mood == .playful) ? CGSize.zero : eyeShift
            GhostEye(style: eyeStyle, openAmount: eyeOpen, size: eyeSize)
                .offset(x: -9 + shift.width, y: -3 + shift.height)
            GhostEye(style: eyeStyle, openAmount: eyeOpen, size: eyeSize)
                .offset(x: 9 + shift.width, y: -3 + shift.height)

            // 嘴
            mouth.offset(y: 5)
        }
        .frame(width: GhostMetrics.canvas, height: GhostMetrics.canvas)   // 固定画布，让子元素偏移以 (32,32) 为基准
        .offset(y: -6)   // 画布中心 y=32，回移 6 让脸中心落在 y≈26
        .rotationEffect(.degrees(headTilt))
    }

    private var headTilt: Double {
        switch mood {
        case .curious: return 5
        case .happy: return -2
        default: return 0
        }
    }

    // MARK: - 表情

    private var eyeStyle: GhostEye.Style {
        switch mood {
        case .happy, .playful: return .happy
        case .sleepy: return .sleepy
        case .surprised: return .surprised
        default: return .round
        }
    }

    private var eyeOpen: CGFloat {
        mood == .sleepy ? 0.3 : (isBlinking ? 0.15 : 1.0)
    }

    private var eyeSize: CGFloat {
        switch mood {
        case .surprised: return 6
        case .happy, .playful: return 4.4
        default: return 4.6
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .happy:
            // 张开的开心大嘴
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addQuadCurve(to: CGPoint(x: 10, y: 1), control: CGPoint(x: 5, y: 3.4))
                p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 5, y: 0.6))
            }
            .fill(GhostMetrics.dark)
            .frame(width: 10, height: 3)

        case .playful:
            // 大嘴 + 小舌头（顽皮）
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 1))
                    p.addQuadCurve(to: CGPoint(x: 10, y: 1), control: CGPoint(x: 5, y: 3.4))
                    p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 5, y: 0.6))
                }
                .fill(GhostMetrics.dark)
                .frame(width: 10, height: 3)
                // 舌头：从嘴下缘探出一点
                Ellipse()
                    .fill(GhostMetrics.blush)
                    .frame(width: 3, height: 2.5)
                    .offset(x: 0, y: 1.6)
            }
            .frame(width: 10, height: 6)

        case .excited, .surprised, .sleepy:
            // O 型小嘴
            Ellipse()
                .fill(GhostMetrics.dark)
                .frame(width: 4.5, height: mood == .surprised ? 6 : 5)

        case .curious:
            // 小歪嘴
            Path { p in
                p.move(to: CGPoint(x: 1, y: 2))
                p.addQuadCurve(to: CGPoint(x: 7, y: 2), control: CGPoint(x: 4, y: 3.2))
            }
            .stroke(GhostMetrics.dark, lineWidth: 1.4)
            .frame(width: 8, height: 4)

        default:
            // 微笑
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addQuadCurve(to: CGPoint(x: 7, y: 0), control: CGPoint(x: 3.5, y: 2))
            }
            .stroke(GhostMetrics.dark, lineWidth: 1.4)
            .frame(width: 8, height: 4)
        }
    }

    // MARK: - 点缀：星星 / boo! / 爆发

    @ViewBuilder
    private var sparkleLayer: some View {
        if mood == .happy || mood == .playful || mood == .excited {
            ZStack {
                GhostSparkle(offset: CGSize(width: -23, height: -16), startOn: false)
                GhostSparkle(offset: CGSize(width: 23, height: -18), startOn: true)
                GhostSparkle(offset: CGSize(width: -26, height: 8), startOn: false)
                GhostSparkle(offset: CGSize(width: 26, height: 11), startOn: true)
            }
            .frame(width: GhostMetrics.canvas, height: GhostMetrics.canvas)
            .transition(.opacity)
        }
    }

    /// 点击后冒出的 "boo!" 气泡
    private var booBubble: some View {
        Text("boo!")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
            .offset(x: 26, y: booFloat)
            .opacity(booVisible ? 1 : 0)
            .scaleEffect(booVisible ? 1 : 0.4)
            .zIndex(15)
    }

    /// 点击爆出的星星（向外扩散并淡出）
    @ViewBuilder
    private var burstLayer: some View {
        if burstActive {
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) / 6 * .pi * 2
                    GhostStar()
                        .fill(.white.opacity(0.95))
                        .frame(width: 9, height: 9)
                        .offset(x: CGFloat(cos(angle)) * burstDist,
                                y: CGFloat(sin(angle)) * burstDist - 6)
                        .opacity(burstDist < 3 ? 1 : max(0, 1 - (burstDist - 3) / 19))
                }
            }
            .zIndex(16)
        }
    }

    // MARK: - 跳舞

    /// 开始跳舞：快速左右摆 + 上下颠，复用现有循环管线（sway/arm/skirt 读取跳舞时的速度）
    private func startDance() {
        withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) {
            danceRock = true
        }
        withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true)) {
            danceBob = 1
        }
    }

    private func stopDance() {
        withAnimation(.easeOut(duration: 0.25)) {
            danceRock = false
            danceBob = 0
        }
    }

    /// 跳舞时头顶飘的音符（随上下颠起伏淡出）
    private var danceNotes: some View {
        HStack(spacing: 5) {
            Text("♪").font(.system(size: 8, weight: .bold))
            Text("♫").font(.system(size: 10, weight: .bold))
            Text("♩").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .offset(x: 17, y: -4 + danceBob * -14)
        .opacity(danceBob > 0.9 ? 0.3 : 1)
        .zIndex(18)
    }

    // MARK: - 循环动画

    private func startLoopAnimations() {
        // 呼吸 / 漂浮 / 摇摆：固定周期的持续循环（SwiftUI 托管，视图消失自动回收）
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            breathPhase = true
        }
        withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
            floatPhase = true
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            swayPhase = true
        }
        // 眨眼 / 裙摆 / 手臂循环由 .task 托管（见 body），视图消失自动取消
    }

    /// 眨眼循环：3~6 秒随机眨一次
    private func runBlinkLoop() async {
        while !Task.isCancelled {
            let delay = Double.random(in: 2.5...5.5)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.1)) { isBlinking = true }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) { isBlinking = false }
        }
    }

    /// 裙摆起伏循环：每轮读取当前心情定速
    private func runSkirtLoop() async {
        while !Task.isCancelled {
            let duration = skirtDuration
            withAnimation(.easeInOut(duration: duration)) { skirtPhase.toggle() }
            try? await Task.sleep(for: .seconds(duration))
        }
    }

    /// 手臂挥舞循环：每轮读取当前心情定速
    private func runArmLoop() async {
        while !Task.isCancelled {
            let duration = armDuration
            withAnimation(.easeInOut(duration: duration)) { armPhase.toggle() }
            try? await Task.sleep(for: .seconds(duration))
        }
    }

    private var skirtDuration: Double {
        if dancing { return 0.10 }   // 跳舞：裙摆快速甩动
        switch mood {
        case .happy, .playful: return 0.30
        case .excited: return 0.20
        case .sleepy: return 1.2
        default: return 0.55
        }
    }

    private var armDuration: Double {
        if dancing { return 0.10 }   // 跳舞：手臂快速挥舞
        switch mood {
        case .happy, .playful, .excited: return 0.20
        case .sleepy: return 1.4
        default: return 0.5
        }
    }

    private func triggerJump() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
            jumpPulse = 1
        }
        Task {
            try? await Task.sleep(for: .seconds(0.30))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                jumpPulse = 0
            }
        }
    }

    /// 开岛「飘下来」：先蓄力微微上抬，再缓缓下坠落到专属道，落地弹一下
    private func performDrop() {
        withAnimation(.easeOut(duration: 0.10)) { dropOffset = -8 }
        Task {
            try? await Task.sleep(for: .seconds(0.10))
            withAnimation(.spring(response: 0.30, dampingFraction: 0.38)) { dropOffset = 22 }
            try? await Task.sleep(for: .seconds(0.38))
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) { dropOffset = 0 }
        }
    }
}

// MARK: - 幽灵眼睛

struct GhostEye: View {
    enum Style {
        case round
        case happy
        case sleepy
        case surprised
    }

    let style: Style
    let openAmount: CGFloat   // 0...1 眨眼
    let size: CGFloat

    var body: some View {
        switch style {
        case .round, .surprised:
            ZStack {
                Ellipse()
                    .fill(GhostMetrics.dark)
                    .frame(width: size, height: max(1.2, size * 1.3 * openAmount))
                if style == .surprised {
                    Circle()
                        .fill(.white)
                        .frame(width: 1.8, height: 1.8)
                        .offset(x: size * 0.28, y: -size * 0.28)
                } else {
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 1.5, height: 1.5)
                        .offset(x: size * 0.24, y: -size * 0.24)
                }
            }

        case .happy:
            // ^^ 笑眯眯的眼睛
            GhostEyeArc(curveUp: true)
                .stroke(GhostMetrics.dark, lineWidth: 1.6)
                .frame(width: size * 2, height: size)

        case .sleepy:
            // 向下垂的弧 = 犯困
            GhostEyeArc(curveUp: false)
                .stroke(GhostMetrics.dark, lineWidth: 1.6)
                .frame(width: size * 2, height: size)
        }
    }
}

/// 眼睛弧线（用 Shape 而非裸 Path：以 frame 为坐标空间，天然居中，不会像 Path 那样跑到 frame 左侧）
struct GhostEyeArc: Shape {
    let curveUp: Bool   // true: 上凸 ^^（开心）；false: 下凹 ∪（犯困）

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let half = rect.width * 0.44
        if curveUp {
            // 端点在下方两侧，弧顶在上
            let endY = rect.midY + rect.height * 0.28
            let apexY = rect.midY - rect.height * 0.28
            p.move(to: CGPoint(x: rect.midX - half, y: endY))
            p.addQuadCurve(to: CGPoint(x: rect.midX + half, y: endY),
                           control: CGPoint(x: rect.midX, y: apexY))
        } else {
            // 端点在中线，弧底在下垂
            let endY = rect.midY
            let apexY = rect.midY + rect.height * 0.38
            p.move(to: CGPoint(x: rect.midX - half, y: endY))
            p.addQuadCurve(to: CGPoint(x: rect.midX + half, y: endY),
                           control: CGPoint(x: rect.midX, y: apexY))
        }
        return p
    }
}

// MARK: - 四角小星星

struct GhostStar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.35
        for i in 0..<8 {
            let radius = i % 2 == 0 ? outer : inner
            let a = CGFloat(i) * .pi / 4 - .pi / 2
            let pt = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

/// 环绕幽灵飘动的小星星（各自错开相位闪烁）
struct GhostSparkle: View {
    @State private var on: Bool
    let offset: CGSize

    init(offset: CGSize, startOn: Bool) {
        self.offset = offset
        _on = State(initialValue: startOn)
    }

    var body: some View {
        GhostStar()
            .fill(GhostMetrics.sparkle.opacity(0.95))
            .frame(width: 7, height: 7)
            .offset(offset)
            .scaleEffect(on ? 1.1 : 0.25)
            .opacity(on ? 0.95 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.3)
        HStack(spacing: 30) {
            GhostView(moodManager: PetMoodManager.shared)
            GhostView(moodManager: {
                let m = PetMoodManager.shared
                m.trigger(.mediaPlaying(true))
                return m
            }())
        }
        .frame(width: 200, height: 120)
    }
}

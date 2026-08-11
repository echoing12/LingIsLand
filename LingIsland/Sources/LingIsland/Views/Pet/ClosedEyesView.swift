import AppKit
import SwiftUI

/// 闭岛时的「眼睛形态」：黑色胶囊里只剩两只圆眼睛，一只在胶囊左端、一只在右端。
/// 白眼球 + 深色瞳孔，瞳孔各自朝鼠标方向转，间歇眨眼。
/// 平时是圆眼睛；犯困耷拉、惊讶瞪圆、开心/顽皮眯成 ^^ 等心情偶尔接管。
struct ClosedEyesView: View {
    @ObservedObject var moodManager: PetMoodManager
    let capsuleSize: CGSize

    @State private var isBlinking = false
    @State private var pupilLeft = CGSize.zero
    @State private var pupilRight = CGSize.zero

    private enum EyeStyle {
        case round        // 白眼球 + 深色瞳孔，追光标
        case surprised    // 瞪圆：更大的眼白 + 小瞳孔
        case sleepy       // 半垂眼帘：只露下半眼白
        case happy        // 眯成 ^^ 白弧
    }

    /// 眼睛直径随闭岛胶囊高度缩放：闭岛被压矮时眼睛同步变小，始终和「深槽」成比例，
    /// 不会顶满胶囊或被圆角裁剪。上限 20 保持当前观感（闭岛胶囊 ~50-53 高时正好封顶）。
    private var eyeDiameter: CGFloat {
        min(capsuleSize.height * Self.eyeScaleRatio, Self.eyeDiameterMax)
    }
    /// 眼睛离胶囊两端的边距：固定值即可，胶囊越矮圆角（= 高/2）越小，26 始终够避开圆角
    private let eyeInset: CGFloat = 26

    private static let eyeScaleRatio: CGFloat = 0.4
    private static let eyeDiameterMax: CGFloat = 20

    private var mood: PetMood { moodManager.mood }

    private var eyeStyle: EyeStyle {
        switch mood {
        case .happy, .playful: return .happy
        case .sleepy: return .sleepy
        case .surprised: return .surprised
        default: return .round
        }
    }

    var body: some View {
        ZStack {
            eye(at: leftEyePosition, style: eyeStyle, pupil: pupilLeft)
            eye(at: rightEyePosition, style: eyeStyle, pupil: pupilRight)
        }
        .frame(width: capsuleSize.width, height: capsuleSize.height)
        .task { await runBlinkLoop() }
        .task { await runTrackingLoop() }
        .onTapGesture { moodManager.trigger(.petTapped) }
    }

    // MARK: - 布局

    private var leftEyePosition: CGPoint {
        CGPoint(x: eyeInset + eyeDiameter / 2, y: capsuleSize.height / 2)
    }
    private var rightEyePosition: CGPoint {
        CGPoint(x: capsuleSize.width - eyeInset - eyeDiameter / 2, y: capsuleSize.height / 2)
    }

    // MARK: - 光标追踪

    private func runTrackingLoop() async {
        while !Task.isCancelled {
            pollMouse()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 轮询鼠标，让两只眼睛的瞳孔各自朝光标方向偏移。
    /// 与 GhostView 同思路：NSEvent.mouseLocation 轮询，零权限、macOS 26 可用。
    /// 非圆眼（眯眼/耷拉）时瞳孔归位。
    private func pollMouse() {
        guard eyeStyle == .round, let screen = NSScreen.main else {
            if pupilLeft != .zero { pupilLeft = .zero }
            if pupilRight != .zero { pupilRight = .zero }
            return
        }
        let mouse = NSEvent.mouseLocation
        let newL = pupilOffset(from: leftScreenPosition(on: screen), to: mouse)
        let newR = pupilOffset(from: rightScreenPosition(on: screen), to: mouse)
        if newL != pupilLeft { pupilLeft = newL }
        if newR != pupilRight { pupilRight = newR }
    }

    /// 胶囊横向居中于屏幕、纵向顶住屏幕顶部，据此推算眼睛的屏幕坐标
    private func leftScreenPosition(on screen: NSScreen) -> CGPoint {
        CGPoint(
            x: screen.frame.midX - capsuleSize.width / 2 + eyeInset + eyeDiameter / 2,
            y: screen.frame.maxY - capsuleSize.height / 2
        )
    }
    private func rightScreenPosition(on screen: NSScreen) -> CGPoint {
        CGPoint(
            x: screen.frame.midX + capsuleSize.width / 2 - eyeInset - eyeDiameter / 2,
            y: screen.frame.maxY - capsuleSize.height / 2
        )
    }

    /// 瞳孔偏移：朝向光标方向；鼠标越远偏移越大（封顶），很近时收敛以免瞳孔飞出眼白。
    /// maxOffset 控制在 0.22×直径，保证瞳孔始终滑在白眼球内、不戳出来。
    /// 注意：屏幕坐标 y 向上、SwiftUI offset y 向下为正，y 方向要取反，否则瞳孔会朝鼠标反方向看。
    private func pupilOffset(from eye: CGPoint, to mouse: CGPoint) -> CGSize {
        let dx = mouse.x - eye.x
        let dy = mouse.y - eye.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0.5 else { return .zero }
        let maxOffset = eyeDiameter * 0.22
        let scale = min(1.0, dist / 200)
        return CGSize(
            width: (dx / dist) * maxOffset * scale,
            height: (-dy / dist) * maxOffset * scale
        )
    }

    // MARK: - 眨眼

    /// 间歇眨眼：2.5~5.5s 随机眨一次（眯眼/耷拉形态本身不带 blink 效果，不影响）
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

    // MARK: - 眼睛绘制

    @ViewBuilder
    private func eye(at position: CGPoint, style: EyeStyle, pupil: CGSize) -> some View {
        eyeShape(style: style, pupil: pupil)
            .position(position)
            .animation(.easeInOut(duration: 0.15), value: isBlinking)
    }

    @ViewBuilder
    private func eyeShape(style: EyeStyle, pupil: CGSize) -> some View {
        switch style {
        case .round, .surprised: roundEye(style: style, pupil: pupil)
        case .sleepy: sleepyEye
        case .happy: happyEye
        }
    }

    /// 圆眼 / 惊讶：白眼球 + 深色瞳孔，眨眼把眼睛压扁
    @ViewBuilder
    private func roundEye(style: EyeStyle, pupil: CGSize) -> some View {
        let d = style == .surprised ? eyeDiameter * 1.35 : eyeDiameter
        ZStack {
            Ellipse()
                .fill(.white)
                .frame(width: d, height: d)
            Circle()
                .fill(GhostMetrics.dark)
                .frame(width: d * 0.5, height: d * 0.5)
                .offset(style == .surprised ? .zero : pupil)
            // 瞳孔高光
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: d * 0.13, height: d * 0.13)
                .offset(style == .surprised
                    ? CGSize(width: d * 0.14, height: -d * 0.14)
                    : CGSize(width: pupil.width + d * 0.14, height: pupil.height - d * 0.14))
        }
        .scaleEffect(x: 1, y: isBlinking ? 0.12 : 1, anchor: .center)
        .animation(.easeOut(duration: 0.06), value: pupil)
    }

    /// 犯困：眼帘半垂，只露下半眼白 + 耷拉瞳孔
    private var sleepyEye: some View {
        ZStack {
            Ellipse()
                .fill(.white)
                .frame(width: eyeDiameter, height: eyeDiameter * 0.55)
                .offset(y: eyeDiameter * 0.22)
            Ellipse()
                .fill(GhostMetrics.dark)
                .frame(width: eyeDiameter * 0.38, height: eyeDiameter * 0.26)
                .offset(y: eyeDiameter * 0.26)
        }
    }

    /// 开心/顽皮：眯成 ^^ 白弧（黑色胶囊上清晰可见）
    private var happyEye: some View {
        GhostEyeArc(curveUp: true)
            .stroke(.white, lineWidth: 2.2)
            .frame(width: eyeDiameter * 1.4, height: eyeDiameter * 0.6)
    }
}

#Preview {
    ZStack {
        Color.black
        ClosedEyesView(
            moodManager: PetMoodManager.shared,
            capsuleSize: CGSize(width: 280, height: 50)
        )
    }
    .frame(width: 300, height: 100)
}

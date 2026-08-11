import SwiftUI

/// 主视图：黑色胶囊（刘海）+ 幽灵定位 + 悬停/点击交互
struct IslandView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var pet: PetMoodManager
    @EnvironmentObject var hud: HUDManager
    @EnvironmentObject var notifications: NotificationManager

    @AppStorage(AppSettings.showPet) private var showPet = true
    @AppStorage(AppSettings.hoverToOpen) private var hoverToOpen = true

    @State private var hoverTask: Task<Void, Never>?
    @State private var dragTargeting = false

    private let spring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private var isOpen: Bool { vm.islandState == .open }

    // MARK: - 尺寸

    private var capsuleWidth: CGFloat {
        // 闭岛：黑色胶囊 = 刘海 + 两侧延伸，把幽灵包含在内
        isOpen ? NotchGeometry.openWidth : vm.closedSize.width + NotchGeometry.petClosedOverhang * 2
    }
    private var capsuleHeight: CGFloat {
        isOpen ? NotchGeometry.openHeight : vm.closedSize.height + NotchGeometry.closedExtraHeight
    }
    private var topRadius: CGFloat {
        // 闭岛 = 黑色胶囊：两端圆角 = 高度一半，塞进幽灵也保持胶囊外形
        isOpen ? NotchGeometry.openTopRadius : capsuleHeight / 2
    }
    private var bottomRadius: CGFloat {
        isOpen ? NotchGeometry.openBottomRadius : capsuleHeight / 2
    }

    var body: some View {
        ZStack(alignment: .top) {
            capsule
            petSpeechLayer
            hudLayer
            notificationLayer
        }
        .frame(width: NotchGeometry.windowWidth, height: NotchGeometry.windowHeight, alignment: .top)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .data], isTargeted: $dragTargeting) { providers in
            if !isOpen {
                vm.open()
                vm.switchTab(.shelf)
            }
            return ShelfManager.shared.handleDrop(providers)
        }
        .onChange(of: dragTargeting) { _, targeting in
            // 拖文件靠近顶部（窗口区域）→ 自动开岛到文件 tab
            if targeting {
                vm.open()
                vm.switchTab(.shelf)
            }
        }
    }

    // MARK: - 胶囊

    private var capsule: some View {
        ZStack {
            Rectangle().fill(.black)
            if isOpen {
                // 开岛：顶部 tab 条 + 下方「幽灵专属区 | 功能区」（都挤在黑色内部）
                VStack(spacing: 0) {
                    headerBar
                        .frame(height: NotchGeometry.openHeaderHeight)
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: NotchGeometry.petZoneWidth)
                        tabContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, NotchGeometry.panelPadding)
                    .padding(.bottom, NotchGeometry.panelPadding)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
            // 幽灵：始终在黑色胶囊/面板内部（被裁剪进胶囊形状，不脱离黑色部位）
            if showPet { petLayer }
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .clipShape(NotchRoundedShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .shadow(color: isOpen ? .black.opacity(0.6) : .clear, radius: 12)
        .animation(spring, value: vm.islandState)
        .onHover(perform: handleHover)
        .onTapGesture { toggle() }
    }

    /// 顶部条：闭岛时空白（纯黑），开岛时显示 tab + 关闭按钮
    @ViewBuilder
    private var headerBar: some View {
        if isOpen {
            HStack(spacing: 6) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
                Spacer()
                Button {
                    vm.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .onHover { _ in }
            }
            .padding(.horizontal, 14)
        }
    }

    private func tabButton(_ tab: IslandTab) -> some View {
        let selected = vm.currentTab == tab
        return Button {
            withAnimation(.smooth(duration: 0.2)) { vm.switchTab(tab) }
        } label: {
            Text(tab.rawValue)
                .font(.caption2.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? .white.opacity(0.18) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        // 内边距由胶囊里的 HStack 统一控制（panelPadding）
        Group {
            switch vm.currentTab {
            case .media: MediaPlayerView()
            case .stats: StatsView()
            case .shelf: ShelfView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - HUD 浮层

    @ViewBuilder
    private var hudLayer: some View {
        if let item = hud.current {
            HUDView(item: item)
                .position(hudPosition)
                .animation(spring, value: vm.islandState)
                .allowsHitTesting(false)
                .zIndex(20)
        }
    }

    private var hudPosition: CGPoint {
        let midX = NotchGeometry.windowWidth / 2
        // 胶囊底边 y 直接复用 capsuleHeight：闭岛高度公式只在一处维护，改高度时 HUD 自动跟随
        let capsuleBottom = capsuleHeight
        return CGPoint(
            x: midX,
            y: capsuleBottom + NotchGeometry.hudGap + 20   // 20 = HUD 胶囊半高
        )
    }

    // MARK: - 通知层

    @ViewBuilder
    private var notificationLayer: some View {
        if isOpen, let notification = notifications.current {
            NotificationToastView(notification: notification)
                .position(
                    x: NotchGeometry.windowWidth / 2,
                    y: NotchGeometry.openHeaderHeight + 8 + 22   // header 下方，22 ≈ toast 半高
                )
                .allowsHitTesting(false)
                .zIndex(30)
        }
    }

    // MARK: - 幽灵

    private var petLayer: some View {
        ZStack {
            // 开岛：完整幽灵（左侧专属区，可点击互动）
            if isOpen {
                GhostView(moodManager: pet)
                    .frame(width: GhostMetrics.canvas, height: GhostMetrics.canvas)
                    .scaleEffect(petScale)
                    .position(petPosition)
            } else {
                // 闭岛：黑色胶囊里只有两只圆眼睛（白眼球+瞳孔，各自看鼠标、间歇眨眼），不再有幽灵
                ClosedEyesView(
                    moodManager: pet,
                    capsuleSize: CGSize(width: capsuleWidth, height: capsuleHeight)
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isOpen)
    }

    /// 气泡（窗口坐标系）：胶囊上方是顶部 tab 条，气泡放在胶囊下方、不随胶囊被裁剪。
    /// 只在开岛时说话 —— 闭岛只剩眼睛，不冒台词。
    @ViewBuilder
    private var petSpeechLayer: some View {
        if isOpen, showPet, let speech = pet.speech {
            PetSpeechBubble(text: speech)
                .position(windowSpeechPosition)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                .allowsHitTesting(false)
                .zIndex(25)
        }
    }

    /// 气泡位置（窗口坐标系）：胶囊水平居中于窗口，把胶囊内参考点换算到窗口坐标
    private var windowSpeechPosition: CGPoint {
        let capsuleOriginX = (NotchGeometry.windowWidth - capsuleWidth) / 2
        let p = capsuleSpeechPosition
        return CGPoint(
            x: capsuleOriginX + p.x,
            y: min(p.y, NotchGeometry.windowHeight - 24)
        )
    }

    /// 气泡在胶囊内部的参考位置：开岛在幽灵下方；闭岛在胶囊正下方居中
    private var capsuleSpeechPosition: CGPoint {
        if isOpen {
            let petHalf = NotchGeometry.petSizeOpen / 2
            return CGPoint(x: petPosition.x, y: petPosition.y + petHalf + 12)
        } else {
            return CGPoint(x: capsuleWidth / 2, y: capsuleHeight + 12)
        }
    }

    private var petScale: CGFloat {
        NotchGeometry.petSizeOpen / GhostMetrics.canvas
    }

    /// 幽灵在开岛面板内部的位置（胶囊坐标系，0,0 = 胶囊左上角）
    private var petPosition: CGPoint {
        // 水平保持在左侧专属区，垂直相对原底部对齐往上挪
        CGPoint(
            x: NotchGeometry.panelPadding + NotchGeometry.petZoneWidth / 2,
            y: NotchGeometry.openHeight - NotchGeometry.panelPadding - NotchGeometry.petSizeOpen / 2 - 30
        )
    }

    // MARK: - 交互

    private func toggle() {
        if isOpen { vm.close() } else { vm.open() }
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            guard hoverToOpen else { return }
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(NotchGeometry.hoverOpenDelay))
                guard !Task.isCancelled else { return }
                if !isOpen { vm.open() }
            }
        } else {
            // 拖拽文件期间 / 刚完成暂存时，抑制悬停自动关闭
            guard !vm.suppressAutoClose else { return }
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(NotchGeometry.hoverCloseDelay))
                guard !Task.isCancelled else { return }
                if isOpen { vm.close() }
            }
        }
    }
}

/// 上小下大的圆角胶囊形状（参考 boring.notch 的 NotchShape）
struct NotchRoundedShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// 让圆角参与开/关岛的弹簧动画，避免 frame 在动而圆角瞬间跳变
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // 左上
        path.move(to: CGPoint(x: 0, y: topRadius))
        path.addQuadCurve(to: CGPoint(x: topRadius, y: 0), control: CGPoint(x: 0, y: 0))
        // 右上
        path.addLine(to: CGPoint(x: w - topRadius, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: topRadius), control: CGPoint(x: w, y: 0))
        // 右下
        path.addLine(to: CGPoint(x: w, y: h - bottomRadius))
        path.addQuadCurve(to: CGPoint(x: w - bottomRadius, y: h), control: CGPoint(x: w, y: h))
        // 左下
        path.addLine(to: CGPoint(x: bottomRadius, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - bottomRadius), control: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

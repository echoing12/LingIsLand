import Foundation

/// 幽灵的心情状态
enum PetMood: String {
    case idle       // 待机：漂浮起伏 + 眨眼 + 裙摆慢摇
    case happy      // 开心：^^眼 + 挥手 + 星星（媒体播放中）
    case curious    // 好奇：歪头（文件拖入/悬停）
    case excited    // 兴奋：弹跳 + 手臂举起（岛展开/切歌）
    case sleepy     // 犯困：垂眼 + zzZ（长时间无操作/深夜）
    case surprised  // 惊讶：瞪眼（音量突增/新通知）
    case playful    // 顽皮：点击互动后的大笑脸 + 舌头 + 星星
}

/// 幽灵姿态
enum PetPose {
    case crouch    // 收拢 —— 闭岛时缩在黑色胶囊内左侧
    case sit       // 漂浮 —— 开岛时漂在面板左侧专属区
}

/// 触发心情变化的事件
enum PetEvent {
    case islandOpened
    case islandClosed
    case mediaPlaying(Bool)
    case trackChanged
    case volumeChanged(magnitude: Float)
    case brightnessChanged(magnitude: Float)
    case fileDropped
    case notificationReceived
    case petTapped
    case petDoubleTapped
    case idleTick(secondsIdle: TimeInterval)
}

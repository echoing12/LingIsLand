import SwiftUI

/// 小幽灵的台词库：按场景分组的中文短语，需要加台词就加在这里
enum PetSpeech {
    static let greeting = ["嗨！", "你好呀~", "我在呢！", "今天也来啦？"]
    static let farewell = ["拜拜~", "回来找我哦", "我等你~"]
    static let playing = ["好听的歌！", "🎵 一起听~", "好好听呀"]
    static let track = ["下一首！", "这首我喜欢！", "换歌啦~"]
    static let loud = ["太大声啦！", "吓我一跳！", "轻一点嘛~"]
    static let dropped = ["这是什么呀？", "给我的吗？", "咦？"]
    static let notice = ["有新消息~", "有人找你！"]
    static let tapped = ["嘻嘻！", "别戳我啦~", "痒痒的！"]
    static let dance = ["跳舞时间！", "看我跳舞！", "♪ 一起来！"]
    static let sleepy = ["好困…", "zzZ…", "想睡了…"]
    static let idleChat = ["今天过得好吗？", "陪着你~", "在干嘛呢？", "嘿嘿"]

    static func random(_ pool: [String]) -> String { pool.randomElement() ?? pool[0] }
}

/// 幽灵说话的气泡（完整字号绘制，不随幽灵缩放）
struct PetSpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            .lineLimit(2)
            .fixedSize()
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.3)
        PetSpeechBubble(text: "你好呀~")
    }
}

import Foundation
import SwiftUI

/// 幽灵心情状态机：接收操作事件 → 切换心情（带衰减计时器回落到 happy/idle）
/// 同时驱动姿态：闭岛=收拢、开岛=漂浮
@MainActor
final class PetMoodManager: ObservableObject {
    static let shared = PetMoodManager()

    @Published var mood: PetMood = .idle
    @Published var pose: PetPose = .crouch
    @Published var speech: String?          // 气泡台词（nil = 不说话）
    @Published var dancing = false          // 跳舞中
    @Published private(set) var isMusicPlaying = false

    private var decayTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var danceTask: Task<Void, Never>?
    private var lastInteractionAt = Date()
    private var lastSpeechAt = Date().addingTimeInterval(-30)

    private init() {
        startIdleTimer()
    }

    // MARK: - 事件入口

    func trigger(_ event: PetEvent) {
        lastInteractionAt = Date()

        switch event {
        case .islandOpened:
            pose = .sit
            setMood(.excited, decayTo: .happy, after: 2.5)
            say(PetSpeech.random(PetSpeech.greeting))

        case .islandClosed:
            pose = .crouch
            setMood(.idle, decayTo: nil, after: 0)
            say(PetSpeech.random(PetSpeech.farewell))

        case .mediaPlaying(true):
            isMusicPlaying = true
            if mood != .excited {
                setMood(.happy, decayTo: .idle, after: 4)
            }
            if shouldSpeak(every: 8) {
                say(PetSpeech.random(PetSpeech.playing))
            }

        case .mediaPlaying(false):
            isMusicPlaying = false
            if mood == .happy {
                setMood(.idle, decayTo: nil, after: 0)
            }

        case .trackChanged:
            setMood(.excited, decayTo: .happy, after: 2)
            say(PetSpeech.random(PetSpeech.track))
            if Int.random(in: 0..<100) < 40 {
                dance(for: 3)
            }

        case .volumeChanged(let magnitude), .brightnessChanged(let magnitude):
            if magnitude > 0.25 {
                setMood(.surprised, decayTo: .happy, after: 1.6)
                if shouldSpeak(every: 2.5) {
                    say(PetSpeech.random(PetSpeech.loud))
                }
            } else if mood == .idle {
                setMood(.curious, decayTo: .idle, after: 2)
            }

        case .fileDropped:
            setMood(.curious, decayTo: .idle, after: 3)
            say(PetSpeech.random(PetSpeech.dropped))

        case .notificationReceived:
            setMood(.curious, decayTo: .idle, after: 3)
            say(PetSpeech.random(PetSpeech.notice))

        case .petTapped:
            setMood(.playful, decayTo: .happy, after: 2.5)
            say(PetSpeech.random(PetSpeech.tapped), duration: 1.6)

        case .petDoubleTapped:
            setMood(.playful, decayTo: .happy, after: 3)
            say(PetSpeech.random(PetSpeech.dance))
            dance(for: 4)

        case .idleTick(let secondsIdle):
            // 深夜 0-6 点或长时间无操作 → 犯困
            let hour = Calendar.current.component(.hour, from: Date())
            if secondsIdle > 75 || hour < 6 {
                if mood != .excited && mood != .surprised && mood != .playful {
                    let wasSleepy = mood == .sleepy
                    setMood(.sleepy, decayTo: nil, after: 0)
                    if !wasSleepy, shouldSpeak(every: 30) {
                        say(PetSpeech.random(PetSpeech.sleepy))
                    }
                }
            } else if mood == .sleepy {
                setMood(.idle, decayTo: nil, after: 0)
            }
            // 待机时的自发闲聊 / 跳舞（让幽灵更像活的）
            spontaneous(idle: secondsIdle)
        }
    }

    // MARK: - 说话 / 跳舞

    /// 说话：弹气泡，duration 秒后自动收掉（新台词会顶掉旧的）
    func say(_ line: String, duration: TimeInterval = 2.4) {
        speechTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { speech = line }
        lastSpeechAt = Date()
        speechTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { self.speech = nil }
        }
    }

    /// 跳舞：置 dancing，duration 秒后结束（重复触发会重新计时）
    func dance(for duration: TimeInterval) {
        danceTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { dancing = true }
        danceTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.dancing = false }
        }
    }

    /// 节流：距上次说话超过 interval 才允许再说（防止音量拖动等高频事件刷屏）
    private func shouldSpeak(every interval: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastSpeechAt) > interval
    }

    /// 待机时的自发行为：随机闲聊 / 心情好时随机跳一段
    private func spontaneous(idle: TimeInterval) {
        if mood == .idle, idle > 8, !dancing, shouldSpeak(every: 25), Int.random(in: 0..<100) < 15 {
            say(PetSpeech.random(PetSpeech.idleChat))
        }
        guard !dancing, mood == .happy || mood == .playful else { return }
        let chance = isMusicPlaying ? 25 : 8
        if Int.random(in: 0..<100) < chance {
            dance(for: 3.5)
        }
    }

    // MARK: - 内部

    private func setMood(_ newMood: PetMood, decayTo: PetMood?, after: TimeInterval) {
        decayTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            mood = newMood
        }
        guard let decayTo else { return }
        decayTask = Task {
            try? await Task.sleep(for: .seconds(after))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                self.mood = decayTo
            }
        }
    }

    private func startIdleTimer() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                let secondsIdle = Date().timeIntervalSince(lastInteractionAt)
                trigger(.idleTick(secondsIdle: secondsIdle))
            }
        }
    }
}

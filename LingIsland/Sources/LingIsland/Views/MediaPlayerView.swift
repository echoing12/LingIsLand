import SwiftUI

/// 媒体控制面板（Phase 2 实现：封面 / 标题 / 进度 / 控制）
struct MediaPlayerView: View {
    @ObservedObject var media = MediaManager.shared
    @EnvironmentObject var pet: PetMoodManager

    var body: some View {
        HStack(spacing: 14) {
            // 封面
            Group {
                if let art = media.albumArt {
                    Image(nsImage: art)
                        .resizable()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.1))
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(media.isPlaying ? media.title : "未在播放")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(media.artist.isEmpty ? "等待 Apple Music / Spotify…" : media.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                // 进度条
                progressBar
            }

            // 控制按钮
            controls
                .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var progressBar: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * media.progress)
                }
            }
            .frame(height: 3)

            HStack {
                Text(formatTime(media.elapsed))
                    .font(.caption2)
                Spacer()
                Text(formatTime(media.duration))
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            controlButton("backward.fill", size: 18) { media.nextOrPrevious(backward: true) }
            controlButton(media.isPlaying ? "pause.fill" : "play.fill", size: 26) {
                media.togglePlayPause()
            }
            controlButton("forward.fill", size: 18) { media.nextOrPrevious(backward: false) }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

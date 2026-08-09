import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 文件暂存区（中转站）：拖入暂存 → 拖出投递/移动，或点 × 移出
struct ShelfView: View {
    @ObservedObject var shelf = ShelfManager.shared

    var body: some View {
        VStack(spacing: 10) {
            if shelf.files.isEmpty {
                Spacer()
                Image(systemName: "tray.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.3))
                Text("把文件拖进来暂存")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                Text("从缩略图拖出即可投递到目标位置")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shelf.files, id: \.url) { file in
                            fileThumb(file)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .data], isTargeted: $shelf.isTargeting) { providers in
            shelf.handleDrop(providers)
        }
    }

    private func fileThumb(_ file: ShelfFile) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: file.icon)
                .resizable()
                .frame(width: 40, height: 40)

            Text(file.url.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .frame(width: 90, height: 74)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        // 拖拽源在最底层，接收整张缩略图的按下/拖动/点击
        .overlay {
            FileThumbDragSource(url: file.url) {
                shelf.remove(file.url)
            }
        }
        // × 移除按钮压在拖拽源之上，避免被其拦截点击
        .overlay(alignment: .topTrailing) {
            Button {
                shelf.remove(file.url)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .help("移出暂存区")
        }
    }
}

/// SwiftUI 侧的拖拽源桥接：把 AppKit 的 FileDragView 叠到缩略图上
private struct FileThumbDragSource: NSViewRepresentable {
    let url: URL
    /// 文件成功投递到别处后回调（用于移出暂存区）
    let onDelivered: () -> Void

    func makeNSView(context: Context) -> FileDragView {
        let view = FileDragView()
        view.url = url
        view.onDelivered = onDelivered
        return view
    }

    func updateNSView(_ nsView: FileDragView, context: Context) {
        nsView.url = url
        nsView.onDelivered = onDelivered
    }
}

/// AppKit 拖拽源：按住缩略图拖出 → 把文件投递到目标位置（Finder 文件夹等），
/// 参照 boring.notch 的 DraggableClickView
final class FileDragView: NSView, NSDraggingSource {
    var url: URL?
    var onDelivered: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private let dragThreshold: CGFloat = 3

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else {
            super.mouseDragged(with: event)
            return
        }
        let distance = hypot(
            event.locationInWindow.x - down.locationInWindow.x,
            event.locationInWindow.y - down.locationInWindow.y
        )
        guard distance > dragThreshold, let url else {
            super.mouseDragged(with: event)
            return
        }
        mouseDownEvent = nil

        // 用 NSURL 作为 pasteboardWriter，正确写入 public.file-url，Finder 可识别
        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        // 普通点击（没拖起来）：在访达中显示该文件
        if mouseDownEvent != nil, let url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        mouseDownEvent = nil
        super.mouseUp(with: event)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]   // 同卷可移动，跨卷或按住 ⌥ 为拷贝
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // 成功投递（copy/move 等）→ 移出暂存区；取消拖拽则保留
        if !operation.isEmpty {
            onDelivered?()
        }
    }
}

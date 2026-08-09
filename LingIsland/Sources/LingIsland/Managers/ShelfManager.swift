import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// 文件暂存区管理器：内存中保存拖入的文件 URL + 图标缩略图
struct ShelfFile: Identifiable {
    let url: URL
    let icon: NSImage
    var id: URL { url }
}

@MainActor
final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()

    @Published var files: [ShelfFile] = []
    @Published var isTargeting = false

    private init() {}

    func add(_ url: URL) {
        guard !files.contains(where: { $0.url == url }) else { return }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        files.append(ShelfFile(url: url, icon: icon))
    }

    func remove(_ url: URL) {
        files.removeAll { $0.url == url }
    }

    func clear() {
        files.removeAll()
    }

    /// 解析 NSItemProvider 里的文件 URL 加入暂存（根视图与 ShelfView 共用）
    @discardableResult
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var loaded = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        self.add(url)
                        PetMoodManager.shared.trigger(.fileDropped)
                    }
                }
            }
            loaded = true
        }
        return loaded
    }
}

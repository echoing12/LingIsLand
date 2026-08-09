import Foundation

/// 设置项 key 常量：@AppStorage 与 UserDefaults 共用同一套，避免字符串散落各处写错
enum AppSettings {
    static let showPet = "settings.showPet"
    static let hoverToOpen = "settings.hoverToOpen"
    static let hudReplacement = "settings.hudReplacement"
}

import Foundation

/// 自绘 HUD 的类型
enum HUDType: String {
    case volume
    case brightness
    case battery

    var iconName: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .battery: return "battery.75percent"
        }
    }
}

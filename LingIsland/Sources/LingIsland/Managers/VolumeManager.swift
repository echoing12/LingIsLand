import AppKit
import Combine
import CoreAudio
import Foundation

/// 音量管理器：CoreAudio 读写系统输出音量并监听变化
@MainActor
final class VolumeManager: ObservableObject {
    static let shared = VolumeManager()

    @Published private(set) var volume: Float = 0.5   // 0...1
    @Published private(set) var isMuted = false

    /// 每级音量增量（参考 boring.notch 的 1/16）
    let step: Float = 1.0 / 16.0

    /// 当前输出设备上的 volume/mute 监听（移除时必须用同一 block 引用，故成对保存）
    private var deviceListeners: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    private init() {
        refresh()
        setupListeners()
    }

    // MARK: - 控制

    func increase() { setRelative(delta: step) }
    func decrease() { setRelative(delta: -step) }

    func setRelative(delta: Float) {
        let current = readVolume() ?? volume
        let target = min(1, max(0, current + delta))
        writeVolume(target)
        publish(volume: target, muted: isMutedNow())
        showHUD(value: target, muted: isMutedNow())
        PetMoodManager.shared.trigger(.volumeChanged(magnitude: abs(delta)))
    }

    func toggleMute() {
        let willMute = !isMutedNow()
        if setMuted(willMute) {
            publish(volume: readVolume() ?? volume, muted: willMute)
            showHUD(value: willMute ? 0 : volume, muted: willMute)
            PetMoodManager.shared.trigger(.volumeChanged(magnitude: 0.5))
        }
    }

    func refresh() {
        publish(volume: readVolume() ?? volume, muted: isMutedNow())
    }

    // MARK: - HUD 展示

    private func showHUD(value: Float, muted: Bool) {
        HUDManager.shared.show(
            .volume,
            value: CGFloat(value),
            icon: muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        )
    }

    private func publish(volume: Float, muted: Bool) {
        self.volume = min(1, max(0, volume))
        self.isMuted = muted
    }

    // MARK: - CoreAudio

    private func systemOutputDeviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private func readVolume() -> Float? {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return nil }
        var values: [Float] = []
        for el in [kAudioObjectPropertyElementMain, UInt32(1), UInt32(2)] {
            if let v = readScalar(deviceID: deviceID, element: el) { values.append(v) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    private func writeVolume(_ value: Float) {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        let clamped = min(1, max(0, value))
        if writeScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: clamped) {
            return
        }
        for el in [UInt32(1), UInt32(2)] {
            _ = writeScalar(deviceID: deviceID, element: el, value: clamped)
        }
    }

    private func readScalar(deviceID: AudioObjectID, element: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size == UInt32(MemoryLayout<Float32>.size) else { return nil }
        var value = Float32(0)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    private func writeScalar(deviceID: AudioObjectID, element: UInt32, value: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        var val = value
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val) == noErr
    }

    private func isMutedNow() -> Bool {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size == UInt32(MemoryLayout<UInt32>.size) else { return false }
        var muted = UInt32(0)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    @discardableResult
    private func setMuted(_ muted: Bool) -> Bool {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        var value = muted ? UInt32(1) : 0
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    // MARK: - 监听

    private func setupListeners() {
        // 默认输出设备变化 → 刷新 + 把 volume/mute 监听重挂到新设备
        var defaultDevAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                let vm = VolumeManager.shared
                vm.refresh()
                vm.resubscribeDeviceListeners()
            }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDevAddr, nil, defaultBlock
        )

        // 音量 / 静音变化（跟随当前默认设备）
        registerDeviceListeners()
    }

    /// 把监听重挂到当前默认输出设备（设备切换后旧设备上的监听随之失效，必须重建）
    private func resubscribeDeviceListeners() {
        registerDeviceListeners()
    }

    private func registerDeviceListeners() {
        // 先摘掉旧设备的监听
        removeDeviceListeners()

        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        var addresses: [AudioObjectPropertyAddress] = []
        for el in [kAudioObjectPropertyElementMain, UInt32(1), UInt32(2)] {
            var a = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: el
            )
            if AudioObjectHasProperty(deviceID, &a) { addresses.append(a) }
        }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) { addresses.append(muteAddr) }

        for var address in addresses {
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                DispatchQueue.main.async { VolumeManager.shared.refresh() }
            }
            AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)
            deviceListeners.append((address, block))
        }
    }

    /// AudioObjectRemovePropertyListenerBlock 需要与注册时相同的 block 引用，按注册时保存的成对数据移除
    private func removeDeviceListeners() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else {
            deviceListeners.removeAll()
            return
        }
        for (var address, block) in deviceListeners {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, block)
        }
        deviceListeners.removeAll()
    }
}

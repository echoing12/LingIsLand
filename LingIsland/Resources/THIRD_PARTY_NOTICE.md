# 第三方组件声明

## MediaRemoteAdapter.framework

- 来源：boring.notch 项目（TheBoredTeam/boring.notch）`mediaremote-adapter/` 目录
- 版权：© 2025 Jonas van den Berg
- 许可：BSD 3-Clause License

MediaRemoteAdapter 是一个把 MediaRemote 私有框架的"现在播放"信息流转换为 JSON
输出的适配层，解决了 macOS 15.4+ 上直接调用 `MRMediaRemoteGetNowPlayingInfo` 失效的兼容问题。

本应用通过 `Sources/MediaRemoteAdapter` 的薄封装调用该 framework 的
`adapter_stream_env` / `adapter_send_env` / `adapter_seek_env` 等导出函数。

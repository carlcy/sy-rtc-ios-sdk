# SY RTC iOS SDK 更新日志

## 1.4.1

### 修复

- **adjustRecordingSignalVolume**：修复公开 API 委托到错误方法（playback 而非 recording）的问题
- **Demo 地址**：SDK 默认信令地址和示例 App 改回 IP 直连（域名备案进行中）

### 升级说明

- CocoaPods：`pod 'SyRtcSDK', '~> 1.4.1'`
- SPM：选择 tag `v1.4.1`

---

## 1.4.0

### 新功能

- **频道消息**：新增 `sendChannelMessage(_ message:)` 方法和 `onChannelMessage(uid:message:)` 回调，支持向频道内所有用户广播自定义消息
- **在线人数修复**：修复后加入的用户收到 `user-list` 时不触发 `onUserJoined` 的问题
- **公开 API 补齐**：`SyRtcEngine` 公开类现在暴露了所有 impl 中的方法，与 Android/Flutter 完全对齐（音频路由、远端音频控制、Token 刷新、音频配置、设备管理、屏幕共享、美颜、音乐混音、音效、音频录制、数据流、旁路推流等）

### 改进

- **Demo 地址**：示例 App 中 API/信令地址改为域名

### 升级说明

- CocoaPods：`pod 'SyRtcSDK', '~> 1.4.0'`
- SPM：选择 tag `v1.4.0`

---

## 1.3.0

### 语音功能修复与稳定性

- **静音**：`muteLocalAudio(_ muted: Bool)` 实际生效，设置 `localAudioTrack?.isEnabled = !muted`。
- **本地音频**：`enableLocalAudio` 同时设置 `localAudioTrack?.isEnabled`，与 Android 行为一致。
- **音频模块**：`enableAudio` / `disableAudio` 同步设置 `localAudioTrack?.isEnabled`，再启停 `audioEngine`。
- **参数校验**：`join(channelId:uid:token:)` 增加 channelId/uid/token 空或仅空白校验，非法时回调 `onError(1000, "channelId/uid/token 不能为空")`。

### 升级说明

- CocoaPods：`pod 'SyRtcSDK', '~> 1.3.0'`
- SPM：选择 tag 1.3.0

---

## 1.2.0

- 版本与 Flutter / Android 统一为 1.2.0；示例与文档更新。

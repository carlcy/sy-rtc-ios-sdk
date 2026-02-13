# SY RTC iOS SDK 更新日志

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

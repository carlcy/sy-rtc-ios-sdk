# SY RTC iOS SDK 更新日志

## 3.3.0

> CocoaPods Trunk 发布时跳过了 `pod trunk push` 的本地校验（它只查 Trunk，而 `LiveKitClient` 只在 LiveKit 自己的 spec 源）；发布前用带 LiveKit 源的空白工程 `pod install` + 模拟器 `xcodebuild` 验证过。

- LiveKit 媒体面：`join` / `renewToken` 除了普通 Token，也接受 `POST /api/server/rtc/token`（`meta=true`）返回的整段 JSON。`mediaWired=true` 且带 `sfuUrl` / `sfuToken` 时，麦克风、摄像头、远端音视频走 LiveKit（LiveKit Swift SDK 2.17，WebRTC 带 `LiveKitWebRTC` 前缀，不与 WebRTC-SDK 冲突），否则仍是 P2P，调用方式不变。新增 `SyJoinCredentials`。
- LiveKit 事件映射：被服务端移出 / 房间删除 / 重复身份 → `onKicked`，信令 kicked 与 LiveKit removed 同时到达时每次进房只回调一次；服务端静音本端 → `onServerMuteAudio(本端uid, true)`（SDK 不自动开麦）；网络质量与音量来自 LiveKit；非踢人断开重连 3 次，原因 `sfu_lost` / `sfu_reconnecting` / `sfu_reconnected`。
- 修：对接 Go 后端时 `onJoinChannelSuccess` 不回调（信令 `joined` / `resumed` 的 `data.peers` 按 `user-list` 处理）。
- **CocoaPods 需要 LiveKit 的 spec 源**：CocoaPods 依赖 `LiveKitClient` `~> 2.15.1`（LiveKit 2.17.0 的 pod 编译失败：`pb.h` 找不到；SPM 仍用 2.17），它不在 Trunk，`Podfile` 顶部加 `source 'https://github.com/livekit/podspecs.git'`（放在 `source 'https://cdn.cocoapods.org/'` 之前）。SPM 不需要。
- 只在 P2P 下可用：屏幕共享、自定义视频源与美颜、数据流、SEI、频道内录音、伴奏混入上行。
- 测试：可选的 LiveKit E2E（`TEST_RUNNER_SFU_META`），不设置时跳过。
- 音频路由：`setAudioRoute(.bluetooth / .headset)` 在设备已连接时可切（首选输入换到 HFP / 耳机麦克风），未连接时回调 `onError(audioRoute)`；新增 `availableAudioRoutes()`；`enumeratePlaybackDevices` / `setPlaybackDevice` 多出 `headset` / `bluetooth`（与 Android 一致）；`onAudioRoutingChanged` 只在路由变化时回调（插拔耳机、蓝牙连断、切扬声器）；`setDefaultAudioRouteToSpeakerphone` 不再丢掉蓝牙选项。
- LiveKit：丢弃 uid 为空的网络质量回调。

## 3.2.2

- 版本对齐发布：Android、iOS、Flutter 统一为 3.2.2。iOS 代码与 3.2.1 相同，仅 `SyRtcSDKVersion.current` / podspec / `VERSION` 改为 3.2.2。

## 3.2.1

- 修复：数据流 / SEI 收不到。`RTCDataChannel.delegate` 是 weak，此前代理创建后立刻释放，iOS 从不回调 `onStreamMessage` / `onSeiMessage`。现在由引擎持有代理，离开频道或对端离开时释放。
- 首次发布到 CocoaPods Trunk。

## 3.2.0

> **已知缺陷，请勿使用 3.2.0（CocoaPods Trunk / tag v3.2.0）：** 数据流 / SEI 收不到（`RTCDataChannel.delegate` 为 weak，代理创建后立即释放）。3.2.1 起修复，请升级到 3.2.2。CocoaPods 不支持按版本 deprecate，因此只在这里说明。

- 网络质量上下行分开（与 Android 相同）：tx = RTT + 上行丢包（remote-inbound-rtp），rx = 本周期下行丢包 + 抖动；新增 `SyRtcLinkQuality` / `SyRtcStatsSample`。修复：下行丢包此前只取最后一路 inbound-rtp、且为通话累计值。
- Token 过期提醒去重：本地定时器与服务端推送（`token-privilege-will-expire` / `token-expired`）每个 Token 只回调一次；按 `data.expireAt` 忽略旧 Token 的迟到推送。新增 `SyRtcTokenExpiryDedupe`。与 Android 相同。
- 本地录音：频道内改为录 WebRTC 管线里的 PCM（本端 APM 采集后处理 + 远端解码）并混音，不再另开 `AVAudioRecorder`（此前通话中只录麦克风、可能被通话抢占）；`AudioRecordingConfiguration` 新增 `includeLocal` / `includeRemote` / `aacBitrate`；`mp3` 等不支持的格式报 `onError(1000)`（此前 mp3 静默输出 PCM）。PeerConnectionFactory 改为显式传入默认 APM；podspec 的 WebRTC-SDK 固定为 125.6422.07（与 SPM、Flutter 一致，.09 改了该 init）。见 README「本地录音」。
- 远端视频 sink 改为常驻：`onVideoSizeChanged` 在首帧及之后每次宽高或旋转变化时回调（此前只在首帧一次）；回调改在主线程（此前在 WebRTC 渲染线程）。新增 `onFirstLocalVideoFrame(width:height:elapsed:)`。规则见 `SyRtcVideoFrameTracker`，与 Android 相同。
- `onNetworkQuality` 与 Android 统一（本端 uid = 对端最差一档，再逐个对端，按 uid 排序），新增 `SyRtcNetworkQuality.worst`；`onRtcStats` 改为每个对端一条（此前只发第一个对端）。
- 新增 `SyRtcErrorCode`，与 Android / Flutter 取值统一（见 README「错误码」）。**码值有变化**：音频路由 1004 → 1009，未知画质档位 1003 → 1000，附加信息过长 1006 → 1000，屏幕共享 1008 → 1006，视频源未就绪 -1001 → 1005（自定义采集为 1007）。被踢现在回调 `onError(1004)`；凭证停用时为 4031 / 4032 / 4033。
- 修复：Token 过期提醒只按三段式 JWT 的 `exp` 解析，服务端签发的 `payload.签名` Token 从不回调 `onTokenPrivilegeWillExpire`。现在读 `expireAt`（兼容 `exp`），见 `SyRtcTokenExpiry`。
- 修复：信令错误的文本取自 `data.message`（服务端实际字段），此前一直显示「信令错误」。

## 3.2.0

### 集成

- 明确以**源码**发布：CocoaPods `pod 'SyRtcSDK', '~> 3.2.0'`（Trunk 或 `:git` + `:tag`），Swift Package Manager 用仓库 URL 和 tag `v3.2.0`。
- SPM 的 WebRTC 改为与 CocoaPods 相同的 `WebRTC-SDK` 125.6422.07 xcframework（`binaryTarget`），不再依赖另一套 `stasel/WebRTC` 141。
- 示例工程去掉本地 `:path` 依赖，改为与客户相同的版本号。

### 修复

- **可选回调此前不会送达**：`onJoinChannelSuccess`、`onNetworkQuality`、`onConnectionStateChanged`、`onUserMuteAudio` 等 23 个回调只写在 protocol extension 里，引擎经 `SyRtcEventHandler?` 调用时静态派发到空默认实现，实现方（含 Flutter 插件）永远收不到。现已全部声明为协议要求，默认空实现保留，已有代码无需改动。单测 `SyRtcEventHandlerDispatchTests`。

### 新增

- `SyRoomService.renewToken`：`POST /api/rtc/token/renew`，鉴权与 `fetchToken` 相同。
- `SyRtcEngine.renewToken` 改为更新当前 RTC Token 并重连信令（不发送 leave、不拆掉已有媒体连接）。Token 为带 `exp` 的 JWT 时，过期前 30 秒回调 `onTokenPrivilegeWillExpire`，过期时回调 `onRequestToken`。
- `SyRtcEngine.setQualityTier` / `getQualityTier`：本地画质档位 `audio|sd|hd|fhd`。
- `SyRoomService.switchQualityTier`：`POST /api/rtc/quality/switch`（需要用户 JWT）。
- `SyRoomService.setRoomAttribute` / `getRoomAttributes` / `deleteRoomAttribute`：房间属性，对应 `POST /api/rtc/channel/meta/set|get|delete`（需要用户 JWT）。
- `SyRtcServiceError`：获取或续期 Token 时识别业务码 4031（凭证已停用）、4032（已吊销）、4033（已过期），HTTP 4xx 也会先读 JSON `code`。
- 网络质量：`onNetworkQuality` 使用 WebRTC candidate-pair RTT 与 inbound-rtp 丢包，没有统计时为 `unknown`。`getNetworkType` 来自 `NWPathMonitor`（wifi / cellular / ethernet / none），有网本身不算 excellent。
- 重连策略与 Android 统一：信令和 ICE 共用最多 5 次、间隔 1/2/4/8/16 秒；ICE 断开时 offer 发起方 `restartIce` 并重发 offer。新增 `onReconnecting` / `onReconnected` / `onReconnectFailed` 与 `SyRtcReconnectPolicy`。不再把各对端 ICE 原始状态转成 `onConnectionStateChanged`；放弃重连的 reason 由 `signaling_give_up` 改为 `signaling`，错误码由 1005 改为 1003（与 Android 相同）。
- 网络质量阈值与 Android 统一（参考即构）：excellent <100ms/<1%，good <200ms/<3%，poor <400ms/<8%，bad <800ms/<20%，其余 down（此前 down 需丢包 ≥50% 或 RTT ≥2000ms）。新增 `SyRtcNetworkQuality.rank`。
- 与 Android 对齐：`sendSei(streamId:data:)` 与回调 `onSeiMessage`（DataChannel `SYSEI` 前缀，有默认实现）；`isRemoteAudioMuted(uid:)` / `isRemoteVideoMuted(uid:)`；频道消息兼容旧版 Android 的 `stream-extra` / `client-mute` JSON。`onStreamMessage` 改在主线程回调。线格式单测见 `Tests/SyRtcSDKTests`（`xcodebuild test -scheme SyRtcSDK`）。
- 设备：`switchCamera` / `useFrontCamera`，`setAudioRoute` 只在扬声器和听筒之间切换；蓝牙和有线耳机只通过 `onAudioRoutingChanged` 上报。
- 音频设备：`enumerateRecordingDevices` 返回 `AVAudioSession.availableInputs`（uid / portName），`setRecordingDevice` 调 `setPreferredInput`，找不到或失败返回 -1。`enumeratePlaybackDevices` 只列能主动切换的 `speaker` / `earpiece`，`setPlaybackDevice` 对其他 id 返回 -1。
- `setVideoFrameProcessor`：本地 `CVPixelBuffer` 前处理钩子。`setBeautyEffectOptions` 只记录参数，不内置美颜渲染。
- 屏幕共享：`startScreenCapture` 把应用内 `RPScreenRecorder` 帧送进 WebRTC，并重新发 offer。`BroadcastExtension/` 只是广播扩展脚手架，不跨进程传帧。主 App 进程可调用 `pushScreenSampleBuffer`。
- 静音：`muteLocalAudio` / `muteLocalVideoStream` 会关轨道，并用信令类型 `user-media` 通知对端（`onUserMuteAudio` / `onUserMuteVideo`）。这不是 SFU 强制断流；服务端 `mute-audio` 仍走 `onServerMuteAudio`。
- 音量：`enableAudioVolumeIndication` 读取 WebRTC `audioLevel`（0–255），不再固定返回 0。
- `setStreamExtraInfo`：用信令广播附加信息（保留前缀 `sy-extra:`，回调 `onStreamExtraInfoUpdated`），不是视频 SEI。
- `enableCustomVideoCapture` / `sendCustomVideoFrame`：外部像素缓冲进本地视频轨。
- 信令断开后按 1、2、4、8、16 秒重连，最多 5 次，不拆掉已有 PeerConnection；成功后 `onRejoinChannelSuccess`。ICE 状态变化走 `onConnectionStateChanged`。
- `createDataStream` / `sendStreamMessage` 建在真实的网格 PeerConnection 上（标签 `sy-<id>`），不再创建一条未连接的 `"default"` 连接。对端 `didOpen` 后回调 `onStreamMessage`。
- 远端视频轨在 Unified Plan 的 `didAddReceiver` 上绑定。发布摄像头或屏幕时即使本端 uid 较大也会重新 offer，否则对端收不到画面。

## 3.1.0

### 重大变更 / Breaking

- **移除 CDN 旁路推流（直播）能力**：删除 RTMP/旁路相关 API 与类型；不再调用 `/api/rtc/live/*`。
- **产品功能位**：`hasLiveFeature` / `live` → `hasRtcFeature` / `rtc`；`hasVoiceFeature` 保留为兼容别名。

### 新增

- `onKicked` / `onServerMuteAudio` 可选回调（控制面信令；非 SFU 强制断流）

## 3.0.1

- Version align with Android/Flutter RTC SDKs.

## 3.0.0

### 版本同步

- 版本号与 Flutter SDK 3.0.0、Android SDK 3.0.0 统一
- 无功能变更，仅版本对齐

## 2.1.1

### 新增功能

- `SyRtcEngine.setChannelProfile(profile)` — 设置频道场景（通信/直播）
- `SyRtcEngine.enableAudioVolumeIndication(interval, smooth, reportVad)` — 启用音量提示回调
- `SyRtcEngine.getConnectionState()` — 获取当前连接状态
- `SyRtcEngine.getNetworkType()` — 获取当前网络类型
- `SyRoomService.setUserId(uid)` — 设置用户 ID 用于房间创建等需要身份认证的操作

### Bug 修复

- 修复 `SyRoomService` 的 API 路径与后端不一致的问题（`rooms` → `api/room/active` 等）
- 修复 `fetchToken` 的参数传递方式（改为 query params）
- 统一所有版本号为 2.1.1

## 2.1.0

### 新增 SyRoomService — 房间管理服务

- `SyRoomService` 类：房间管理 + Token 获取
  - `getRoomList()` / `createRoom()` / `closeRoom()` / `getRoomDetail()`
  - `fetchToken()` / `getOnlineCount()`
- `SyRoomInfo` 结构体

---

## 2.0.0 (Breaking Change)

### 架构调整

SDK 重新定位为纯 RTC 传输层，移除所有业务逻辑，对齐声网/即构等主流 RTC SDK 设计。

### 移除

- 房间管理、麦位管理、用户管理（踢人/禁言/封禁）、聊天、礼物等业务 API 及回调

### 新增

- 频道生命周期回调：`onJoinChannelSuccess`、`onLeaveChannel`、`onRejoinChannelSuccess`
- 连接与网络：`onConnectionStateChanged`、`onNetworkQuality`、`onRtcStats`
- Token 管理：`onTokenPrivilegeWillExpire`、`onRequestToken`、`renewToken()`
- 音频状态：`onLocalAudioStateChanged`、`onRemoteAudioStateChanged`、`onUserMuteAudio`、`onAudioRoutingChanged`
- 视频状态：`onLocalVideoStateChanged`、`onRemoteVideoStateChanged`、`onFirstRemoteVideoDecoded`、`onFirstRemoteVideoFrame`、`onVideoSizeChanged`
- 数据流：`createDataStream`、`sendStreamMessage`、`onStreamMessage`、`onStreamMessageError`
- Flutter 插件 iOS 端修复：`sendChannelMessage` 方法补齐、`release()` 正确释放 impl

### 迁移指南

业务逻辑请通过 `sendChannelMessage` 自定义 JSON 协议实现。

---

## 1.5.0

### 新功能

- **房间管理**：`updateRoomInfo`、`setRoomNotice`、`setRoomManager`
- **麦位管理**：`takeSeat`、`leaveSeat`、`requestSeat`、`handleSeatRequest`、`inviteToSeat`、`handleSeatInvitation`、`kickFromSeat`、`lockSeat`/`unlockSeat`、`muteSeat`/`unmuteSeat`
- **用户管理**：`kickUser`、`muteUser`、`banUser`
- **房间聊天**：`sendRoomMessage`
- **礼物系统**：`sendGift`
- **14 个新回调**：房间信息/公告/管理员变更、座位操作、用户管理、聊天、礼物等

### 升级说明

- CocoaPods：`pod 'SyRtcSDK', '~> 1.5.0'`
- SPM：选择 tag `v1.5.0`

---

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

# SY RTC iOS SDK 更新日志

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

# SY RTC iOS SDK

SY RTC iOS SDK 提供实时音视频通信。本仓库以 **Swift 源码** 分发，客户用版本号集成，不需要下载或解压 framework / zip。

当前版本：**3.2.0**（git tag `v3.2.0`）。最低系统 iOS 13.0，Swift 5.9，Xcode 15+。

## 集成 SDK

任选一种。两种都是「仓库 + 版本」，没有手动拷贝框架这一步。

### CocoaPods

在业务工程的 `Podfile` 里写：

```ruby
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'
use_frameworks!

target 'YourApp' do
  pod 'SyRtcSDK', '~> 3.2.0'
end
```

然后：

```bash
pod install
```

之后用 `.xcworkspace` 打开工程。

`pod 'SyRtcSDK', '~> 3.2.0'` 在 SDK 发布到 CocoaPods Trunk 之后生效。还没上 Trunk 时，用同一个版本 tag：

```ruby
pod 'SyRtcSDK', :git => 'https://github.com/carlcy/sy-rtc-ios-sdk.git', :tag => 'v3.2.0'
```

### Swift Package Manager

Xcode：**File → Add Package Dependencies…**，地址填：

```text
https://github.com/carlcy/sy-rtc-ios-sdk.git
```

Dependency Rule 选 **Up to Next Major Version**，版本填 `3.2.0`。把产品 `SyRtcSDK` 加到 App target。

如果业务工程本身是 Swift Package，在 `Package.swift` 里写：

```swift
dependencies: [
    .package(url: "https://github.com/carlcy/sy-rtc-ios-sdk.git", from: "3.2.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SyRtcSDK", package: "SyRtcSDK")
        ]
    )
]
```

版本来自 git tag `v3.2.0`，不需要单独上传二进制包。

## 快速开始

下面四步对应一次进房：加依赖（上一节）、初始化、取 Token、加入频道。接口以本仓库源码为准。

### 1. 权限

在 App 的 `Info.plist` 增加：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限进行语音通话</string>
<key>NSCameraUsageDescription</key>
<string>需要摄像头权限进行视频通话</string>
```

进房前请求麦克风权限：

```swift
import AVFoundation

AVAudioSession.sharedInstance().requestRecordPermission { granted in
    print(granted ? "麦克风已授权" : "麦克风被拒绝")
}
```

### 2. 初始化

```swift
import SyRtcSDK

let engine = SyRtcEngine.shared
engine.initialize(appId: appId) // AppId 从控制台获取
engine.setApiBaseUrl("https://syrtcapi.shengyuchenyao.cn")
engine.setSignalingServerUrl("wss://syrtcapi.shengyuchenyao.cn/ws/signaling")
engine.setEventHandler(self)
```

`SyRtcEventHandler` 里至少实现 `onUserJoined`、`onUserOffline`、`onVolumeIndication`。Token 续期实现 `onTokenPrivilegeWillExpire` 和 `onRequestToken`（有默认空实现，不写也能编译）。

### 3. 获取 Token

RTC Token 由控制面签发，不要在客户端用 AppSecret 自己拼。业务服务器调用 `POST /api/rtc/token`，再把字符串 Token 交给 App。

Demo 或已持有 AppSecret 的测试包可以用 `SyRoomService`：

```swift
let rooms = SyRoomService(apiBaseUrl: "https://syrtcapi.shengyuchenyao.cn", appId: appId)
rooms.setAppSecret(appSecret) // 仅测试。正式 App 让你们自己的服务器签发 Token

rooms.fetchToken(channelId: channelId, uid: uid, qualityTier: "sd") { result in
    switch result {
    case .success(let token):
        engine.join(channelId: channelId, uid: uid, token: token)
        engine.enableLocalAudio(true)
    case .failure(let error):
        print("获取 Token 失败: \(error)")
    }
}
```

`qualityTier` 可选：`audio`、`sd`、`hd`、`fhd`。

### 4. 加入频道

```swift
engine.join(channelId: channelId, uid: uid, token: token)
engine.enableLocalAudio(true)
```

加入成功会回调 `onJoinChannelSuccess(channelId:uid:elapsed:)`。远端用户进入时回调 `onUserJoined`。

离开并释放：

```swift
engine.leave()
engine.release()
```

角色（主播可说话，观众只听）：

```swift
engine.setClientRole(.host)     // 或 .audience / .publisher / .subscriber
```

## 续期 Token

Token 快过期时 SDK 会回调 `onTokenPrivilegeWillExpire`（提前 30 秒），到期回调 `onRequestToken`。过期时间取自 Token payload 的 `expireAt`（服务端 Token 形如 `base64url(payload).签名`；也兼容 JWT 的 `exp`），`join` 和 `renewToken` 后重新计时，Android 行为相同。3.2.0 及之前只按三段式 JWT 解析，服务端签发的两段式 Token 实际从不提醒。服务端也会推送 `token-privilege-will-expire` / `token-expired`（带 `data.expireAt`）；本地定时器与服务端推送按 Token 去重（`SyRtcTokenExpiryDedupe`），每个 Token 只回调一次提醒、一次过期，旧 Token 迟到的推送忽略。收到后向控制面续期，再交给引擎，不要先 `leave`：

```swift
func onTokenPrivilegeWillExpire() {
    rooms.renewToken(channelId: channelId, uid: uid) { result in
        if case .success(let token) = result {
            engine.renewToken(token)
        }
    }
}
```

`SyRoomService.renewToken` 对应 `POST /api/rtc/token/renew`，鉴权与 `fetchToken` 相同（`X-App-Id` + `X-App-Secret`，或用户 JWT）。`SyRtcEngine.renewToken` 会更新当前会话的信令 Token，已建立的媒体连接保留。

## 切换画质

本地采集立刻生效（不需要登录）：

```swift
engine.setQualityTier(.hd)          // .audio / .sd / .hd / .fhd
engine.setQualityTier("fhd")        // 直接传后台字符串也可以
```

控制面档位（计费 / 权益）走 `POST /api/rtc/quality/switch`，**必须是用户 JWT**（`setAuthToken`）。只带 AppSecret 会返回未登录。

```swift
rooms.setAuthToken(userJwt)
rooms.switchQualityTier(channelId: channelId, qualityTier: "hd", uid: uid) { result in
    switch result {
    case .success(let newToken):
        engine.setQualityTier(.hd)
        if let newToken { engine.renewToken(newToken) }
    case .failure(let error):
        print(error)
    }
}
```

若接口没有返回新 Token，用新的 `qualityTier` 再调一次 `fetchToken` / `renewToken`。

## 房间属性

对应控制面频道元数据（ZEGO 房间附加信息那种 key-value），**同样需要用户 JWT**：

```swift
rooms.setAuthToken(userJwt)

rooms.setRoomAttribute(channelId: channelId, key: "notice", value: "欢迎") { _ in }

rooms.getRoomAttributes(channelId: channelId) { result in
    if case .success(let attrs) = result {
        print(attrs) // [String: String]
    }
}

rooms.deleteRoomAttribute(channelId: channelId, key: "notice") { _ in }
```

路径分别是 `POST /api/rtc/channel/meta/set`、`/get`、`/delete`。

## 客户端能力（相对 ZEGO Express）

这些接口跑在本机 WebRTC 网格和控制面信令上。没有 CDN、云端转码、云端录制、服务端 simulcast，也不要把美颜参数当成已经在渲染。

```swift
engine.switchCamera()
engine.useFrontCamera(true)
engine.setAudioRoute(.speaker)          // 只能是 .speaker 或 .earpiece
engine.setVideoFrameProcessor { pixelBuffer, _ in pixelBuffer }
engine.enableCustomVideoCapture(true)
engine.sendCustomVideoFrame(pixelBuffer: buffer)
engine.setStreamExtraInfo("座位:1")       // 信令附加信息，不是 SEI
engine.startScreenCapture(ScreenCaptureConfiguration(frameRate: 15, width: 1280, height: 720))
let streamId = engine.createDataStream(reliable: true, ordered: true)
engine.sendStreamMessage(streamId: streamId, data: Data("hi".utf8))
engine.sendSei(streamId: streamId, data: Data("ts=123".utf8))  // 对端 onSeiMessage，DataChannel 前缀，不是码流 SEI
engine.isRemoteAudioMuted(uid: "u2")    // 本机屏蔽或对端自己静音都算 true
engine.isRemoteVideoMuted(uid: "u2")
```

**断线重连。** 与 Android 相同（`SyRtcReconnectPolicy`）：信令或 ICE 断开后最多重试 5 次，第 n 次等待 2^(n-1) 秒（1、2、4、8、16 秒）。ICE 断开时 uid 字典序较小的一方 `restartIce` 并重发 offer。

| 时机 | `onConnectionStateChanged(state:reason:)` | 专用回调 |
|---|---|---|
| join | `connecting` / `joining` → `connected` / `join_success` | `onJoinChannelSuccess` |
| 断开，开始重试 | `reconnecting` / `signaling` 或 `ice` | `onReconnecting(reason:attempt:maxAttempts:delayMs:)` |
| 恢复 | `connected` / `rejoin_success` | `onRejoinChannelSuccess`、`onReconnected(reason:)` |
| 5 次都失败 | `failed` / `signaling` 或 `ice` | `onReconnectFailed(reason:)`、`onError(1003)` |
| leave | `disconnecting` / `leaving` → `disconnected` / `leave` | `onLeaveChannel` |

此前 iOS 把每个对端的 ICE / PeerConnection 原始状态直接转成 `onConnectionStateChanged`（reason 如 `ice_connected:u2`），没有 ICE 重启，信令放弃时 reason 为 `signaling_give_up`、错误码 1005。

**网络质量。** `onNetworkQuality` 的档位由 `SyRtcNetworkQuality.level` 计算。RTT 和丢包各自落档，取较差的一档；没有样本时为 `unknown`。阈值参考即构 Express 的分级，Android 与 iOS 完全相同（两端各有同一张表的单测）。 `onRtcStats` 同时给 `packetLossRate`（0–1）和 `lossPercent`（0–100）。每 2 秒一轮：先 `onNetworkQuality(本端 uid)`，质量为所有对端链路最差的一档（`SyRtcNetworkQuality.worst`，unknown 不计入），再逐个对端（按 uid 排序）；没有对端时只回调本端 `unknown`。Android 相同。`onRtcStats` 每个对端一条（此前 iOS 只发第一个对端）。**上下行分开**（`SyRtcLinkQuality`，与 Android `LinkQuality` 相同）：`txQuality` = RTT + 上行丢包（对端回报的 `remote-inbound-rtp.fractionLost`）；`rxQuality` = 本统计周期的下行丢包（`inbound-rtp` 丢包 / 收包增量）+ 抖动（excellent <30ms、good <50ms、poor <100ms、bad <200ms、其余 down），取较差。本端 uid 的 tx / rx 分别取各对端最差。`onRtcStats` 另给 `txQuality` / `rxQuality` / `txPacketLossRate` / `rxPacketLossRate` / `jitterMs`，`quality` 为两者较差。此前 tx 与 rx 同值，且下行丢包只取最后一路 inbound-rtp 的累计值。

| 档位 | RTT (ms) | 丢包 |
|---|---|---|
| `excellent` | < 100 | < 1% |
| `good` | < 200 | < 3% |
| `poor` | < 400 | < 8% |
| `bad` | < 800 | < 20% |
| `down` | ≥ 800 | ≥ 20% |

**与 Android 互通。** 静音通知走信令 `user-media`（对端 `onUserMuteAudio` / `onUserMuteVideo`），附加信息走频道消息 `sy-extra:<文本>`（UTF-8 最多 1024 字节，新成员进房会补发），SEI 走 DataChannel `SYSEI` 前缀。这些保留消息不会进 `onChannelMessage`。旧版 Android（3.1）的 JSON 信封 `stream-extra` / `client-mute` 也能解析。DataChannel 回调（`onStreamMessage` / `onSeiMessage`）在主线程。

Token 失败时把错误转成 `SyRtcServiceError` 看说明：4031 凭证已停用，4032 已吊销，4033 已过期。

```swift
if let serviceError = error as? SyRtcServiceError {
    print(serviceError.businessCode ?? -1, serviceError.localizedDescription)
}
```

运行时版本号：`SyRtcSDKVersion.current` 为 `3.2.0`，与 podspec、`VERSION` 和 Android `RtcEngine.VERSION` 一致。

应用内屏幕共享失败（常见于模拟器）会回调 `onError`，不会把状态标成正在共享。系统广播扩展见 [BroadcastExtension/README.md](BroadcastExtension/README.md)，扩展进程里的帧到不了引擎。

## 首帧与分辨率

远端视频轨到达后挂一个常驻 sink：第一帧回调 `onFirstRemoteVideoDecoded` 和 `onFirstRemoteVideoFrame`（elapsed 为距 join 的毫秒），第一帧及之后宽、高或旋转变化时回调 `onVideoSizeChanged`（宽高为缓冲区尺寸，rotation 0/90/180/270），都在主线程。本地摄像头（含自定义采集）或屏幕共享视频轨新建后的第一帧回调 `onFirstLocalVideoFrame`。Android 相同。

## 本地录音

`startAudioRecording(AudioRecordingConfiguration(filePath:codecType:))`，与 Android 相同：

- 格式：`aac` / `aacLc` / `m4a` 输出 AAC（MPEG-4，建议 `.m4a`）；`wav` / `pcm` 输出 16 bit WAV。**不支持 mp3**，传入回调 `onError(1000)` 并返回 -1。
- 频道内：录 WebRTC 管线里的 PCM，本端（APM 采集后处理回调）+ 所有远端（`RTCAudioTrack` renderer）混成单声道，`includeLocal` / `includeRemote` 控制；不另开 `AVAudioRecorder`，因此不会与通话抢麦录成静音。本端静音时不录本端；本端静音了某远端时不录他。
- 频道外：`AVAudioRecorder` 录麦克风，仅 AAC。频道外开始的录音 join 后请重新开始。
- leave 时自动停止并写完文件；远端离开时从混音中移除。
- 已在模拟器验证混音与写文件（单测）；本端 APM 回调与远端 renderer 在真机上的实际出声待真机验证。

## 错误码

`onError(code:message:)` 的取值三端（iOS `SyRtcErrorCode`、Android `RtcErrorCode`、Flutter `SyRtcErrorCode`）相同：

| code | 常量 | 含义 |
|---|---|---|
| 1000 | `invalidArgument` | 参数无效或调用时机不对（空 Token、未知画质档位、附加信息超过 1024 字节） |
| 1002 | `signaling` | 信令服务端返回的错误，message 为服务端原文 |
| 1003 | `reconnectFailed` | 重连 5 次都失败，需要 leave 后重新 join |
| 1004 | `kicked` | 被房间管理踢出（同时回调 `onKicked`） |
| 1005 | `camera` | 摄像头不可用或视频源未就绪 |
| 1006 | `screenShare` | 屏幕共享失败 |
| 1007 | `customCapture` | 自定义采集用法错误或视频源未就绪 |
| 1009 | `audioRoute` | 音频路由不支持（iOS 只能在扬声器和听筒之间切换）或设置失败 |
| 403 | `forbidden` | 服务端拒绝入房：在踢出名单、房间锁定、不在白名单 |
| 4031 / 4032 / 4033 | `credentialSuspended` / `Revoked` / `Expired` | AppId 访问凭证被暂停 / 吊销 / 过期；服务端断开信令，SDK 回调 `onKicked` 后以此码回调 `onError` |

403 和 4031–4033 与控制面 REST 业务码相同，取自信令 `kicked` / `error` 帧的 `data.code`（需要 2026-09-30 之后的 rtc-backend-go）。

与 3.2.0 相比有变化的码：音频路由 1004 → 1009，未知画质档位 1003 → 1000，附加信息过长 1006 → 1000，屏幕共享 1008 → 1006，视频源未就绪 -1001 → 1005 / 1007，被踢由不报错改为 1004。

## 示例工程

`example/` 与客户使用同一行依赖：`pod 'SyRtcSDK', '~> 3.2.0'`。步骤见 [example/README.md](example/README.md)。

## 发布新版本

维护者打 tag、`pod trunk push` 的完整命令在 [PUBLISH_GUIDE.md](PUBLISH_GUIDE.md)。

## 常见问题

**进不了房间。** Token 过期、AppId 不对，或麦克风权限没给。重新 `fetchToken` 再 `join`。

**没有声音。** 确认已 `enableLocalAudio(true)`，没有 `muteLocalAudio(true)`，角色不是观众。

**画质或房间属性接口返回未登录。** 这两个接口不认 AppSecret，先 `setAuthToken` 传入用户 JWT。

## 许可证

MIT License

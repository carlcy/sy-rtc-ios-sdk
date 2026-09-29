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

Token 快过期时 SDK 会回调 `onTokenPrivilegeWillExpire`（JWT 且带 `exp` 时，提前 30 秒）。已经过期时回调 `onRequestToken`。收到后向控制面续期，再交给引擎，不要先 `leave`：

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

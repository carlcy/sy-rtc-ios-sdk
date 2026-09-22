# SyRtcSDK iOS Example

可在 **iOS 模拟器** 与 **真机** 上运行的 RTC 示例：配置 → 初始化 → 加入/离开 → 静音 → 本地/远端视频。

## 运行

```bash
cd example
pod install
open SyRtcSDKExample.xcworkspace
```

命令行构建（模拟器）：

```bash
xcodebuild -workspace SyRtcSDKExample.xcworkspace \
  -scheme SyRtcSDKExample \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

真机：在 Xcode 选择你的开发团队与设备，连接 iPhone 后 Run。需在系统弹窗中允许麦克风 / 摄像头。

## 示例能力

| 操作 | 说明 |
|------|------|
| 配置 | AppId / AppSecret / API Base / Signaling / Channel / UID |
| 请求权限 | 麦克风 + 摄像头（Info.plist 已含 Usage Description） |
| 初始化 | `SyRtcEngine.initialize` + 信令 / API 地址 |
| 加入 / 离开 | `POST /api/rtc/token` 后 `join` / `leave` |
| 静音 | `muteLocalAudio` |
| 启用视频 | `enableVideo` + `setupLocalVideo(view:)` |
| 开始预览 | `startPreview`（绑定 `RTCMTLVideoView`） |
| 远端画面 | `onUserJoined` → `setupRemoteVideo(uid:view:)` |

## 模拟器 vs 真机

| | 模拟器 | 真机 |
|--|--------|------|
| 加入频道 / 信令 | 可用（需网络） | 可用 |
| 麦克风 | 部分 Mac 可转发麦克风，不稳定 | 完整 |
| 摄像头 / 本地预览 | **通常没有摄像头**，画面为黑占位 | 需要授权后预览 |
| 远端视频 | 对端在真机时可能收到，本地无法采集 | 完整 |

模拟器顶部有橙色提示条。无摄像头时 SDK 会回调 `onError(code: -1001)`，**音频与加入房间仍可测**。

## 权限

`Info.plist`：

- `NSMicrophoneUsageDescription`
- `NSCameraUsageDescription`
- `NSAppTransportSecurity` / `NSAllowsArbitraryLoads`（demo HTTP）

## 默认 demo 地址

界面预填了 demo 控制面（`http://127.0.0.1:8080`）。生产环境请换成你的 AppId 与 HTTPS / WSS。**不要把 AppSecret 写进正式客户端。**

## 对接本地 Go 后端

默认 API `http://127.0.0.1:8080`，信令 `ws://127.0.0.1:8080/ws/signaling`。

```bash
cd ../../rtc-backend-go && make run
```

- Token：`POST /api/rtc/token?channelId=&uid=`，Header `X-App-Id` / `X-App-Secret`
- **模拟器**可用 127.0.0.1；**真机**请改成 Mac 的局域网 IP
- 填写控制台 AppId / AppSecret（应用需开通 RTC）

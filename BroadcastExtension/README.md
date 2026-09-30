# ReplayKit 广播扩展脚手架

这是给系统广播（控制中心 → 屏幕镜像 → 广播）准备的 **Upload Extension 源码脚手架**，版本与 SDK 同为 3.2.0。CocoaPods / SPM **不会**把它编进 `SyRtcSDK`。

## 它能做什么

在 Xcode 里新建 Broadcast Upload Extension，用这里的 `SampleHandler.swift` 和 `Info.plist` 作为起点。扩展里可以收到 `CMSampleBuffer`。

## 它不能做什么

扩展和主 App 不是同一个进程。`SampleHandler` 里的帧不会自动进入 `SyRtcEngine`，SDK 也没有内置 App Group 或 socket 去假装跨进程传帧。

同一个进程里的屏幕共享用：

```swift
engine.startScreenCapture(ScreenCaptureConfiguration(frameRate: 15, width: 1280, height: 720))
```

这会走 `RPScreenRecorder.startCapture`，把画面编码进当前这条 WebRTC 网格连接。模拟器和未授权的录屏会失败，失败会回调 `onError`，不会把状态标成已经在共享。

若你自己打通了跨进程通道，在主 App 进程里把视频帧交给：

```swift
engine.pushScreenSampleBuffer(sampleBuffer)
```

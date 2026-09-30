# iOS SDK Demo

示例工程用 CocoaPods **按版本** 依赖 SyRtcSDK，和客户的 `Podfile` 同一行写法。不要 `:path` 指向上级目录，也不要下载、解压 framework。

## 依赖

`Podfile`：

```ruby
pod 'SyRtcSDK', '~> 3.2.2'
```

这一行在 [CocoaPods Trunk](https://cocoapods.org) 已有 3.2.2 之后可以直接安装。维护者发布步骤见仓库根目录 [PUBLISH_GUIDE.md](../PUBLISH_GUIDE.md)。

SyRtcSDK 3.2.2 已在 Trunk。本机 CDN 缓存未更新（`pod repo update` 仍找不到）时，可临时把 Podfile 改成：

```ruby
pod 'SyRtcSDK', :git => 'https://github.com/carlcy/sy-rtc-ios-sdk.git', :tag => 'v3.2.2'
```

## 运行

```bash
cd example
pod install
open SyRtcSDKExample.xcworkspace
```

用 `.xcworkspace`，不要用 `.xcodeproj`。

命令行编模拟器（需要 macOS / Xcode）：

```bash
xcodebuild -workspace SyRtcSDKExample.xcworkspace \
  -scheme SyRtcSDKExample \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`Info.plist` 已包含麦克风和摄像头权限说明。流程、模拟器限制见 [README_EXAMPLE.md](./README_EXAMPLE.md)。

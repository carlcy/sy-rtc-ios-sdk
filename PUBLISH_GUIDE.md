# 发布 SyRtcSDK 3.x（维护者）

客户只写版本号，不下载 zip。发布物是：

- git tag `vX.Y.Z`（Swift Package Manager 靠它解析版本）
- CocoaPods Trunk 上的同名版本，或在 Trunk 之前用 `:git` + `:tag`

本仓库是 **Swift 源码包**。`Package.swift` 用 `binaryTarget` 引用与 CocoaPods 相同的 WebRTC 125.6422.07 xcframework。不要把 `SyRtcSDK.xcframework` 当成客户集成方式。`build-xcframework.sh` 只在你已经有 Xcode Framework 工程时可选，Demo 和 README 都不使用它。

## 客户最终会写的两行

CocoaPods（Trunk 发布成功之后）：

```ruby
pod 'SyRtcSDK', '~> 3.2.0'
```

Trunk 还没收录、但 tag 已经推上去时：

```ruby
pod 'SyRtcSDK', :git => 'https://github.com/carlcy/sy-rtc-ios-sdk.git', :tag => 'v3.2.0'
```

Swift Package Manager：

```swift
.package(url: "https://github.com/carlcy/sy-rtc-ios-sdk.git", from: "3.2.0")
```

Xcode 里 Add Package Dependencies，URL 填 `https://github.com/carlcy/sy-rtc-ios-sdk.git`，规则选 Up to Next Major，从 `3.2.0` 起。

示例工程 `example/Podfile` 用的就是第一行。

## 切一个版本

下面以 `3.2.0` 为例。换版本时三处一起改：`SyRtcSDK.podspec` 的 `s.version`、`VERSION`、README 里的示例版本号。SPM 没有单独的版本字段，版本就是 tag。

1. 确认 `s.source` 仍是：

   ```ruby
   s.source = { :git => 'https://github.com/carlcy/sy-rtc-ios-sdk.git', :tag => "v#{s.version}" }
   ```

   tag 必须带 `v` 前缀，和历史上的 `v3.1.0` 一样。SPM 认 `v3.2.0` 和 `3.2.0` 这两种写法里的前者。

2. 提交版本号改动并推到 `main`（或你要打 tag 的提交）。

3. 打 tag 并推送。**先有 tag，再 `pod trunk push`**，否则 Trunk 按 podspec 里的 tag 拉源码会失败。

   ```bash
   git tag v3.2.0
   git push origin v3.2.0
   ```

4. 本机校验（需要 macOS 上的 Xcode 才能真正编译通过；Linux 上只能做清单检查）：

   ```bash
   swift package dump-package
   swift package describe
   pod ipc spec SyRtcSDK.podspec
   pod lib lint SyRtcSDK.podspec --allow-warnings
   ```

   `pod spec lint` 会去克隆 tag `v3.2.0`，所以必须在第 3 步之后执行。

5. 注册 Trunk（每台机器、每个维护者账号一次）：

   ```bash
   pod trunk register you@company.com 'Your Name'
   ```

   点邮件里的确认链接。`pod trunk me` 能看到账号后继续。

6. 推到 Trunk：

   ```bash
   pod trunk push SyRtcSDK.podspec
   ```

   成功后过几分钟，客户的 `pod 'SyRtcSDK', '~> 3.2.0'` 就能 `pod install`。可用 `pod trunk info SyRtcSDK` 查看。

7. SPM 不需要再传一次包。tag 在 GitHub 上之后，Xcode 选 `3.2.0` 就会拉这个 tag。

8. 示例工程：Trunk 可用后，在 `example/` 执行 `pod install`，用 `SyRtcSDKExample.xcworkspace` 打开。Trunk 索引还没好、但 tag 已经在仓库上时，把 Podfile 里注释的 `:git` / `:tag` 那行打开、把 `~> 3.2.0` 那行注释掉，再 `pod install`。

## 不要做的事

- 不要让客户或 Demo 下载 `SyRtcSDK.xcframework` / zip 再拖进 Xcode。
- 不要在示例 Podfile 里写 `pod 'SyRtcSDK', :path => '../'`。那是本地联调，不是客户集成。
- 不要只推 podspec 不打 `v` 开头的 tag。CocoaPods 和 SPM 都对不上版本。

# SY RTC iOS SDK

SY RTC iOS SDK 是一个用于实时语音通信的 iOS 原生 SDK。

## ✨ 特性

- ✅ 完整的 RTC 功能
- ✅ Swift 5.0+ 支持
- ✅ 支持 Swift Package Manager 和 CocoaPods
- ✅ 异步 API 设计

## 📦 安装

### 方式一：使用 Swift Package Manager（推荐）

1. 在 Xcode 中打开项目
2. 选择 **File** → **Add Packages...**
3. 输入仓库地址：
   ```
   https://github.com/carlcy/sy-rtc-ios-sdk.git
   ```
4. 选择版本（如 `1.2.0`）
5. 点击 **Add Package**

### 方式二：使用 CocoaPods

1. **创建 Podfile**

   在项目根目录创建 `Podfile`：

   ```ruby
   platform :ios, '13.0'
   use_frameworks!

   target 'YourApp' do
     pod 'SyRtcSDK', '~> 1.2.0'
   end
   ```

   **Apple Silicon（M 系列）提示**：如果你需要在 iOS Simulator 运行，可能需要在 `Podfile` 里排除 `arm64`：

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end
```

2. **安装依赖**

   ```bash
   pod install
   ```

3. **打开工作空间**

   使用 `.xcworkspace` 文件打开项目，而不是 `.xcodeproj`

### 方式三：手动集成

1. **下载 XCFramework**

   从发布页面下载 `SyRtcSDK.xcframework`

2. **添加到项目**

   - 在 Xcode 中选择项目
   - 选择 Target
   - 进入 **General** → **Frameworks, Libraries, and Embedded Content**
   - 点击 **+** 添加 `SyRtcSDK.xcframework`
   - 确保设置为 **Embed & Sign**

## 🚀 快速开始

### 1. 添加权限

在 `Info.plist` 中添加：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限进行语音通话</string>
```

### 2. 导入 SDK

```swift
import SyRtcSDK
```

### 3. 初始化 SDK

```swift
let engine = SyRtcEngine.initialize(appId: "your_app_id") // AppId 从用户后台获取
```

### 4. 设置事件监听

```swift
engine.setEventHandler { event in
    switch event {
    case .userJoined(let uid, let elapsed):
        print("用户加入: \(uid), 耗时: \(elapsed)ms")
    case .userOffline(let uid, let reason):
        print("用户离开: \(uid), 原因: \(reason)")
    case .volumeIndication(let speakers):
        speakers.forEach { info in
            print("用户 \(info.uid) 音量: \(info.volume)")
        }
    }
}
```

### 5. 加入房间

```swift
// 先从服务器获取 Token（不能在前端直接生成）
let token = try await getTokenFromServer(appId: appId, channelId: channelId, uid: uid)

// 加入房间
try await engine.join(channelId: channelId, uid: uid, token: token)
```

### 6. 控制音频

```swift
// 启用本地音频
try await engine.enableLocalAudio(enabled: true)

// 静音
try await engine.muteLocalAudio(muted: true)

// 取消静音
try await engine.muteLocalAudio(muted: false)
```

### 7. 设置角色

```swift
// 设置为主播
try await engine.setClientRole(.host)

// 设置为观众
try await engine.setClientRole(.audience)
```

### 8. 离开房间

```swift
try await engine.leave()
```

### 9. 释放资源

```swift
engine.release()
```

## 📖 完整示例

```swift
import UIKit
import SyRtcSDK

class ViewController: UIViewController {
    var engine: SyRtcEngine?
    var isJoined = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 请求麦克风权限
        requestMicrophonePermission()
        
        // 初始化引擎
        initEngine()
    }
    
    func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("麦克风权限已授予")
            } else {
                print("麦克风权限被拒绝")
            }
        }
    }
    
    func initEngine() {
        engine = SyRtcEngine.initialize(appId: "your_app_id")
        
        engine?.setEventHandler { [weak self] event in
            switch event {
            case .userJoined(let uid, let elapsed):
                print("用户加入: \(uid)")
            case .userOffline(let uid, let reason):
                print("用户离开: \(uid)")
            case .volumeIndication(let speakers):
                // 处理音量指示
                break
            }
        }
    }
    
    @IBAction func joinChannel() {
        guard !isJoined else { return }
        
        Task {
            do {
                // 从服务器获取 Token
                let token = try await getTokenFromServer()
                
                // 加入房间
                try await engine?.join(
                    channelId: "channel_001",
                    uid: "user_001",
                    token: token
                )
                
                // 启用本地音频
                try await engine?.enableLocalAudio(enabled: true)
                
                isJoined = true
            } catch {
                print("加入房间失败: \(error)")
            }
        }
    }
    
    @IBAction func leaveChannel() {
        guard isJoined else { return }
        
        Task {
            do {
                try await engine?.leave()
                isJoined = false
            } catch {
                print("离开房间失败: \(error)")
            }
        }
    }
    
    func getTokenFromServer() async throws -> String {
        // 调用服务器 API 获取 Token
        // 这里需要实现 HTTP 请求
        let url = URL(string: "https://your-api.com/rtc/token")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        return response.data.token
    }
    
    deinit {
        engine?.release()
    }
}
```

## 📚 API 文档

### SyRtcEngine

#### 初始化

```swift
static func initialize(appId: String) -> SyRtcEngine
```

初始化 RTC 引擎。

**参数：**
- `appId`: 应用ID，从用户后台获取

**返回：**
- `SyRtcEngine`: 引擎实例

#### 加入房间

```swift
func join(channelId: String, uid: String, token: String) async throws
```

加入语音房间。

**参数：**
- `channelId`: 房间ID
- `uid`: 用户ID（字符串类型）
- `token`: 鉴权Token（从服务器获取）

**抛出：**
- `RtcError`: 如果加入失败

#### 离开房间

```swift
func leave() async throws
```

离开当前房间。

**抛出：**
- `RtcError`: 如果离开失败

#### 启用/禁用本地音频

```swift
func enableLocalAudio(enabled: Bool) async throws
```

启用或禁用本地音频采集和播放。

**参数：**
- `enabled`: `true` 为启用，`false` 为禁用

**抛出：**
- `RtcError`: 如果操作失败

#### 静音/取消静音

```swift
func muteLocalAudio(muted: Bool) async throws
```

静音或取消静音本地音频。

**参数：**
- `muted`: `true` 为静音，`false` 为取消静音

**抛出：**
- `RtcError`: 如果操作失败

#### 设置客户端角色

```swift
func setClientRole(_ role: RtcClientRole) async throws
```

设置客户端角色。

**参数：**
- `role`: `.host` 或 `.audience`

**抛出：**
- `RtcError`: 如果操作失败

#### 设置事件监听

```swift
func setEventHandler(_ handler: ((RtcEvent) -> Void)?)
```

设置事件监听器。

**参数：**
- `handler`: 事件处理闭包，`nil` 表示移除监听

#### 释放资源

```swift
func release()
```

释放引擎资源。在不再使用引擎时调用。

### RtcEvent

事件枚举：

```swift
enum RtcEvent {
    case userJoined(uid: String, elapsed: Int)
    case userOffline(uid: String, reason: String)
    case volumeIndication(speakers: [VolumeInfo])
}
```

**事件说明：**
- `userJoined`: 当有用户加入房间时触发
  - `uid`: 用户ID
  - `elapsed`: 加入耗时（毫秒）
- `userOffline`: 当有用户离开房间时触发
  - `uid`: 用户ID
  - `reason`: 离开原因
- `volumeIndication`: 当检测到用户音量变化时触发
  - `speakers`: 说话者列表

### RtcClientRole

客户端角色枚举：

```swift
enum RtcClientRole {
    case host      // 主播，可以说话
    case audience  // 观众，只能听
}
```

### VolumeInfo

音量信息：

```swift
struct VolumeInfo {
    let uid: String    // 用户ID
    let volume: Int    // 音量（0-255）
}
```

### RtcError

错误类型：

```swift
enum RtcError: Error {
    case invalidAppId
    case invalidToken
    case networkError
    case permissionDenied
    case unknown(Int)
}
```

## 🔑 如何获取 Token？

**重要**：Token 必须从服务器获取，不能在前端直接生成！

### 推荐流程

1. **客户端请求加入房间**
   ```swift
   let url = URL(string: "https://your-api.com/rtc/token")!
   var request = URLRequest(url: url)
   request.httpMethod = "POST"
   request.setValue("application/json", forHTTPHeaderField: "Content-Type")
   
   let body = [
       "appId": appId,
       "channelId": channelId,
       "uid": uid
   ]
   request.httpBody = try JSONSerialization.data(withJSONObject: body)
   
   let (data, _) = try await URLSession.shared.data(for: request)
   let response = try JSONDecoder().decode(TokenResponse.self, from: data)
   let token = response.data.token
   ```

2. **服务器生成 Token**
   ```java
   // 服务器代码（Java Spring Boot）
   @PostMapping("/rtc/token")
   public Result<String> generateToken(@RequestBody TokenRequest request) {
       String token = rtcService.generateToken(
           request.getAppId(),
           request.getChannelId(),
           request.getUid()
       );
       return Result.success(token);
   }
   ```

3. **客户端使用 Token 加入房间**
   ```swift
   try await engine.join(channelId: channelId, uid: uid, token: token)
   ```

## ⚙️ 项目配置

### 最低要求

- **iOS**: 13.0+
- **Swift**: 5.0+
- **Xcode**: 14.0+

### 权限配置

在 `Info.plist` 中添加：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限进行语音通话</string>
```

### 运行时权限请求

iOS 需要动态请求麦克风权限：

```swift
import AVFoundation

AVAudioSession.sharedInstance().requestRecordPermission { granted in
    if granted {
        print("麦克风权限已授予")
    } else {
        print("麦克风权限被拒绝")
    }
}
```

### Podfile 配置（如果使用 CocoaPods）

```ruby
platform :ios, '13.0'
use_frameworks!

target 'YourApp' do
  pod 'SyRtcSDK', '~> 1.2.0'
end
```

## 📦 构建 XCFramework

如果需要构建 XCFramework：

```bash
./build-xcframework.sh
```

构建完成后，XCFramework 位于 `build/` 目录。

## ❓ 常见问题

### 1. 无法加入房间？

**可能原因：**
- Token 无效或已过期
- 网络连接问题
- 权限未授予

**解决方法：**
- 重新从服务器获取 Token
- 检查网络连接
- 确保已授予麦克风权限

### 2. 没有声音？

**可能原因：**
- 本地音频未启用
- 已静音
- 角色设置为观众

**解决方法：**
```swift
// 启用本地音频
try await engine.enableLocalAudio(enabled: true)

// 取消静音
try await engine.muteLocalAudio(muted: false)

// 设置为主播
try await engine.setClientRole(.host)
```

### 3. 编译错误？

**可能原因：**
- Swift 版本不兼容
- 依赖冲突

**解决方法：**
- 确保 Swift 版本 >= 5.0
- 检查依赖版本冲突
- 清理构建缓存：`Product → Clean Build Folder`

## 📱 平台要求

- **iOS**: 13.0+
- **Swift**: 5.0+
- **Xcode**: 14.0+

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

**最后更新**: 2026-01-14

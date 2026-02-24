# iOS SDK Demo

这是一个完整的 iOS SDK 使用示例项目，使用纯代码 UI（无 Storyboard）。

## 📁 项目结构

```
example/
├── SyRtcSDKExample.xcodeproj/    # Xcode 项目
├── SyRtcSDKExample.xcworkspace   # CocoaPods 工作空间（用此打开）
├── SyRtcSDKExample/
│   ├── ViewController.swift      # 主界面（程序化 UI）
│   ├── AppDelegate.swift         # 应用入口
│   └── Info.plist
├── Podfile
└── Podfile.lock
```

## 🚀 快速开始

### 1. 安装依赖

```bash
cd example
pod install
```

### 2. 打开项目

**重要**：请使用 `.xcworkspace` 打开，不要使用 `.xcodeproj`：

```bash
open SyRtcSDKExample.xcworkspace
```

### 3. 构建

在 Xcode 中选择模拟器或真机，按 Cmd+B 构建。

或使用命令行：

```bash
xcodebuild -workspace SyRtcSDKExample.xcworkspace \
  -scheme SyRtcSDKExample \
  -sdk iphonesimulator \
  -configuration Debug build
```

### 4. 权限

`Info.plist` 已包含麦克风和摄像头权限说明。

## 📝 使用示例

参考 `SyRtcSDKExample/ViewController.swift`。应用提供初始化、加入/离开房间、音频控制、视频预览等按钮。

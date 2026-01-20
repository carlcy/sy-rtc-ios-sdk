# iOS SDK Demo

这是一个完整的 iOS SDK 使用示例项目。

## 📁 项目结构

```
example/
├── SyRtcSDKExample/
│   ├── ViewController.swift
│   ├── AppDelegate.swift
│   └── Info.plist
└── Podfile
```

## 🚀 快速开始

### 1. 安装依赖

使用 CocoaPods：

```bash
pod install
```

或使用 Swift Package Manager（在 Xcode 中添加包依赖）

### 2. 添加权限

在 `Info.plist` 中添加：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限进行语音通话</string>
<key>NSCameraUsageDescription</key>
<string>需要摄像头权限进行视频通话</string>
```

### 3. 使用示例

参考 `SyRtcSDKExample/ViewController.swift`

## 📝 完整示例代码

详见 README.md 中的示例代码部分。

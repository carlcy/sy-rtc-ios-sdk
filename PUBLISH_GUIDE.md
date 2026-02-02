# iOS SDK 发布指南

## 发布到 CocoaPods

### 1. 准备工作

1. 注册 CocoaPods 账号：
```bash
pod trunk register your-email@example.com 'Your Name'
```

2. 验证 podspec：
```bash
pod lib lint SyRtcSDK.podspec
```

### 2. 发布

```bash
pod trunk push SyRtcSDK.podspec
```

### 3. 使用

在 `Podfile` 中添加：
```ruby
pod 'SyRtcSDK', '~> 1.2.0'
```

## 发布到 Swift Package Manager

### 1. 创建 Git 仓库

```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/yourusername/sy-rtc-ios-sdk.git
git push -u origin main
```

### 2. 创建 Release Tag

```bash
git tag 1.2.0
git push origin 1.2.0
```

### 3. 在 Xcode 中使用

1. File → Add Packages
2. 输入：`https://github.com/yourusername/sy-rtc-ios-sdk`
3. 选择版本

## 构建 XCFramework

### 1. 在 Xcode 中创建 Framework 项目

1. File → New → Project
2. 选择 "Framework"
3. 项目名称：SyRtcSDK
4. Language: Swift

### 2. 添加源代码

将 `Sources/SyRtcSDK` 中的文件添加到项目

### 3. 配置构建设置

- Build Libraries for Distribution = YES
- Skip Install = NO

### 4. 构建 XCFramework

```bash
# 构建 iOS 设备版本
xcodebuild archive \
  -scheme SyRtcSDK \
  -archivePath build/ios.xcarchive \
  -sdk iphoneos \
  SKIP_INSTALL=NO

# 构建模拟器版本
xcodebuild archive \
  -scheme SyRtcSDK \
  -archivePath build/ios-sim.xcarchive \
  -sdk iphonesimulator \
  SKIP_INSTALL=NO

# 创建 XCFramework
xcodebuild -create-xcframework \
  -framework build/ios.xcarchive/Products/Library/Frameworks/SyRtcSDK.framework \
  -framework build/ios-sim.xcarchive/Products/Library/Frameworks/SyRtcSDK.framework \
  -output build/SyRtcSDK.xcframework
```

### 5. 分发 XCFramework

- 上传到 GitHub Releases
- 或提供下载链接


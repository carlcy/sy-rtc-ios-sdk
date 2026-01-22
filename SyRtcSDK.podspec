Pod::Spec.new do |s|
  s.name             = 'SyRtcSDK'
  s.version          = '1.0.6'
  s.summary          = 'SY RTC iOS SDK for audio communication'
  s.description      = <<-DESC
SY RTC iOS SDK provides real-time audio and video communication capabilities.
                       DESC
  s.homepage         = 'https://github.com/carlcy/sy-rtc-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'SY RTC Team' => 'support@sy-rtc.com' }
  s.source           = { :git => 'https://github.com/carlcy/sy-rtc-ios-sdk.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  s.source_files = 'Sources/SyRtcSDK/**/*.swift'
  s.frameworks = 'Foundation', 'AVFoundation'
  # WebRTC 依赖（CocoaPods，XCFramework：支持真机 + 模拟器）
  # 版本号对齐 Android 端 webrtc-sdk: 125.6422.07
  s.dependency 'WebRTC-SDK', '~> 125.6422.07'
  # 架构兼容性说明：
  # - 如果你在 Apple Silicon 上遇到 Simulator 架构问题，建议在业务 App 的 Podfile/Build Settings 里做 EXCLUDED_ARCHS 配置，
  #   而不是在 SDK podspec 中强制排除（避免出现“宿主与 pod 架构不一致”导致的编译失败）。
end

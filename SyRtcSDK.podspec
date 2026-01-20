Pod::Spec.new do |s|
  s.name             = 'SyRtcSDK'
  s.version          = '1.0.3'
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
  # WebRTC 依赖（CocoaPods）
  s.dependency 'GoogleWebRTC'
  # Apple Silicon 下 Simulator arm64 可能与 WebRTC.framework 的 slice 不匹配（导致链接失败）
  # 如需在 iOS Simulator 运行，可在 Podfile 中排除 arm64，或使用 Rosetta 跑 x86_64 Simulator。
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
end

Pod::Spec.new do |s|
  s.name             = 'SyRtcSDK'
  s.version          = '1.0.1'
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
end

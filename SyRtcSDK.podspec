Pod::Spec.new do |s|
  s.name             = 'SyRtcSDK'
  s.version          = '3.2.2'
  s.summary          = 'SY RTC iOS SDK for real-time audio and video.'
  s.description      = <<-DESC
SY RTC iOS SDK is the source distribution of the SY real-time audio and video engine.
Integrate it with CocoaPods by version (`pod 'SyRtcSDK', '~> 3.2.2'`) or with Swift Package Manager by git URL and version tag.
The pod ships Swift sources and depends on WebRTC-SDK; customers do not download or unzip an SDK framework.
                       DESC
  s.homepage         = 'https://github.com/carlcy/sy-rtc-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'SY RTC Team' => 'support@sy-rtc.com' }
  # tag 必须是 v{version}，与 SPM 的 v3.2.0 一致。先推 tag，再 pod trunk push。
  s.source           = { :git => 'https://github.com/carlcy/sy-rtc-ios-sdk.git', :tag => "v#{s.version}" }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/SyRtcSDK/**/*.swift'
  s.frameworks = 'Foundation', 'AVFoundation', 'UIKit', 'CoreImage', 'ReplayKit', 'CoreMedia', 'CoreVideo', 'Network'
  # 与 Android webrtc-sdk 125.6422.07、Package.swift binaryTarget 同一版本。固定到 .07：
  # 125.6422.09 改了 RTCPeerConnectionFactory 带 APM 的 init（多了 audioDeviceModuleType），录音取本端 PCM 依赖该 init。
  s.dependency 'WebRTC-SDK', '125.6422.07'
  s.dependency 'LiveKitClient', '~> 2.17'
end

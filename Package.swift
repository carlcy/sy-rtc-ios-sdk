// swift-tools-version: 5.9
import PackageDescription

// 源码分发（不是预编译 SyRtcSDK.xcframework）。
// 版本由 git tag 决定：打 `v3.2.2` 后，客户写 `.package(url:from: "3.2.2")`。
// WebRTC 与 CocoaPods 的 WebRTC-SDK 125.6422.07 使用同一份 xcframework zip，
// 避免再依赖另一套版本号（例如 stasel/WebRTC 141）导致 API 对不齐。
let package = Package(
    name: "SyRtcSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "SyRtcSDK",
            targets: ["SyRtcSDK"]
        ),
    ],
    dependencies: [
        // LiveKit SFU media plane (prefixed LiveKitWebRTC, no clash with WebRTC-SDK below).
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.17.0"),
    ],
    targets: [
        .target(
            name: "SyRtcSDK",
            dependencies: ["WebRTC", .product(name: "LiveKit", package: "client-sdk-swift")],
            path: "Sources/SyRtcSDK",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Network"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ReplayKit"),
                .linkedFramework("UIKit"),
            ]
        ),
        .testTarget(
            name: "SyRtcSDKTests",
            dependencies: ["SyRtcSDK"],
            path: "Tests/SyRtcSDKTests"
        ),
        .binaryTarget(
            name: "WebRTC",
            url: "https://github.com/webrtc-sdk/Specs/releases/download/125.6422.07/WebRTC.xcframework.zip",
            checksum: "827cc2f508c341367c9b0e4f6def46e5f6834251082047d5d1da5bc8fd379263"
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

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
        // WebRTC SPM 依赖（推荐）：这里使用官方镜像仓库
        .package(url: "https://github.com/webrtc-sdk/webrtc.git", from: "125.6422.07")
    ],
    targets: [
        .target(
            name: "SyRtcSDK",
            dependencies: [
                .product(name: "WebRTC", package: "webrtc")
            ],
            path: "Sources/SyRtcSDK"
        ),
        .testTarget(
            name: "SyRtcSDKTests",
            dependencies: ["SyRtcSDK"],
            path: "Tests/SyRtcSDKTests"
        ),
    ]
)


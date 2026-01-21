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
        // WebRTC SPM 依赖（二进制包，支持 SemVer tag）
        .package(url: "https://github.com/stasel/WebRTC.git", from: "141.0.0")
    ],
    targets: [
        .target(
            name: "SyRtcSDK",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
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


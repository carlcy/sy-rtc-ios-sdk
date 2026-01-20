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
    targets: [
        .target(
            name: "SyRtcSDK",
            dependencies: [
                .product(name: "WebRTC", package: "webrtc-swift")
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


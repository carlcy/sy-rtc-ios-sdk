import Foundation
import CoreVideo
import CoreMedia
import ReplayKit

/// 本机播放路由。只能主动切到扬声器或听筒；蓝牙和有线耳机由系统决定，通过 `onAudioRoutingChanged` 上报。
///
/// 数值不是 ZEGO `ZegoAudioRoute` 的原枚举序，见发布说明里的对照表。
public enum SyRtcAudioRoute: Int {
    case headset = 0
    case earpiece = 1
    case speaker = 3
    case bluetooth = 5
    case unknown = -1
}

/// 摄像头或自定义采集帧的处理钩子。返回要送进编码器的像素缓冲。
///
/// 这是本地前处理，不是云端美颜、转码或 SFU。
public typealias SyRtcVideoFrameProcessor = (_ pixelBuffer: CVPixelBuffer, _ rotationDegrees: Int) -> CVPixelBuffer

/// 进程内的 ReplayKit 帧入口。
///
/// Broadcast Upload Extension 与 App 不是同一个进程，在扩展里调用本类不会把画面送进 `SyRtcEngine`。
/// 应用内采集请用 `startScreenCapture`。扩展工程只保留脚手架，见 `BroadcastExtension/`。
public final class SyRtcReplayKitBridge {
    public static let shared = SyRtcReplayKitBridge()

    /// 仅在当前进程内触发。不要把它当成跨进程屏幕共享通道。
    public var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?

    private init() {}

    public func consumeVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        onVideoSampleBuffer?(sampleBuffer)
    }
}

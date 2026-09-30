import ReplayKit
import CoreMedia

/// Broadcast Upload Extension 脚手架。
///
/// 把这个文件放进一个 Broadcast Upload Extension target 后，系统会在用户开始广播时回调这里。
/// 扩展进程和主 App 进程互相隔离：这里拿到的 `CMSampleBuffer` 到不了 `SyRtcEngine`，
/// 本仓库也不假装已经做了 App Group / socket 跨进程传帧。
///
/// 应用内屏幕共享（同一个进程）用 `SyRtcEngine.startScreenCapture`，由 `RPScreenRecorder` 直接送进 WebRTC。
class SampleHandler: RPBroadcastSampleHandler {
    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    }

    override func broadcastPaused() {
    }

    override func broadcastResumed() {
    }

    override func broadcastFinished() {
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            // 帧只存在于扩展进程。要送到房间里，需要你自己实现跨进程通道，再在主 App 调用
            // `SyRtcEngine.pushScreenSampleBuffer`。SDK 不提供这条通道。
            break
        case .audioApp, .audioMic:
            break
        @unknown default:
            break
        }
    }
}

import Foundation

/// 视频首帧与分辨率变化判定。每条视频轨一个实例，与 Android `VideoFrameTracker` 规则相同：
/// 第一帧 → `first` 且 `sizeChanged`；之后宽、高或旋转与上一帧不同 → `sizeChanged`。
/// 宽高为解码后缓冲区尺寸，旋转为 0/90/180/270。线程安全（WebRTC 在渲染线程回调）。
final class SyRtcVideoFrameTracker {
    struct Change: Equatable {
        let first: Bool
        let sizeChanged: Bool
    }

    private let lock = NSLock()
    private var seen = false
    private var width = 0
    private var height = 0
    private var rotation = 0

    func onFrame(width: Int, height: Int, rotation: Int) -> Change {
        lock.lock()
        defer { lock.unlock() }
        if !seen {
            seen = true
            self.width = width; self.height = height; self.rotation = rotation
            return Change(first: true, sizeChanged: true)
        }
        let changed = width != self.width || height != self.height || rotation != self.rotation
        if changed {
            self.width = width; self.height = height; self.rotation = rotation
        }
        return Change(first: false, sizeChanged: changed)
    }
}

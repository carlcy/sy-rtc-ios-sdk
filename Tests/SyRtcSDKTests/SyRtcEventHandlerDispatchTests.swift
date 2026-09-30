import XCTest
@testable import SyRtcSDK

/// 可选回调必须是协议要求：经 `SyRtcEventHandler` 存在类型调用时要派发到实现方。
final class SyRtcEventHandlerDispatchTests: XCTestCase {
    private final class Recorder: SyRtcEventHandler {
        var calls: [String] = []
        func onUserJoined(uid: String, elapsed: Int) {}
        func onUserOffline(uid: String, reason: String) {}
        func onVolumeIndication(speakers: [SyVolumeInfo]) {}
        func onJoinChannelSuccess(channelId: String, uid: String, elapsed: Int) { calls.append("join") }
        func onNetworkQuality(uid: String, txQuality: String, rxQuality: String) { calls.append("quality") }
        func onConnectionStateChanged(state: String, reason: String) { calls.append("state:\(state)") }
        func onUserMuteVideo(uid: String, muted: Bool) { calls.append("muteVideo") }
        func onRtcStats(stats: [String: Any]) { calls.append("stats") }
        func onSeiMessage(uid: String, streamId: Int, data: Data) { calls.append("sei") }
    }

    func testOptionalCallbacksReachImplementer() {
        let recorder = Recorder()
        let handler: SyRtcEventHandler = recorder
        handler.onJoinChannelSuccess(channelId: "c", uid: "u", elapsed: 0)
        handler.onNetworkQuality(uid: "u", txQuality: "good", rxQuality: "good")
        handler.onConnectionStateChanged(state: "connected", reason: "join_success")
        handler.onUserMuteVideo(uid: "u", muted: true)
        handler.onRtcStats(stats: [:])
        handler.onSeiMessage(uid: "u", streamId: 1, data: Data())
        handler.onKicked(channelId: "c", reason: "x") // 未实现：走默认空实现
        XCTAssertEqual(recorder.calls, ["join", "quality", "state:connected", "muteVideo", "stats", "sei"])
    }
}

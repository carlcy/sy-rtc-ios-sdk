import XCTest
@testable import SyRtcSDK

/// Manual E2E against a real backend + LiveKit node. Skipped unless the env has
/// (xcodebuild forwards TEST_RUNNER_-prefixed vars into the simulator):
///   TEST_RUNNER_SFU_META        base64 of the `POST /api/server/rtc/token` meta=true response
///   TEST_RUNNER_SIGNALING_URL   e.g. ws://127.0.0.1:8080/ws/signaling
///   TEST_RUNNER_EXPECT_REMOTE   uid of a peer already in the LiveKit room
/// The host side kicks this uid via the backend (signaling + LiveKit removal) while the test waits.
final class SyLiveKitE2ETests: XCTestCase {
    private final class Handler: SyRtcEventHandler {
        var joined: XCTestExpectation?
        var sawRemote: XCTestExpectation?
        var kicked: XCTestExpectation?
        var expectRemote = ""
        var kicks = 0
        var errors: [String] = []
        var qualities: [String] = []
        func onJoinChannelSuccess(channelId: String, uid: String, elapsed: Int) { joined?.fulfill(); joined = nil }
        func onVolumeIndication(speakers: [SyVolumeInfo]) {
            if !expectRemote.isEmpty, speakers.contains(where: { $0.uid == expectRemote }) { sawRemote?.fulfill(); sawRemote = nil }
        }
        func onNetworkQuality(uid: String, txQuality: String, rxQuality: String) { qualities.append("\(uid)=\(txQuality)") }
        func onKicked(channelId: String, reason: String) { kicks += 1; NSLog("LKE2E KICKED \(channelId) \(reason)"); kicked?.fulfill(); kicked = nil }
        func onError(code: Int, message: String) { errors.append("\(code):\(message)") }
        func onUserJoined(uid: String, elapsed: Int) {}
        func onUserOffline(uid: String, reason: String) {}
        func onStreamMessage(uid: String, streamId: Int, data: Data) {}
        func onSeiMessage(uid: String, streamId: Int, data: Data) {}
        func onStreamMessageError(uid: String, streamId: Int, code: Int, missed: Int, cached: Int) {}
        func onChannelMessage(uid: String, message: String) {}
    }

    func testJoinSeesRemoteAndKickFiresOnce() throws {
        let env = ProcessInfo.processInfo.environment
        guard let b64 = env["SFU_META"], !b64.isEmpty,
              let raw = Data(base64Encoded: b64), let meta = String(data: raw, encoding: .utf8) else {
            throw XCTSkip("SFU_META not provided; skipping LiveKit E2E")
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let data = (root["data"] as? [String: Any]) ?? root
        let channel = try XCTUnwrap(data["channelId"] as? String)
        let uid = try XCTUnwrap(data["uid"] as? String)
        let h = Handler()
        h.expectRemote = env["EXPECT_REMOTE"] ?? ""
        let joinedExp = expectation(description: "joined")
        let remoteExp = h.expectRemote.isEmpty ? nil : expectation(description: "remote via LiveKit")
        let kickedExp = expectation(description: "kicked")
        h.joined = joinedExp; h.sawRemote = remoteExp; h.kicked = kickedExp

        let engine = SyRtcEngine.shared
        engine.initialize(appId: try XCTUnwrap(data["appId"] as? String))
        if let s = env["SIGNALING_URL"] { engine.setSignalingServerUrl(s) }
        engine.setEventHandler(h)
        engine.enableAudioVolumeIndication(interval: 200, smooth: 3, reportVad: false)
        engine.join(channelId: channel, uid: uid, token: meta)

        wait(for: [joinedExp], timeout: 20)
        NSLog("LKE2E JOINED \(channel) as \(uid)")
        if let e = remoteExp { wait(for: [e], timeout: 20); NSLog("LKE2E SAW_REMOTE \(h.expectRemote)") }
        wait(for: [kickedExp], timeout: 90)
        let settle = expectation(description: "settle"); DispatchQueue.main.asyncAfter(deadline: .now() + 3) { settle.fulfill() }
        wait(for: [settle], timeout: 5)
        NSLog("LKE2E DONE kicks=\(h.kicks) quality=\(h.qualities.prefix(5)) errors=\(h.errors)")
        XCTAssertEqual(h.kicks, 1, "onKicked must fire exactly once")
        engine.leave()
    }
}

import XCTest
@testable import SyRtcSDK

final class SyJoinCredentialsTests: XCTestCase {
    private let wired = #"{"code":0,"data":{"token":"sy.tok","canPublish":true,"mediaWired":true,"sfuKind":"livekit","sfuUrl":"wss://lk.example","sfuToken":"lk.tok","sfuRoom":"APP__ch","sfuIdentity":"u1","sfuExpireAt":1791596481}}"#

    func testPlainToken() {
        let c = SyJoinCredentials.parse("  abc.def  ")
        XCTAssertEqual(c.token, "abc.def"); XCTAssertNil(c.sfu); XCTAssertNil(c.canPublish)
    }
    func testEnvelopeWired() {
        let c = SyJoinCredentials.parse(wired)
        XCTAssertEqual(c.token, "sy.tok")
        XCTAssertEqual(c.sfu, SySfuJoinInfo(url: "wss://lk.example", token: "lk.tok", room: "APP__ch", identity: "u1", expireAt: 1791596481))
        XCTAssertEqual(c.canPublish, true)
    }
    func testDataObjectWithoutEnvelope() {
        let c = SyJoinCredentials.parse(#"{"token":"t","mediaWired":true,"sfuUrl":"ws://x","sfuToken":"s"}"#)
        XCTAssertEqual(c.sfu?.url, "ws://x")
    }
    func testNotWiredFallsBackToMesh() {
        XCTAssertNil(SyJoinCredentials.parse(#"{"token":"t","mediaWired":false,"sfuUrl":"ws://x","sfuToken":"s"}"#).sfu)
        XCTAssertNil(SyJoinCredentials.parse(#"{"token":"t","mediaWired":true,"sfuUrl":"","sfuToken":"s"}"#).sfu)
        XCTAssertNil(SyJoinCredentials.parse(#"{"token":"t","mediaWired":true,"sfuUrl":"ws://x","sfuToken":"s","sfuKind":"mediasoup"}"#).sfu)
    }
    func testBadJsonOrMissingTokenKeepsInput() {
        XCTAssertEqual(SyJoinCredentials.parse("{not json").token, "{not json")
        let c = SyJoinCredentials.parse(#"{"code":0,"data":{}}"#)
        XCTAssertNil(c.sfu); XCTAssertEqual(c.token, #"{"code":0,"data":{}}"#)
    }
}

private final class Sink: SySfuSink {
    var log: [String] = []
    func sfuRemoteAudioMuted(uid: String, muted: Bool) { log.append("ra:\(uid):\(muted)") }
    func sfuRemoteVideoMuted(uid: String, muted: Bool) { log.append("rv:\(uid):\(muted)") }
    func sfuServerMutedLocalAudio(_ muted: Bool) { log.append("sm:\(muted)") }
    func sfuKicked(reason: String) { log.append("kick:\(reason)") }
    func sfuMediaLost(detail: String) { log.append("lost:\(detail)") }
    func sfuNetworkQuality(uid: String, quality: String) { log.append("q:\(uid):\(quality)") }
    func sfuLevels(local: Double?, remote: [String: Double]) { log.append("lv:\(local ?? -1):\(remote.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))") }
    func sfuReconnecting() { log.append("rc") }
    func sfuReconnected() { log.append("rcd") }
}

final class SySfuEventMapperTests: XCTestCase {
    func testDisconnectReasons() {
        let s = Sink(); let m = SySfuEventMapper(sink: s)
        m.on(.disconnected(.client, detail: ""))
        m.on(.disconnected(.removed, detail: ""))
        m.on(.disconnected(.roomDeleted, detail: ""))
        m.on(.disconnected(.duplicateIdentity, detail: ""))
        m.on(.disconnected(.other, detail: ""))
        m.on(.disconnected(.other, detail: "ice"))
        XCTAssertEqual(s.log, ["kick:removed by server", "kick:room deleted", "kick:duplicate identity", "lost:sfu disconnected", "lost:ice"])
    }
    func testServerMuteIsStickyAndAppMuteIgnored() {
        let s = Sink(); let m = SySfuEventMapper(sink: s)
        m.localAudioMuteRequested = true
        m.on(.trackMuted(uid: "me", isLocal: true, audio: true, muted: true)) // app's own mute
        XCTAssertEqual(s.log, [])
        m.localAudioMuteRequested = false
        m.on(.trackMuted(uid: "me", isLocal: true, audio: true, muted: false))
        m.on(.trackMuted(uid: "me", isLocal: true, audio: true, muted: true))  // server
        m.on(.trackMuted(uid: "me", isLocal: true, audio: true, muted: true))  // duplicate
        XCTAssertTrue(m.isServerMuted)
        m.on(.trackMuted(uid: "me", isLocal: true, audio: true, muted: false))
        XCTAssertEqual(s.log, ["sm:true", "sm:false"])
    }
    func testRemoteMuteAndLocalVideoIgnored() {
        let s = Sink(); let m = SySfuEventMapper(sink: s)
        m.on(.trackMuted(uid: "u2", isLocal: false, audio: true, muted: true))
        m.on(.trackMuted(uid: "u2", isLocal: false, audio: false, muted: false))
        m.on(.trackMuted(uid: "me", isLocal: true, audio: false, muted: true))
        XCTAssertEqual(s.log, ["ra:u2:true", "rv:u2:false"])
    }
    func testQualityLevelsReconnect() {
        let s = Sink(); let m = SySfuEventMapper(sink: s)
        m.on(.quality(uid: "u1", .excellent)); m.on(.quality(uid: "u2", .lost)); m.on(.quality(uid: "u3", .unknown))
        m.on(.levels(local: 1.5, remote: ["b": 0.5, "a": -1]))
        m.on(.reconnecting); m.on(.reconnected)
        XCTAssertEqual(s.log, ["q:u1:excellent", "q:u2:down", "q:u3:unknown", "lv:1.0:a=0.0,b=0.5", "rc", "rcd"])
    }
    func testQualityWithEmptyUidIsDropped() {
        let s = Sink(); let m = SySfuEventMapper(sink: s)
        m.on(.quality(uid: "", .unknown)); m.on(.quality(uid: "u1", .good))
        XCTAssertEqual(s.log, ["q:u1:good"])
    }
    func testOnceFlag() {
        let f = SyOnceFlag()
        XCTAssertTrue(f.tryFire()); XCTAssertFalse(f.tryFire()); f.reset(); XCTAssertTrue(f.tryFire())
    }
}

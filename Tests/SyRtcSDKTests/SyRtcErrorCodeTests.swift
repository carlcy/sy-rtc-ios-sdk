import XCTest
@testable import SyRtcSDK

final class SyRtcErrorCodeTests: XCTestCase {
    private func b64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func testCodesMatchAndroidAndFlutter() {
        XCTAssertEqual(SyRtcErrorCode.invalidArgument, 1000)
        XCTAssertEqual(SyRtcErrorCode.signaling, 1002)
        XCTAssertEqual(SyRtcErrorCode.reconnectFailed, 1003)
        XCTAssertEqual(SyRtcErrorCode.kicked, 1004)
        XCTAssertEqual(SyRtcErrorCode.camera, 1005)
        XCTAssertEqual(SyRtcErrorCode.screenShare, 1006)
        XCTAssertEqual(SyRtcErrorCode.customCapture, 1007)
        XCTAssertEqual(SyRtcErrorCode.audioRoute, 1009)
        XCTAssertEqual(SyRtcErrorCode.forbidden, 403)
        XCTAssertEqual(SyRtcErrorCode.credentialSuspended, 4031)
        XCTAssertEqual(SyRtcErrorCode.credentialRevoked, 4032)
        XCTAssertEqual(SyRtcErrorCode.credentialExpired, 4033)
    }

    func testSignalingFramesMapToCodes() {
        XCTAssertEqual(SyRtcErrorCode.forKicked(["reason": "spam"]), 1004)
        XCTAssertEqual(SyRtcErrorCode.forKicked(["reason": "revoked", "code": 4032]), 4032)
        XCTAssertEqual(SyRtcErrorCode.forKicked(["code": NSNumber(value: 403)]), 1004)
        XCTAssertEqual(SyRtcErrorCode.forSignalingError(["message": "x"]), 1002)
        XCTAssertEqual(SyRtcErrorCode.forSignalingError(["code": 400]), 1002)
        XCTAssertEqual(SyRtcErrorCode.forSignalingError(["code": 403]), 403)
        XCTAssertEqual(SyRtcErrorCode.forSignalingError(["code": 4031.0]), 4031)
        XCTAssertEqual(SyRtcErrorCode.signalingErrorMessage(["message": "房间已锁定"]), "房间已锁定")
        XCTAssertEqual(SyRtcErrorCode.signalingErrorMessage(["error": "old"]), "old")
        XCTAssertEqual(SyRtcErrorCode.signalingErrorMessage([:]), "信令错误")
    }

    func testParsesServerTokenExpireAt() {
        let payload = #"{"appId":"a","channelId":"c","uid":"u","expireAt":1790000000,"tierWeight":1.5,"canPublish":true}"#
        XCTAssertEqual(SyRtcTokenExpiry.expireAt(b64url(payload) + ".c2ln"), 1790000000)
    }

    func testParsesJwtExp() {
        let jwt = b64url(#"{"alg":"HS256"}"#) + "." + b64url(#"{"sub":"u","exp":1700000123}"#) + ".sig"
        XCTAssertEqual(SyRtcTokenExpiry.expireAt(jwt), 1700000123)
    }

    func testRejectsTokensWithoutExpiry() {
        XCTAssertNil(SyRtcTokenExpiry.expireAt("plain-token"))
        XCTAssertNil(SyRtcTokenExpiry.expireAt(b64url(#"{"expireAt":0}"#) + ".s"))
        XCTAssertNil(SyRtcTokenExpiry.expireAt("!!!.s"))
    }

    func testWarnsThirtySecondsBeforeExpiry() {
        let now: TimeInterval = 1_000_000
        XCTAssertEqual(SyRtcTokenExpiry.delays(expireAt: now + 100, now: now).warn, 70)
        XCTAssertEqual(SyRtcTokenExpiry.delays(expireAt: now + 100, now: now).expire, 100)
        XCTAssertEqual(SyRtcTokenExpiry.delays(expireAt: now + 10, now: now).warn, 0)
        XCTAssertEqual(SyRtcTokenExpiry.delays(expireAt: now - 5, now: now).expire, 0)
    }
}

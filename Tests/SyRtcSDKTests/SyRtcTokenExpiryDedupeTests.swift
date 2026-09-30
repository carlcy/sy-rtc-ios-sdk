import XCTest
@testable import SyRtcSDK

/// 与 Android TokenExpiryDedupeTest 相同的期望。
final class SyRtcTokenExpiryDedupeTests: XCTestCase {
    func testLocalAndServerFireOncePerToken() {
        let d = SyRtcTokenExpiryDedupe()
        d.reset(currentExpireAt: 1000)
        XCTAssertTrue(d.shouldFire(.willExpire))
        XCTAssertFalse(d.shouldFire(.willExpire, eventExpireAt: 1000))
        XCTAssertTrue(d.shouldFire(.expired, eventExpireAt: 1000))
        XCTAssertFalse(d.shouldFire(.expired))
        XCTAssertFalse(d.shouldFire(.willExpire))
    }

    func testRenewResetsAndStalePushIgnored() {
        let d = SyRtcTokenExpiryDedupe()
        d.reset(currentExpireAt: 1000)
        XCTAssertTrue(d.shouldFire(.expired))
        d.reset(currentExpireAt: 2000)
        XCTAssertFalse(d.shouldFire(.willExpire, eventExpireAt: 1000))
        XCTAssertTrue(d.shouldFire(.willExpire, eventExpireAt: 2000))
        XCTAssertTrue(d.shouldFire(.expired))
    }

    func testTokenWithoutExpiryStillDedupesServerPush() {
        let d = SyRtcTokenExpiryDedupe()
        d.reset(currentExpireAt: nil)
        XCTAssertTrue(d.shouldFire(.willExpire, eventExpireAt: 1500))
        XCTAssertFalse(d.shouldFire(.willExpire, eventExpireAt: 1500))
    }

    func testParsesExpireAtFromPush() {
        XCTAssertEqual(SyRtcTokenExpiryDedupe.expireAt(of: ["expireAt": 1_790_000_000]), 1_790_000_000)
        XCTAssertEqual(SyRtcTokenExpiryDedupe.expireAt(of: ["expireAt": "42"]), 42)
        XCTAssertNil(SyRtcTokenExpiryDedupe.expireAt(of: ["expireAt": 0]))
        XCTAssertNil(SyRtcTokenExpiryDedupe.expireAt(of: [:]))
    }
}

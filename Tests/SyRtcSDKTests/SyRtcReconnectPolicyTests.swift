import XCTest
@testable import SyRtcSDK

/// 与 Android ReconnectPolicyTest 相同的期望。
final class SyRtcReconnectPolicyTests: XCTestCase {
    func testBackoff() {
        XCTAssertEqual((1...5).map { SyRtcReconnectPolicy.delayMs(attempt: $0) }, [1000, 2000, 4000, 8000, 16000])
        XCTAssertEqual(SyRtcReconnectPolicy.delayMs(attempt: 9), 16000)
        XCTAssertEqual(SyRtcReconnectPolicy.delayMs(attempt: 0), 1000)
        XCTAssertEqual(SyRtcReconnectPolicy.maxAttempts, 5)
    }
}

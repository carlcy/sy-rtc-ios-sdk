import XCTest
@testable import SyRtcSDK

/// 与 Android ClientSignalsTest.networkQualityThresholdsMatchIos 同一张表。
final class SyRtcNetworkQualityTests: XCTestCase {
    func testThresholdsMatchAndroid() {
        let cases: [(Double?, Double?, String)] = [
            (20, 0, "excellent"),
            (99, 0.009, "excellent"),
            (100, 0, "good"),
            (20, 0.01, "good"),
            (199, 0.029, "good"),
            (200, 0, "poor"),
            (20, 0.03, "poor"),
            (400, 0, "bad"),
            (20, 0.08, "bad"),
            (800, 0, "down"),
            (20, 0.20, "down"),
            (nil, 0.5, "down"),
            (150, nil, "good"),
            (nil, nil, "unknown"),
        ]
        for (rtt, loss, expected) in cases {
            XCTAssertEqual(SyRtcNetworkQuality.level(rttMs: rtt, packetLossRatio: loss), expected, "rtt=\(String(describing: rtt)) loss=\(String(describing: loss))")
        }
    }

    func testRankMatchesAndroid() {
        XCTAssertEqual(["unknown", "excellent", "good", "poor", "bad", "down"].map(SyRtcNetworkQuality.rank), [0, 1, 2, 3, 4, 5])
    }
}

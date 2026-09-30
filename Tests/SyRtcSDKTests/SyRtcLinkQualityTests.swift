import XCTest
@testable import SyRtcSDK

/// 与 Android LinkQualityTest 相同的期望。
final class SyRtcLinkQualityTests: XCTestCase {
    func testTxUsesRttAndOutboundLoss() {
        XCTAssertEqual(SyRtcLinkQuality.tx(rttMs: 50, outboundLossRate: 0), "excellent")
        XCTAssertEqual(SyRtcLinkQuality.tx(rttMs: 50, outboundLossRate: 0.05), "poor")
        XCTAssertEqual(SyRtcLinkQuality.tx(rttMs: 450, outboundLossRate: 0), "bad")
        XCTAssertEqual(SyRtcLinkQuality.tx(rttMs: 150, outboundLossRate: nil), "good")
        XCTAssertEqual(SyRtcLinkQuality.tx(rttMs: nil, outboundLossRate: nil), "unknown")
    }

    func testRxUsesInboundLossAndJitter() {
        XCTAssertEqual(SyRtcLinkQuality.rx(inboundLossRate: 0, jitterMs: 10), "excellent")
        XCTAssertEqual(SyRtcLinkQuality.rx(inboundLossRate: 0, jitterMs: 40), "good")
        XCTAssertEqual(SyRtcLinkQuality.rx(inboundLossRate: 0, jitterMs: 60), "poor")
        XCTAssertEqual(SyRtcLinkQuality.rx(inboundLossRate: 0.1, jitterMs: 10), "bad")
        XCTAssertEqual(SyRtcLinkQuality.rx(inboundLossRate: nil, jitterMs: 250), "down")
        XCTAssertEqual(SyRtcLinkQuality.rx(inboundLossRate: nil, jitterMs: nil), "unknown")
    }

    func testIntervalLossUsesDeltas() {
        XCTAssertEqual(SyRtcLinkQuality.intervalLossRate(prevLost: nil, prevReceived: nil, lost: 10, received: 90)!, 0.1, accuracy: 1e-9)
        XCTAssertEqual(SyRtcLinkQuality.intervalLossRate(prevLost: 10, prevReceived: 90, lost: 20, received: 100)!, 0.5, accuracy: 1e-9)
        XCTAssertNil(SyRtcLinkQuality.intervalLossRate(prevLost: 10, prevReceived: 90, lost: 10, received: 90))
        XCTAssertEqual(SyRtcLinkQuality.intervalLossRate(prevLost: 10, prevReceived: 90, lost: 0, received: 50)!, 0, accuracy: 1e-9)
        XCTAssertNil(SyRtcLinkQuality.intervalLossRate(prevLost: nil, prevReceived: nil, lost: nil, received: 5))
    }

    func testParserSplitsUplinkAndDownlink() {
        let s = SyRtcStatsSample.parse([
            ("remote-inbound-rtp", ["fractionLost": 0.04, "roundTripTime": 0.12], false),
            ("remote-inbound-rtp", ["fractionLost": 0.02], false),
            ("inbound-rtp", ["packetsLost": 3, "packetsReceived": 97, "jitter": 0.02], true),
            ("inbound-rtp", ["packetsLost": 1, "packetsReceived": 99, "jitter": 0.045], false),
        ])
        XCTAssertEqual(s.outboundLossRate!, 0.04, accuracy: 1e-9)
        XCTAssertEqual(s.inboundPacketsLost, 4)
        XCTAssertEqual(s.inboundPacketsReceived, 196)
        XCTAssertEqual(s.jitterMs!, 45, accuracy: 1e-9)
        XCTAssertEqual(s.rttMs!, 120, accuracy: 1e-9)
    }
}

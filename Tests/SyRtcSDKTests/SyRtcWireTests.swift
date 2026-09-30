import XCTest
@testable import SyRtcSDK

/// 与 Android WireProtocolTest 对应，保证两端线格式一致。
final class SyRtcWireTests: XCTestCase {
    func testStreamExtraPrefix() {
        XCTAssertEqual(SyRtcWire.parseChannelMessage("sy-extra:座位:1"), .streamExtra("座位:1"))
        XCTAssertEqual(SyRtcWire.parseChannelMessage("sy-extra:"), .streamExtra(""))
        XCTAssertEqual(SyRtcWire.parseChannelMessage("hello"), .plain("hello"))
        XCTAssertEqual(SyRtcWire.maxStreamExtraBytes, 1024)
    }

    func testLegacyAndroidEnvelopes() {
        XCTAssertEqual(SyRtcWire.parseChannelMessage(#"{"type":"stream-extra","uid":"u1","extra":"x"}"#), .streamExtra("x"))
        XCTAssertEqual(SyRtcWire.parseChannelMessage(#"{"type":"client-mute","uid":"u1","media":"video","muted":true}"#),
                       .legacyMute(media: "video", muted: true))
        let other = #"{"type":"chat","text":"hi"}"#
        XCTAssertEqual(SyRtcWire.parseChannelMessage(other), .plain(other))
        XCTAssertEqual(SyRtcWire.parseChannelMessage("{bad"), .plain("{bad"))
    }

    func testSeiRoundTrip() {
        let payload = Data([1, 2, 3])
        let wire = SyRtcWire.wrapSei(payload)
        XCTAssertEqual(Array(wire.prefix(5)), Array("SYSEI".utf8))
        XCTAssertEqual(SyRtcWire.unwrapSei(wire), payload)
        XCTAssertEqual(SyRtcWire.unwrapSei(SyRtcWire.wrapSei(Data())), Data())
        XCTAssertNil(SyRtcWire.unwrapSei(Data("SYSE".utf8)))
        XCTAssertNil(SyRtcWire.unwrapSei(Data("hello world".utf8)))
    }
}

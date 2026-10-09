import XCTest
import AVFoundation
@testable import SyRtcSDK

final class SyRtcAudioRoutingTests: XCTestCase {
    func testRouteFromOutputs() {
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.builtInSpeaker]), .speaker)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.builtInReceiver]), .earpiece)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.headphones]), .headset)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.usbAudio]), .headset)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.bluetoothHFP]), .bluetooth)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.bluetoothA2DP]), .bluetooth)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.bluetoothLE]), .bluetooth)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: [.HDMI]), .unknown)
        XCTAssertEqual(SyRtcAudioRouting.route(outputs: []), .unknown)
    }

    func testAvailability() {
        XCTAssertEqual(SyRtcAudioRouting.available(inputs: [.builtInMic], outputs: [.builtInReceiver], hasEarpiece: true),
                       [.speaker, .earpiece])
        XCTAssertEqual(SyRtcAudioRouting.available(inputs: [.builtInMic], outputs: [.builtInSpeaker], hasEarpiece: false),
                       [.speaker])
        // Bluetooth HFP headset shows up as an input even while playing on the speaker.
        XCTAssertEqual(SyRtcAudioRouting.available(inputs: [.builtInMic, .bluetoothHFP], outputs: [.builtInSpeaker], hasEarpiece: true),
                       [.speaker, .earpiece, .bluetooth])
        // Wired headphones without a mic only show up as the current output.
        XCTAssertEqual(SyRtcAudioRouting.available(inputs: [.builtInMic], outputs: [.headphones], hasEarpiece: true),
                       [.speaker, .earpiece, .headset])
        XCTAssertEqual(SyRtcAudioRouting.available(inputs: [.headsetMic, .bluetoothHFP], outputs: [.headphones], hasEarpiece: true),
                       [.speaker, .earpiece, .headset, .bluetooth])
    }

    func testPreferredInput() {
        let inputs: [AVAudioSession.Port] = [.builtInMic, .headsetMic, .bluetoothHFP]
        XCTAssertEqual(SyRtcAudioRouting.preferredInput(for: .bluetooth, inputs: inputs), .bluetoothHFP)
        XCTAssertEqual(SyRtcAudioRouting.preferredInput(for: .headset, inputs: inputs), .headsetMic)
        XCTAssertEqual(SyRtcAudioRouting.preferredInput(for: .earpiece, inputs: inputs), .builtInMic)
        XCTAssertNil(SyRtcAudioRouting.preferredInput(for: .headset, inputs: [.builtInMic]))
        XCTAssertNil(SyRtcAudioRouting.preferredInput(for: .unknown, inputs: inputs))
    }

    func testDeviceIdsRoundTrip() {
        for r in [SyRtcAudioRoute.speaker, .earpiece, .headset, .bluetooth] {
            XCTAssertEqual(SyRtcAudioRouting.route(deviceId: SyRtcAudioRouting.deviceId(r)!), r)
        }
        XCTAssertNil(SyRtcAudioRouting.deviceId(.unknown))
        XCTAssertNil(SyRtcAudioRouting.route(deviceId: "default"))
    }

    func testDeduperPublishesOnlyChanges() {
        let d = SyRtcAudioRouteDeduper()
        XCTAssertTrue(d.shouldPublish(.speaker))
        XCTAssertFalse(d.shouldPublish(.speaker))
        XCTAssertTrue(d.shouldPublish(.bluetooth))
        XCTAssertTrue(d.shouldPublish(.speaker))
        d.reset()
        XCTAssertTrue(d.shouldPublish(.speaker))
    }
}

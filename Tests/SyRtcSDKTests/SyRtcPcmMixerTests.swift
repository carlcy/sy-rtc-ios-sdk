import XCTest
import AVFoundation
import WebRTC
@testable import SyRtcSDK

/// 与 Android CallAudioMixerTest 相同的期望。
final class SyRtcPcmMixerTests: XCTestCase {
    func testStereoDownmixAndResample() {
        XCTAssertEqual(SyRtcPcmConvert.toMono([1000, 3000, -1000, -3000], channels: 2), [2000, -2000])
        XCTAssertEqual(SyRtcPcmConvert.resample([Int16](repeating: 0, count: 960), from: 48000, to: 24000).count, 480)
        XCTAssertEqual(SyRtcPcmConvert.resample([0, 100], from: 2, to: 3), [0, 66, 100])
    }

    func testMixesSumsClipsAndPadsMissingSource() {
        let m = SyRtcPcmMixer(maxBufferedSamples: 100)
        m.push("local", [100, 200, 30000])
        m.push("u2", [1, 2, 30000, 7])
        XCTAssertEqual(m.mix(3), [101, 202, Int16.max])
        XCTAssertEqual(m.mix(2), [7, 0])
    }

    func testBoundedBufferDropsOldest() {
        let m = SyRtcPcmMixer(maxBufferedSamples: 4)
        m.push("a", [1, 2, 3])
        m.push("a", [4, 5, 6])
        XCTAssertEqual(m.bufferedSamples("a"), 4)
        XCTAssertEqual(m.mix(4), [3, 4, 5, 6])
        m.push("a", (0..<10).map { Int16($0) })
        XCTAssertEqual(m.mix(4), [6, 7, 8, 9])
    }

    func testFormats() {
        XCTAssertEqual(SyRtcRecordingFormat.from(codec: "aacLc"), .aacM4a)
        XCTAssertEqual(SyRtcRecordingFormat.from(codec: "WAV"), .wav)
        XCTAssertNil(SyRtcRecordingFormat.from(codec: "mp3"))
    }

    func testRecorderWritesWavFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sy-rec-\(UUID().uuidString).wav")
        let rec = try SyRtcCallAudioRecorder(url: url, format: .wav, sampleRate: 16000, bitrate: 0)
        rec.start()
        rec.push(SyRtcCallAudioRecorder.localSource, mono: [Int16](repeating: 1000, count: 4800), sourceRate: 48000)
        Thread.sleep(forTimeInterval: 0.2)
        rec.stop()
        let f = try AVAudioFile(forReading: url)
        XCTAssertEqual(f.fileFormat.sampleRate, 16000)
        XCTAssertGreaterThan(f.length, 1000)
        try? FileManager.default.removeItem(at: url)
    }

    /// 默认 init + delegate 能建出工厂（录音取本端 PCM 所用的 APM 挂法）。
    func testFactoryWithCaptureTapApm() {
        let tap = SyRtcCaptureAudioTap()
        let apm = RTCDefaultAudioProcessingModule()
        apm.capturePostProcessingDelegate = tap
        XCTAssertTrue(apm.capturePostProcessingDelegate === tap)
        let factory = RTCPeerConnectionFactory(bypassVoiceProcessing: false,
                                               encoderFactory: RTCDefaultVideoEncoderFactory(),
                                               decoderFactory: RTCDefaultVideoDecoderFactory(),
                                               audioProcessingModule: apm)
        XCTAssertNotNil(factory.audioSource(with: nil))
    }
}

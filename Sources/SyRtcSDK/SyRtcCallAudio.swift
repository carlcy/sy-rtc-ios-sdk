import Foundation
import AVFoundation
import WebRTC

/// 通话录音的 PCM 处理。与 Android `CallAudioMixer.kt` 规则相同：
/// - 每个声源（本端采集、每个远端）一条队列，先转单声道、重采样到录音采样率再入队；
/// - 混音按真实时间取样：每个声源取 n 个样本（不足补 0），相加后限幅到 16 bit；
/// - 单个声源最多缓存 `maxBufferedSamples` 个样本，超出丢最旧的。
enum SyRtcPcmConvert {
    /// 交错 Int16 → 单声道（各声道取平均）。
    static func toMono(_ interleaved: [Int16], channels: Int) -> [Int16] {
        let ch = max(1, channels)
        if ch == 1 { return interleaved }
        let frames = interleaved.count / ch
        var out = [Int16](repeating: 0, count: frames)
        for f in 0..<frames {
            var sum = 0
            for c in 0..<ch { sum += Int(interleaved[f * ch + c]) }
            out[f] = Int16(sum / ch)
        }
        return out
    }

    /// 线性插值重采样。
    static func resample(_ src: [Int16], from fromRate: Int, to toRate: Int) -> [Int16] {
        if fromRate <= 0 || toRate <= 0 || fromRate == toRate || src.isEmpty { return src }
        let outLen = max(1, src.count * toRate / fromRate)
        let step = Double(fromRate) / Double(toRate)
        var out = [Int16](repeating: 0, count: outLen)
        for i in 0..<outLen {
            let pos = Double(i) * step
            let i0 = min(Int(pos), src.count - 1)
            let i1 = min(i0 + 1, src.count - 1)
            let frac = pos - Double(i0)
            out[i] = Int16(Double(src[i0]) + Double(Int(src[i1]) - Int(src[i0])) * frac)
        }
        return out
    }

    /// Float（-1…1）→ Int16，限幅。
    static func floatToInt16(_ v: Float, scale: Float = 32767) -> Int16 {
        let x = v * scale
        if x >= 32767 { return 32767 }
        if x <= -32768 { return -32768 }
        return Int16(x)
    }

    /// AVAudioPCMBuffer（Float32 或 Int16，交错或非交错）→ 单声道 Int16。
    static func mono(from buffer: AVAudioPCMBuffer) -> [Int16] {
        let frames = Int(buffer.frameLength)
        let ch = Int(buffer.format.channelCount)
        guard frames > 0, ch > 0 else { return [] }
        var out = [Int16](repeating: 0, count: frames)
        let interleaved = buffer.format.isInterleaved
        if let data = buffer.int16ChannelData {
            for f in 0..<frames {
                var sum = 0
                for c in 0..<ch {
                    sum += Int(interleaved ? data[0][f * ch + c] : data[c][f])
                }
                out[f] = Int16(sum / ch)
            }
        } else if let data = buffer.floatChannelData {
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<ch { sum += interleaved ? data[0][f * ch + c] : data[c][f] }
                out[f] = floatToInt16(sum / Float(ch))
            }
        } else {
            return []
        }
        return out
    }
}

final class SyRtcPcmMixer {
    private let maxBufferedSamples: Int
    private var sources: [String: [Int16]] = [:]
    private var order: [String] = []
    private let lock = NSLock()

    init(maxBufferedSamples: Int) { self.maxBufferedSamples = max(1, maxBufferedSamples) }

    func push(_ sourceId: String, _ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var q = sources[sourceId] ?? { order.append(sourceId); return [] }()
        q.append(contentsOf: samples)
        if q.count > maxBufferedSamples { q.removeFirst(q.count - maxBufferedSamples) }
        sources[sourceId] = q
    }

    func removeSource(_ sourceId: String) {
        lock.lock(); defer { lock.unlock() }
        sources.removeValue(forKey: sourceId)
        order.removeAll { $0 == sourceId }
    }

    func bufferedSamples(_ sourceId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return sources[sourceId]?.count ?? 0
    }

    /// 取出 n 个混音样本；某一路不足时这一路补 0。
    func mix(_ n: Int) -> [Int16] {
        lock.lock(); defer { lock.unlock() }
        var acc = [Int](repeating: 0, count: n)
        for id in order {
            guard var q = sources[id] else { continue }
            let take = min(n, q.count)
            for i in 0..<take { acc[i] += Int(q[i]) }
            q.removeFirst(take)
            sources[id] = q
        }
        return acc.map { Int16(clamping: $0) }
    }
}

/// 录音格式。`mp3` 不支持（两端都没有 mp3 编码器），与 Android 相同。
enum SyRtcRecordingFormat: Equatable {
    case aacM4a, wav

    /// `aac` / `aaclc` / `aac_lc` / `m4a` → aacM4a，`wav` / `pcm` → wav，其余（含 mp3）→ nil。
    static func from(codec: String) -> SyRtcRecordingFormat? {
        switch codec.trimmingCharacters(in: .whitespaces).lowercased() {
        case "aac", "aaclc", "aac_lc", "m4a": return .aacM4a
        case "wav", "pcm": return .wav
        default: return nil
        }
    }
}

/// 通话录音：各声源 push PCM，20 ms 一拍混音后写 AAC(m4a) / WAV。
final class SyRtcCallAudioRecorder {
    static let localSource = "__local__"

    private let mixer: SyRtcPcmMixer
    private let sampleRate: Int
    private let queue = DispatchQueue(label: "sy.rtc.callrecorder")
    private var timer: DispatchSourceTimer?
    private var file: AVAudioFile?
    private var startedAt: CFAbsoluteTime = 0
    private var written = 0

    init(url: URL, format: SyRtcRecordingFormat, sampleRate: Int, bitrate: Int) throws {
        self.sampleRate = sampleRate
        self.mixer = SyRtcPcmMixer(maxBufferedSamples: sampleRate / 2)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        var settings: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        switch format {
        case .aacM4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = bitrate
        case .wav:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        }
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
    }

    func push(_ sourceId: String, mono: [Int16], sourceRate: Int) {
        guard !mono.isEmpty else { return }
        mixer.push(sourceId, SyRtcPcmConvert.resample(mono, from: sourceRate, to: sampleRate))
    }

    func removeSource(_ sourceId: String) { mixer.removeSource(sourceId) }

    func start() {
        startedAt = CFAbsoluteTimeGetCurrent()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    /// 停止并写完文件（AVAudioFile 释放时收尾）。
    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            tick()
            file = nil
        }
    }

    private func tick() {
        guard let file = file else { return }
        let due = Int((CFAbsoluteTimeGetCurrent() - startedAt) * Double(sampleRate))
        let n = due - written
        guard n > 0 else { return }
        let samples = mixer.mix(n)
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)),
              let dst = buf.int16ChannelData else { return }
        samples.withUnsafeBufferPointer { src in dst[0].update(from: src.baseAddress!, count: n) }
        buf.frameLength = AVAudioFrameCount(n)
        do { try file.write(from: buf) } catch { print("通话录音写入失败: \(error)") }
        written = due
    }
}

/// 远端音轨的 PCM 回调（WebRTC 解码后）。
final class SyRtcRemoteAudioTap: NSObject, RTCAudioRenderer {
    private let onPcm: ([Int16], Int) -> Void
    init(onPcm: @escaping ([Int16], Int) -> Void) { self.onPcm = onPcm }
    func render(pcmBuffer: AVAudioPCMBuffer) {
        onPcm(SyRtcPcmConvert.mono(from: pcmBuffer), Int(pcmBuffer.format.sampleRate))
    }
}

/// 本端采集后处理回调（APM 之后、编码之前）。RTCAudioBuffer 的 float 是 Int16 量级。
final class SyRtcCaptureAudioTap: NSObject, RTCAudioCustomProcessingDelegate {
    private let lock = NSLock()
    private var rate = 48000
    var onPcm: (([Int16], Int) -> Void)?

    func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels: Int) {
        lock.lock(); rate = sampleRateHz; lock.unlock()
    }

    func audioProcessingProcess(audioBuffer: RTCAudioBuffer) {
        guard let cb = onPcm else { return }
        let frames = audioBuffer.frames
        let ch = audioBuffer.channels
        guard frames > 0, ch > 0 else { return }
        var sum = [Float](repeating: 0, count: frames)
        for c in 0..<ch {
            let p = audioBuffer.rawBuffer(forChannel: c)
            for f in 0..<frames { sum[f] += p[f] }
        }
        let out = sum.map { SyRtcPcmConvert.floatToInt16($0 / Float(ch), scale: 1) }
        lock.lock(); let r = rate; lock.unlock()
        cb(out, r)
    }

    func audioProcessingRelease() {}
}

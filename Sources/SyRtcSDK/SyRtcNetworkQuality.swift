import Foundation

/// 由 WebRTC 统计里的 RTT 和丢包算出的网络质量。没有测量值时返回 `unknown`。
///
/// Android（`NetworkQualityEstimator`）与 iOS 使用同一套名字和阈值，改动需两端同步。
/// 阈值参考即构 Express 的质量分级，取 RTT 与丢包各自落入的档位中较差的一个：
///
/// | 档位 | RTT (ms) | 丢包 |
/// |---|---|---|
/// | excellent | < 100 | < 1% |
/// | good | < 200 | < 3% |
/// | poor | < 400 | < 8% |
/// | bad | < 800 | < 20% |
/// | down | ≥ 800 | ≥ 20% |
public enum SyRtcNetworkQuality {
    public static let rttExcellentMs = 100.0
    public static let rttGoodMs = 200.0
    public static let rttPoorMs = 400.0
    public static let rttBadMs = 800.0
    public static let lossExcellent = 0.01
    public static let lossGood = 0.03
    public static let lossPoor = 0.08
    public static let lossBad = 0.20

    /// - Parameters:
    ///   - rttMs: 往返时延（毫秒）。没有 candidate-pair 统计时传 nil。
    ///   - packetLossRatio: 丢包率，0 到 1。没有 inbound-rtp 计数时传 nil。
    /// - Returns: `excellent` / `good` / `poor` / `bad` / `down` / `unknown`
    public static func level(rttMs: Double?, packetLossRatio: Double?) -> String {
        guard rttMs != nil || packetLossRatio != nil else { return "unknown" }
        let rtt = max(0, rttMs ?? 0)
        let loss = min(1, max(0, packetLossRatio ?? 0))
        if loss >= lossBad || rtt >= rttBadMs { return "down" }
        if loss >= lossPoor || rtt >= rttPoorMs { return "bad" }
        if loss >= lossGood || rtt >= rttGoodMs { return "poor" }
        if loss >= lossExcellent || rtt >= rttExcellentMs { return "good" }
        return "excellent"
    }

    /// 本端质量 = 所有对端链路中最差的一档（unknown 不参与，全部 unknown 时为 unknown）。
    /// 与 Android `NetworkQualityEstimator.worst` 相同。
    public static func worst<S: Sequence>(_ qualities: S) -> String where S.Element == String {
        let best = qualities.max(by: { rank($0) < rank($1) })
        guard let q = best, rank(q) > 0 else { return "unknown" }
        return q
    }

    /// 0 unknown，1 excellent … 5 down。与 Android `NetworkQualityEstimator.toRank` 相同。
    public static func rank(_ quality: String) -> Int {
        switch quality {
        case "excellent": return 1
        case "good": return 2
        case "poor": return 3
        case "bad": return 4
        case "down": return 5
        default: return 0
        }
    }
}

/// 一轮 WebRTC 统计里与质量相关的字段。与 Android `StatsParser` / `TransportSample` 相同。
public struct SyRtcStatsSample: Equatable {
    public var rttMs: Double?
    /// 上行丢包率 0–1：`remote-inbound-rtp.fractionLost`，多路取最大。
    public var outboundLossRate: Double?
    /// 下行累计丢包 / 收包：各 `inbound-rtp` 之和。
    public var inboundPacketsLost: Int64?
    public var inboundPacketsReceived: Int64?
    /// 下行抖动（ms）：各 `inbound-rtp.jitter` 取最大。
    public var jitterMs: Double?
    public var inboundAudioLevel: Double?
    public var outboundAudioLevel: Double?

    public init() {}

    /// `records`：(type, values, isAudio)。RTT 取选中的 candidate-pair，没有时用 remote-inbound-rtp.roundTripTime。
    public static func parse(_ records: [(type: String, values: [String: Any], isAudio: Bool)]) -> SyRtcStatsSample {
        var s = SyRtcStatsSample()
        var remoteRtt: Double?
        func num(_ v: Any?) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let str = v as? String { return Double(str) }
            return nil
        }
        for r in records {
            let v = r.values
            switch r.type {
            case "candidate-pair":
                let nominated = (v["nominated"] as? NSNumber)?.boolValue ?? (v["nominated"] as? Bool) ?? false
                let selected = (v["selected"] as? NSNumber)?.boolValue ?? (v["selected"] as? Bool) ?? false
                if nominated || selected || (v["state"] as? String) == "succeeded", let rtt = num(v["currentRoundTripTime"]), rtt >= 0 {
                    s.rttMs = rtt * 1000
                }
            case "remote-inbound-rtp":
                if let f = num(v["fractionLost"]), f >= 0 {
                    let rate = f <= 1 ? f : f / 100
                    s.outboundLossRate = max(s.outboundLossRate ?? 0, rate)
                }
                if let rtt = num(v["roundTripTime"]), rtt >= 0 { remoteRtt = rtt * 1000 }
            case "inbound-rtp":
                if let lost = num(v["packetsLost"]), let recv = num(v["packetsReceived"]) {
                    s.inboundPacketsLost = (s.inboundPacketsLost ?? 0) + Int64(max(0, lost))
                    s.inboundPacketsReceived = (s.inboundPacketsReceived ?? 0) + Int64(max(0, recv))
                }
                if let j = num(v["jitter"]), j >= 0 { s.jitterMs = max(s.jitterMs ?? 0, j * 1000) }
                if r.isAudio, let level = num(v["audioLevel"]) { s.inboundAudioLevel = level }
            case "outbound-rtp":
                if r.isAudio, let level = num(v["audioLevel"]) { s.outboundAudioLevel = level }
            default:
                break
            }
        }
        if s.rttMs == nil { s.rttMs = remoteRtt }
        return s
    }
}

/// 上下行分开评估，阈值与 `SyRtcNetworkQuality` 相同。与 Android `LinkQuality` 相同。
/// - 上行 tx：RTT + 上行丢包（对端 `remote-inbound-rtp.fractionLost`）。
/// - 下行 rx：本统计周期的下行丢包（丢包 / 收包增量）+ 抖动：excellent <30ms，good <50ms，poor <100ms，bad <200ms，其余 down。
public enum SyRtcLinkQuality {
    public static let jitterExcellentMs = 30.0
    public static let jitterGoodMs = 50.0
    public static let jitterPoorMs = 100.0
    public static let jitterBadMs = 200.0

    public static func tx(rttMs: Double?, outboundLossRate: Double?) -> String {
        SyRtcNetworkQuality.level(rttMs: rttMs, packetLossRatio: outboundLossRate)
    }

    public static func rx(inboundLossRate: Double?, jitterMs: Double?) -> String {
        guard inboundLossRate != nil || jitterMs != nil else { return "unknown" }
        var levels: [String] = []
        if let loss = inboundLossRate { levels.append(SyRtcNetworkQuality.level(rttMs: nil, packetLossRatio: loss)) }
        if let j = jitterMs {
            let q: String
            if j >= jitterBadMs { q = "down" } else if j >= jitterPoorMs { q = "bad" } else if j >= jitterGoodMs { q = "poor" } else if j >= jitterExcellentMs { q = "good" } else { q = "excellent" }
            levels.append(q)
        }
        return SyRtcNetworkQuality.worst(levels)
    }

    /// 本周期下行丢包率（累计值增量）。没有上一轮用累计值；本周期无新包返回 nil；计数器回退时按没有上一轮处理。
    public static func intervalLossRate(prevLost: Int64?, prevReceived: Int64?, lost: Int64?, received: Int64?) -> Double? {
        guard let lost, let received else { return nil }
        var dLost = lost
        var dRecv = received
        if let pl = prevLost, let pr = prevReceived, lost >= pl, received >= pr {
            dLost = lost - pl
            dRecv = received - pr
        }
        let total = dLost + dRecv
        guard total > 0 else { return nil }
        return min(1, max(0, Double(dLost) / Double(total)))
    }
}

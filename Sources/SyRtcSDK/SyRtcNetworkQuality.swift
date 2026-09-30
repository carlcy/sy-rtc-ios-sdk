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

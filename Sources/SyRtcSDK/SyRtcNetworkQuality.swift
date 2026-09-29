import Foundation

/// 由 WebRTC 统计里的 RTT 和丢包算出的网络质量。没有测量值时返回 `unknown`。
public enum SyRtcNetworkQuality {
    /// - Parameters:
    ///   - rttMs: 往返时延（毫秒）。没有 candidate-pair 统计时传 nil。
    ///   - packetLossRatio: 丢包率，0 到 1。没有 inbound-rtp 计数时传 nil。
    /// - Returns: `excellent` / `good` / `poor` / `bad` / `down` / `unknown`
    public static func level(rttMs: Double?, packetLossRatio: Double?) -> String {
        guard rttMs != nil || packetLossRatio != nil else { return "unknown" }
        let rtt = max(0, rttMs ?? 0)
        let loss = min(1, max(0, packetLossRatio ?? 0))
        if loss >= 0.5 || rtt >= 2000 { return "down" }
        if loss >= 0.2 || rtt >= 600 { return "bad" }
        if loss >= 0.08 || rtt >= 250 { return "poor" }
        if loss >= 0.02 || rtt >= 100 { return "good" }
        return "excellent"
    }
}

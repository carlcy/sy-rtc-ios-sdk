import Foundation

/// 重连策略。与 Android `ReconnectPolicy` 相同，改动需两端同步。
///
/// 信令或 ICE 断开后最多重试 `maxAttempts` 次，第 n 次等待 `2^(n-1)` 秒：1、2、4、8、16 秒。
/// ICE 断开时由 uid 字典序较小的一方 `restartIce` 并重发 offer；另一方等对端 offer。
///
/// 连接状态回调（两端同名）：
/// - `connecting` / `joining` → `connected` / `join_success`
/// - `reconnecting` / `signaling` 或 `ice`（并回调 `onReconnecting`）
/// - `connected` / `rejoin_success`（并回调 `onRejoinChannelSuccess`、`onReconnected`）
/// - `failed` / `signaling` 或 `ice`（并回调 `onReconnectFailed`、`onError(1003)`）
/// - `disconnecting` / `leaving` → `disconnected` / `leave`
public enum SyRtcReconnectPolicy {
    public static let maxAttempts = 5
    public static let baseDelayMs = 1000
    public static let maxDelayMs = 16_000

    /// `attempt` 从 1 开始，返回毫秒。
    public static func delayMs(attempt: Int) -> Int {
        let n = min(max(attempt, 1), 31) - 1
        return min(baseDelayMs << min(n, 20), maxDelayMs)
    }
}

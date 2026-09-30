import Foundation

/// `onError(code:message:)` 的错误码。Android `RtcErrorCode`、iOS、Flutter `SyRtcErrorCode` 取值相同。
///
/// 10xx 是 SDK 本地错误；403 / 4031 / 4032 / 4033 与服务端 REST 业务码相同，
/// 来自信令 `kicked` / `error` 帧的 `data.code`。
public enum SyRtcErrorCode {
    /// 参数无效或调用时机不对（空 Token、未知画质档位、附加信息超过 1024 字节等）。
    public static let invalidArgument = 1000
    /// 信令服务端返回的错误；message 为服务端原文。
    public static let signaling = 1002
    /// 断线重连 5 次都失败，需 leave 后重新 join。
    public static let reconnectFailed = 1003
    /// 被房间管理踢出。凭证被停用时改报 4031/4032/4033。
    public static let kicked = 1004
    /// 摄像头打开或切换失败，或没有可用视频源。
    public static let camera = 1005
    /// 屏幕共享失败。
    public static let screenShare = 1006
    /// 自定义视频采集用法错误或视频源未就绪。
    public static let customCapture = 1007
    /// 音频路由切换失败或不支持（iOS 只能在扬声器和听筒之间切换）。
    public static let audioRoute = 1009
    /// 服务端拒绝入房（踢出名单、房间锁定、不在白名单）。
    public static let forbidden = 403
    /// AppId 的访问凭证已暂停。
    public static let credentialSuspended = 4031
    /// AppId 的访问凭证已吊销。
    public static let credentialRevoked = 4032
    /// AppId 的访问凭证已过期。
    public static let credentialExpired = 4033

    public static func isCredentialBlocked(_ code: Int) -> Bool {
        code == credentialSuspended || code == credentialRevoked || code == credentialExpired
    }

    static func intValue(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return nil
    }

    /// 信令 `kicked` 帧对应的错误码：带凭证码时用凭证码，否则 `kicked`。
    public static func forKicked(_ data: [String: Any]) -> Int {
        guard let code = intValue(data["code"]), isCredentialBlocked(code) else { return kicked }
        return code
    }

    /// 信令 `error` 帧对应的错误码：403 与凭证码原样透传，其余归为 `signaling`。
    public static func forSignalingError(_ data: [String: Any]) -> Int {
        guard let code = intValue(data["code"]) else { return signaling }
        return (code == forbidden || isCredentialBlocked(code)) ? code : signaling
    }

    /// 信令 `error` 帧的文本；新服务端用 `message`，旧服务端用 `error`。
    public static func signalingErrorMessage(_ data: [String: Any]) -> String {
        if let m = data["message"] as? String, !m.isEmpty { return m }
        if let m = data["error"] as? String, !m.isEmpty { return m }
        return "信令错误"
    }
}

/// RTC Token 过期时间解析。服务端 Token 形如 `base64url(payload).signature`，
/// payload 的 `expireAt` 为 Unix 秒；也兼容三段式 JWT 的 `exp`。
public enum SyRtcTokenExpiry {
    /// 过期前多少秒回调 `onTokenPrivilegeWillExpire`。
    public static let warnBeforeSeconds: TimeInterval = 30

    /// 返回过期时间（Unix 秒）；解析不出或为 0 时返回 nil。
    public static func expireAt(_ token: String) -> TimeInterval? {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        let payload: Substring
        switch parts.count {
        case 2: payload = parts[0]
        case 3: payload = parts[1]
        default: return nil
        }
        var b64 = String(payload)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - (b64.count % 4)) % 4
        if pad > 0 { b64 += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["expireAt", "exp"] {
            if let n = obj[key] as? NSNumber, n.doubleValue > 0 { return n.doubleValue }
        }
        return nil
    }

    /// (提醒延迟秒, 过期延迟秒)。已过期时两者都为 0。
    public static func delays(expireAt: TimeInterval, now: TimeInterval) -> (warn: TimeInterval, expire: TimeInterval) {
        let expire = max(0, expireAt - now)
        return (max(0, expire - warnBeforeSeconds), expire)
    }
}

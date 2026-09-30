import Foundation

/// Android / iOS / Flutter 共用的频道信令约定。改动必须三端同步。
///
/// - 流附加信息：`channel-message`，正文 `sy-extra:<文本>`，只回调 `onStreamExtraInfoUpdated`。
/// - 本端静音通知：信令类型 `user-media`，data 为 `{uid, audioMuted?, videoMuted?}`。
/// - SEI 风格消息：DataChannel 二进制，前 5 字节 `SYSEI`。不是码流 SEI。
/// - 旧版 Android（3.1 及以前）发的 JSON 信封 `{"type":"stream-extra"}` / `{"type":"client-mute"}` 仍能解析，但不再发送。
enum SyRtcWire {
    static let streamExtraPrefix = "sy-extra:"
    static let maxStreamExtraBytes = 1024
    static let seiMagic = Data("SYSEI".utf8)

    enum ChannelMessage: Equatable {
        /// 普通频道消息，回调 `onChannelMessage`。
        case plain(String)
        /// 流附加信息。
        case streamExtra(String)
        /// 旧 Android 静音通知。media 为 `audio` / `video`。
        case legacyMute(media: String, muted: Bool)
    }

    static func parseChannelMessage(_ message: String) -> ChannelMessage {
        if message.hasPrefix(streamExtraPrefix) {
            return .streamExtra(String(message.dropFirst(streamExtraPrefix.count)))
        }
        guard message.first == "{",
              let data = message.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String else {
            return .plain(message)
        }
        switch type {
        case "stream-extra":
            return .streamExtra((obj["extra"] as? String) ?? "")
        case "client-mute":
            guard let media = obj["media"] as? String, media == "audio" || media == "video",
                  let muted = obj["muted"] as? Bool else { return .plain(message) }
            return .legacyMute(media: media, muted: muted)
        default:
            return .plain(message)
        }
    }

    static func wrapSei(_ payload: Data) -> Data {
        var out = seiMagic
        out.append(payload)
        return out
    }

    /// 不是 SEI 帧时返回 nil。
    static func unwrapSei(_ data: Data) -> Data? {
        guard data.count >= seiMagic.count, data.prefix(seiMagic.count) == seiMagic else { return nil }
        return Data(data.dropFirst(seiMagic.count))
    }
}

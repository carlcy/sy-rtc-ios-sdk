import Foundation

/// iOS WebSocket 信令客户端。连接 URL 带 ?token=（RTC Token）。
internal final class SyRtcSignalingClient {
    private let url: URL
    private let channelId: String
    private let uid: String
    private let token: String
    private let onMessage: (_ type: String, _ data: [String: Any]) -> Void
    private var onFailure: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    init(
        signalingUrl: String,
        channelId: String,
        uid: String,
        token: String,
        onMessage: @escaping (_ type: String, _ data: [String: Any]) -> Void,
        onFailure: (() -> Void)? = nil
    ) {
        self.channelId = channelId
        self.uid = uid
        self.token = token
        self.onMessage = onMessage
        self.onFailure = onFailure
        self.session = URLSession(configuration: .default)
        self.url = Self.urlWithToken(base: signalingUrl, token: token)
    }

    private static func urlWithToken(base: String, token: String) -> URL {
        var cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: #"[?&]token=[^&]*"#, options: .regularExpression) {
            cleaned.replaceSubrange(range, with: String(cleaned[range].prefix(1)))
            while cleaned.hasSuffix("?") || cleaned.hasSuffix("&") {
                cleaned.removeLast()
            }
        }
        guard !token.isEmpty else { return URL(string: cleaned)! }
        let enc = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        let sep = cleaned.contains("?") ? "&" : "?"
        return URL(string: "\(cleaned)\(sep)token=\(enc)")!
    }

    func connect() {
        task = session.webSocketTask(with: url)
        task?.resume()
        sendJoin()
        receiveLoop()
    }

    func disconnect() {
        sendLeave()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                self.onFailure?()
                return
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handle(text: text)
                case .data:
                    break
                @unknown default:
                    break
                }
                self.receiveLoop()
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return
        }
        var payload = (obj["data"] as? [String: Any]) ?? [:]
        if let uid = obj["uid"] as? String { payload["uid"] = uid }
        if let channelId = obj["channelId"] as? String { payload["channelId"] = channelId }
        if let toUid = obj["toUid"] as? String { payload["toUid"] = toUid }
        onMessage(type, payload)
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func sendJoin() {
        var msg: [String: Any] = ["type": "join", "channelId": channelId, "uid": uid]
        if !token.isEmpty { msg["token"] = token }
        send(msg)
    }

    func sendChannelMessage(_ message: String) {
        send([
            "type": "channel-message",
            "channelId": channelId,
            "uid": uid,
            "data": ["uid": uid, "message": message]
        ])
    }

    func sendLeave() {
        send(["type": "leave", "channelId": channelId, "uid": uid])
    }

    func sendOffer(sdp: String, toUid: String? = nil) {
        var msg: [String: Any] = [
            "type": "offer",
            "channelId": channelId,
            "uid": uid,
            "data": ["sdp": sdp, "type": "offer"]
        ]
        if let toUid = toUid, !toUid.isEmpty { msg["toUid"] = toUid }
        send(msg)
    }

    func sendAnswer(sdp: String, toUid: String? = nil) {
        var msg: [String: Any] = [
            "type": "answer",
            "channelId": channelId,
            "uid": uid,
            "data": ["sdp": sdp, "type": "answer"]
        ]
        if let toUid = toUid, !toUid.isEmpty { msg["toUid"] = toUid }
        send(msg)
    }

    func sendIceCandidate(candidate: String, sdpMLineIndex: Int32, sdpMid: String, toUid: String? = nil) {
        var msg: [String: Any] = [
            "type": "ice-candidate",
            "channelId": channelId,
            "uid": uid,
            "data": ["candidate": candidate, "sdpMLineIndex": sdpMLineIndex, "sdpMid": sdpMid]
        ]
        if let toUid = toUid, !toUid.isEmpty { msg["toUid"] = toUid }
        send(msg)
    }
}

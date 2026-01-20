import Foundation

/// iOS WebSocket 信令客户端（对齐 rtm-service 的消息格式）
internal final class SyRtcSignalingClient {
    private let url: URL
    private let channelId: String
    private let uid: String
    private let onMessage: (_ type: String, _ data: [String: Any]) -> Void
    
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    
    init(signalingUrl: String, channelId: String, uid: String, onMessage: @escaping (_ type: String, _ data: [String: Any]) -> Void) {
        self.url = URL(string: signalingUrl)!
        self.channelId = channelId
        self.uid = uid
        self.onMessage = onMessage
        self.session = URLSession(configuration: .default)
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
        // 兼容：服务端可能把 uid/toUid/channelId 放在根字段
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
        send(["type": "join", "channelId": channelId, "uid": uid])
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


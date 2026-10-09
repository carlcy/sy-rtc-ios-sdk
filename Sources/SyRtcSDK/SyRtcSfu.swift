import Foundation

/// LiveKit join credentials from a `meta=true` token response
/// (`sfuUrl` / `sfuToken` / `sfuRoom` / `sfuIdentity` / `sfuExpireAt`).
/// `sfuExpireAt` equals the SY token's `expireAt`, so both are renewed together.
struct SySfuJoinInfo: Equatable {
    let url: String
    let token: String
    let room: String
    let identity: String
    let expireAt: Int64
}

/// What `join` / `renewToken` received: the SY token plus, when the server wired a
/// media node, the LiveKit credentials. Same rules as Android `JoinCredentials`.
///
/// Accepts a plain token, the `data` object of `POST /api/rtc/token` with `meta=true`,
/// or the whole `{code, data}` envelope. LiveKit is used only when `mediaWired == true`
/// and both `sfuUrl` and `sfuToken` are present; otherwise `sfu` is nil (P2P mesh).
struct SyJoinCredentials: Equatable {
    let token: String
    let sfu: SySfuJoinInfo?
    let canPublish: Bool?

    static func parse(_ input: String) -> SyJoinCredentials {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{"),
              let raw = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
            return SyJoinCredentials(token: text, sfu: nil, canPublish: nil)
        }
        let data = (root["data"] as? [String: Any]) ?? root
        func str(_ k: String) -> String { ((data[k] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let token = str("token")
        guard !token.isEmpty else { return SyJoinCredentials(token: text, sfu: nil, canPublish: nil) }
        let url = str("sfuUrl"), sfuToken = str("sfuToken")
        let kind = str("sfuKind").isEmpty ? "livekit" : str("sfuKind")
        let wired = (data["mediaWired"] as? Bool) ?? false
        var sfu: SySfuJoinInfo?
        if wired, !url.isEmpty, !sfuToken.isEmpty, kind == "livekit" {
            let exp = (data["sfuExpireAt"] as? NSNumber)?.int64Value ?? 0
            sfu = SySfuJoinInfo(url: url, token: sfuToken, room: str("sfuRoom"), identity: str("sfuIdentity"), expireAt: exp)
        }
        return SyJoinCredentials(token: token, sfu: sfu, canPublish: data["canPublish"] as? Bool)
    }
}

/// Why the SFU connection ended, reduced from LiveKit's DisconnectReason.
enum SySfuDisconnect: Equatable { case client, removed, roomDeleted, duplicateIdentity, other }

/// LiveKit ConnectionQuality, reduced.
enum SySfuQuality: Equatable { case excellent, good, poor, lost, unknown }

/// Media-plane events, independent of LiveKit types so the mapping is unit-testable.
enum SySfuSignal: Equatable {
    case trackMuted(uid: String, isLocal: Bool, audio: Bool, muted: Bool)
    case disconnected(SySfuDisconnect, detail: String)
    case quality(uid: String, SySfuQuality)
    /// Audio levels 0...1.
    case levels(local: Double?, remote: [String: Double])
    case reconnecting
    case reconnected
}

/// What the engine does with a mapped media event.
protocol SySfuSink: AnyObject {
    func sfuRemoteAudioMuted(uid: String, muted: Bool)
    func sfuRemoteVideoMuted(uid: String, muted: Bool)
    /// The server muted (or released) our microphone. Must not be auto-restored by the SDK.
    func sfuServerMutedLocalAudio(_ muted: Bool)
    /// Removed from the room by the server. Engine dedupes with signaling `kicked` and leaves.
    func sfuKicked(reason: String)
    /// Media connection lost for a reason other than kick / leave.
    func sfuMediaLost(detail: String)
    func sfuNetworkQuality(uid: String, quality: String)
    func sfuLevels(local: Double?, remote: [String: Double])
    func sfuReconnecting()
    func sfuReconnected()
}

/// Maps LiveKit media events onto SY callbacks (same rules as Android `SfuEventMapper`).
/// Roster (onUserJoined / onUserOffline) still comes from `/ws/signaling`.
final class SySfuEventMapper {
    private weak var sink: SySfuSink?
    /// Last mute state the app asked for. A local mute that differs came from the server.
    var localAudioMuteRequested = false
    private(set) var isServerMuted = false

    init(sink: SySfuSink) { self.sink = sink }

    func on(_ signal: SySfuSignal) {
        guard let sink else { return }
        switch signal {
        case let .trackMuted(uid, isLocal, audio, muted):
            if !isLocal {
                audio ? sink.sfuRemoteAudioMuted(uid: uid, muted: muted) : sink.sfuRemoteVideoMuted(uid: uid, muted: muted)
                return
            }
            guard audio else { return }
            if muted && !localAudioMuteRequested && !isServerMuted {
                isServerMuted = true
                sink.sfuServerMutedLocalAudio(true)
            } else if !muted && isServerMuted {
                isServerMuted = false
                sink.sfuServerMutedLocalAudio(false)
            }
        case let .disconnected(reason, detail):
            switch reason {
            case .client: break
            case .removed: sink.sfuKicked(reason: "removed by server")
            case .roomDeleted: sink.sfuKicked(reason: "room deleted")
            case .duplicateIdentity: sink.sfuKicked(reason: "duplicate identity")
            case .other: sink.sfuMediaLost(detail: detail.isEmpty ? "sfu disconnected" : detail)
            }
        case let .quality(uid, q):
            sink.sfuNetworkQuality(uid: uid, quality: Self.qualityLabel(q))
        case let .levels(local, remote):
            sink.sfuLevels(local: local.map(Self.clamp), remote: remote.mapValues(Self.clamp))
        case .reconnecting: sink.sfuReconnecting()
        case .reconnected: sink.sfuReconnected()
        }
    }

    static func qualityLabel(_ q: SySfuQuality) -> String {
        switch q {
        case .excellent: return "excellent"
        case .good: return "good"
        case .poor: return "poor"
        case .lost: return "down"
        case .unknown: return "unknown"
        }
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v.isFinite ? v : 0)) }
}

/// onKicked fires once per join even when LiveKit and signaling both report it.
final class SyOnceFlag {
    private let lock = NSLock()
    private var fired = false
    func tryFire() -> Bool { lock.lock(); defer { lock.unlock() }; if fired { return false }; fired = true; return true }
    func reset() { lock.lock(); fired = false; lock.unlock() }
}

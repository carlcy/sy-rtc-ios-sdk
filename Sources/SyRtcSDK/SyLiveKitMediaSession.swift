import Foundation
// SPM product module is `LiveKit`; the CocoaPods pod `LiveKitClient` builds module `LiveKitClient`.
#if canImport(LiveKitClient)
import LiveKitClient
#else
import LiveKit
#endif
#if canImport(UIKit)
import UIKit
#endif

protocol SyLiveKitMediaSessionCallbacks: AnyObject {
    func sfuConnected(reconnect: Bool)
    func sfuConnectFailed(_ error: Error)
    func sfuFirstRemoteVideo(uid: String)
}

/// Media over a LiveKit SFU, used when the token carries `sfuUrl` / `sfuToken`.
/// Same design as Android `LiveKitMediaSession`: only media lives here, `/ws/signaling`
/// keeps business events and the roster; events go out through `SySfuEventMapper`.
/// All state is touched on the main queue.
final class SyLiveKitMediaSession: NSObject, RoomDelegate {
    private let localUid: String
    private let mapper: SySfuEventMapper
    private weak var callbacks: SyLiveKitMediaSessionCallbacks?
    private var room: Room?
    private var levelsTimer: Timer?
    private(set) var credentials: SySfuJoinInfo?
    private var wantMic = false
    private var wantCamera = false
    private var released = false

#if canImport(UIKit)
    private weak var localContainer: UIView?
    private var localView: VideoView?
    private var remoteContainers: [String: WeakView] = [:]
    private var remoteViews: [String: VideoView] = [:]
    private final class WeakView { weak var view: UIView?; init(_ v: UIView) { view = v } }
#endif
    private var remoteVideo: [String: VideoTrack] = [:]
    private var firstVideoSeen = Set<String>()

    init(localUid: String, mapper: SySfuEventMapper, callbacks: SyLiveKitMediaSessionCallbacks) {
        self.localUid = localUid
        self.mapper = mapper
        self.callbacks = callbacks
        super.init()
    }

    func connect(_ info: SySfuJoinInfo, publishMic: Bool, publishCamera: Bool, reconnect: Bool = false) {
        credentials = info
        wantMic = publishMic
        wantCamera = publishCamera
        let r = room ?? Room(delegate: self)
        room = r
        Task { @MainActor [weak self] in
            do {
                try await r.connect(url: info.url, token: info.token)
                guard let self, !self.released else { return }
                await self.applyPublishing(r)
                self.bindLocal()
                self.startLevels()
                self.callbacks?.sfuConnected(reconnect: reconnect)
            } catch {
                guard let self, !self.released else { return }
                NSLog("[SyRtc] LiveKit connect failed: \(error)")
                self.callbacks?.sfuConnectFailed(error)
            }
        }
    }

    /// New SY token renewed: keep the matching sfuToken for the next (re)connect.
    func updateCredentials(_ info: SySfuJoinInfo) { credentials = info }

    /// Reconnect after a media loss with the latest credentials.
    func reconnect() {
        guard let info = credentials, let r = room else { return }
        Task { @MainActor [weak self] in
            await r.disconnect()
            self?.connect(info, publishMic: self?.wantMic ?? false, publishCamera: self?.wantCamera ?? false, reconnect: true)
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        wantMic = enabled
        guard let r = room, r.connectionState == .connected else { return }
        Task { @MainActor in
            do { try await r.localParticipant.setMicrophone(enabled: enabled) } catch { NSLog("[SyRtc] LiveKit mic: \(error)") }
        }
    }

    func setCameraEnabled(_ enabled: Bool) {
        wantCamera = enabled
        guard let r = room, r.connectionState == .connected else { return }
        Task { @MainActor [weak self] in
            do {
                try await r.localParticipant.setCamera(enabled: enabled)
                self?.bindLocal()
            } catch { NSLog("[SyRtc] LiveKit camera: \(error)") }
        }
    }

#if canImport(UIKit)
    func attachLocal(_ container: UIView) {
        localContainer = container
        bindLocal()
    }

    func attachRemote(uid: String, container: UIView) {
        remoteContainers[uid] = WeakView(container)
        bindRemote(uid)
    }
#endif

    func disconnect() {
        released = true
        levelsTimer?.invalidate()
        levelsTimer = nil
#if canImport(UIKit)
        localView?.track = nil
        localView?.removeFromSuperview()
        remoteViews.values.forEach { $0.track = nil; $0.removeFromSuperview() }
        remoteViews.removeAll()
        remoteContainers.removeAll()
#endif
        remoteVideo.removeAll()
        let r = room
        room = nil
        Task { await r?.disconnect() }
    }

    // MARK: - Internals

    @MainActor
    private func applyPublishing(_ r: Room) async {
        do { try await r.localParticipant.setMicrophone(enabled: wantMic) } catch { NSLog("[SyRtc] LiveKit mic: \(error)") }
        if wantCamera {
            do { try await r.localParticipant.setCamera(enabled: true) } catch { NSLog("[SyRtc] LiveKit camera: \(error)") }
        }
    }

    private func uid(_ p: Participant?) -> String { p?.identity?.stringValue ?? "" }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    private func bindRemote(_ uid: String) {
#if canImport(UIKit)
        guard let track = remoteVideo[uid], let container = remoteContainers[uid]?.view else { return }
        let v = remoteViews[uid] ?? VideoView()
        v.layoutMode = .fit
        v.track = track
        if v.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            v.frame = container.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(v)
        }
        remoteViews[uid] = v
        if firstVideoSeen.insert(uid).inserted { callbacks?.sfuFirstRemoteVideo(uid: uid) }
#endif
    }

    private func bindLocal() {
#if canImport(UIKit)
        guard let container = localContainer, let r = room,
              let track = r.localParticipant.firstCameraPublication?.track as? VideoTrack else { return }
        let v = localView ?? VideoView()
        v.mirrorMode = .mirror
        v.layoutMode = .fill
        v.track = track
        if v.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            v.frame = container.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(v)
        }
        localView = v
#endif
    }

    /// LiveKit audio levels (0..1) every 200 ms, fed into the existing volume indication.
    private func startLevels() {
        levelsTimer?.invalidate()
        levelsTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, !self.released, let r = self.room else { return }
            var remote: [String: Double] = [:]
            for p in r.remoteParticipants.values {
                let u = self.uid(p)
                if !u.isEmpty { remote[u] = Double(p.audioLevel) }
            }
            self.mapper.on(.levels(local: Double(r.localParticipant.audioLevel), remote: remote))
        }
    }

    static func reason(_ error: LiveKitError?) -> SySfuDisconnect {
        guard let error else { return .client }
        switch error.type {
        case .cancelled: return .client
        case .participantRemoved: return .removed
        case .roomDeleted: return .roomDeleted
        case .duplicateIdentity: return .duplicateIdentity
        default: return .other
        }
    }

    static func quality(_ q: ConnectionQuality) -> SySfuQuality {
        switch q {
        case .excellent: return .excellent
        case .good: return .good
        case .poor: return .poor
        case .lost: return .lost
        default: return .unknown
        }
    }

    // MARK: - RoomDelegate (called off the main queue)

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        let u = uid(participant)
        onMain { [weak self] in
            guard let self, !u.isEmpty else { return }
            self.remoteVideo[u] = track
            self.bindRemote(u)
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        guard publication.kind == .video else { return }
        let u = uid(participant)
        onMain { [weak self] in
            guard let self else { return }
            self.remoteVideo.removeValue(forKey: u)
            self.firstVideoSeen.remove(u)
#if canImport(UIKit)
            if let v = self.remoteViews.removeValue(forKey: u) { v.track = nil; v.removeFromSuperview() }
#endif
        }
    }

    func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        let u = uid(participant)
        let isLocal = participant is LocalParticipant
        let kind = trackPublication.kind
        onMain { [weak self] in
            guard let self else { return }
            switch kind {
            case .audio: self.mapper.on(.trackMuted(uid: isLocal ? self.localUid : u, isLocal: isLocal, audio: true, muted: isMuted))
            case .video: self.mapper.on(.trackMuted(uid: isLocal ? self.localUid : u, isLocal: isLocal, audio: false, muted: isMuted))
            default: break
            }
        }
    }

    func room(_ room: Room, participant: Participant, didUpdateConnectionQuality quality: ConnectionQuality) {
        let isLocal = participant is LocalParticipant
        let u = uid(participant)
        onMain { [weak self] in
            guard let self else { return }
            self.mapper.on(.quality(uid: isLocal ? self.localUid : u, Self.quality(quality)))
        }
    }

    func roomIsReconnecting(_ room: Room) { onMain { [weak self] in self?.mapper.on(.reconnecting) } }
    func roomDidReconnect(_ room: Room) { onMain { [weak self] in self?.mapper.on(.reconnected) } }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        onMain { [weak self] in
            guard let self, !self.released, self.room === room else { return }
            self.mapper.on(.disconnected(Self.reason(error), detail: error.map { "\($0.type)" } ?? ""))
        }
    }
}

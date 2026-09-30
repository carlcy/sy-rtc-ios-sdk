import Foundation
import AVFoundation
import Network
import WebRTC
#if canImport(UIKit)
import UIKit
#endif
import ReplayKit
import CoreImage
import CoreMedia
import CoreVideo

/// RTC引擎实现类
/// 
/// 包含所有原生方法的实现
internal class SyRtcEngineImpl {
    private let appId: String
    weak var eventHandler: SyRtcEventHandler?
    private var audioEngine: AVAudioEngine?
    private var speakerphoneEnabled = false
    private var isVideoEnabled = false
    private var isLocalVideoEnabled = false
    private var audioMixingState: AudioMixingState = .stopped
    private var effects: [Int: AudioEffectState] = [:]
    private var userVolumes: [String: Int] = [:]
    private var playbackVolume = 100
    
    // 视频编码配置
    private var currentVideoConfig: VideoEncoderConfiguration?
    private var isPreviewing = false
    private var videoMutedStates: [String: Bool] = [:]
    
    // WebRTC核心组件
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var videoCapturer: RTCVideoCapturer?
    
    // 屏幕共享状态
    private var isScreenCapturing = false
    private var screenCaptureConfig: ScreenCaptureConfiguration?
    
    // 美颜配置
    private var beautyOptions: BeautyOptions?
    
    // 音频质量配置
    private var currentAudioQuality: String = "medium"
    private var audioSampleRate: Int = 48000
    private var audioBitrate: Int = 32000
    
    // 音频混音
    private var audioMixingPlayer: AVAudioPlayer?
    private var audioMixingConfig: AudioMixingConfiguration?
    
    // 音效管理
    private var effectPlayers: [Int: AVAudioPlayer] = [:]
    
    // 音频录制
    private var audioRecorder: AVAudioRecorder?
    private var audioRecordingConfig: AudioRecordingConfiguration?
    /// 频道内录音：WebRTC 管线里的 PCM（本端采集后处理 + 远端解码）混音。与 Android 相同。
    private var callRecorder: SyRtcCallAudioRecorder?
    private let captureAudioTap = SyRtcCaptureAudioTap()
    /// capturePostProcessingDelegate 是 weak，需要自己持有。
    private var audioProcessingModule: RTCDefaultAudioProcessingModule?
    private var remoteAudioTaps: [String: SyRtcRemoteAudioTap] = [:]
    
    // 数据流
    private var dataStreams: [Int: Bool] = [:]
    private var dataChannelMap: [Int: RTCDataChannel] = [:]
    private var peerConnections: [String: RTCPeerConnection] = [:]

    // 信令
    private var signalingClient: SyRtcSignalingClient?
    private var signalingUrl: String = "ws://47.105.48.196/ws/signaling"
    private var joinStartTime: Date?
    private var hasFiredJoinSuccess = false
    private var apiBaseUrl: String?
    private var currentChannelId: String?
    private var currentUid: String?
    // join() 传入的是 RTC Token（用于加入频道）
    private var currentToken: String?
    // 后端 API 认证用的 JWT
    private var apiAuthToken: String?
    private var pendingRejoin = false
    private var tokenWarnWork: DispatchWorkItem?
    private var tokenExpireWork: DispatchWorkItem?
    private var currentQualityTier: String = SyRtcQualityTier.sd.rawValue
    private var connectionState = "disconnected"
    private var networkType = "unknown"
    private var pathMonitor: NWPathMonitor?
    private var routeObserver: NSObjectProtocol?
    private var monitorsStarted = false
    private var preferFrontCamera = true
    private var customVideoCaptureEnabled = false
    private var videoFrameProcessor: SyRtcVideoFrameProcessor?
    private var cameraVideoSource: RTCVideoSource?
    private var cameraFrameRelay: CameraFrameRelay?
    private var screenVideoSource: RTCVideoSource?
    private var screenVideoTrack: RTCVideoTrack?
    private var screenCapturer: RTCVideoCapturer?
    private var localAudioMuted = false
    private var localVideoMuted = false
    private var muteAllRemoteAudio = false
    private var muteAllRemoteVideo = false
    private var remoteAudioMuted: [String: Bool] = [:]
    private var remoteAudioTracks: [String: RTCAudioTrack] = [:]
    /// 上一轮下行累计丢包 / 收包（按对端），用于算本周期下行丢包率。
    private var lastInboundLost: [String: Int64] = [:]
    private var lastInboundRecv: [String: Int64] = [:]
    private var streamExtraInfo = ""
    private let streamExtraPrefix = SyRtcWire.streamExtraPrefix
    private var signalingGeneration = 0
    private var reconnectAttempt = 0
    private var reconnectWork: DispatchWorkItem?
    /// ICE 断开、正在恢复的对端。与信令共用 `reconnectAttempt`。
    private var iceLostPeers = Set<String>()
    private var iceRecoveryPending = false
    private var iceRetryWork: DispatchWorkItem?
    /// 最近一次掉线来自信令（用于 `onReconnected(reason:)`）。
    private var reconnectWorkWasSignaling = false
    private var qualityTimer: Timer?
    private var volumeIntervalMs = 0
    private var volumeSmooth = 3
    private var reportVad = false
    private var smoothedVolumes: [String: Double] = [:]
    private var dataStreamConfigs: [Int: (reliable: Bool, ordered: Bool)] = [:]
    private var nextDataStreamId = 1
    private var dataChannelsByPeer: [String: [Int: RTCDataChannel]] = [:]
    private var pendingForceOffer: Set<String> = []
    private var firstFrameRenderers: [String: FrameTrackingRenderer] = [:]
    private var localFrameRenderers: [String: FrameTrackingRenderer] = [:]
    private var canPublishMedia = true
    
    // 多人语聊（Mesh）：每个远端用户一条 PeerConnection（key=remoteUid）
    private var offerSentByUid: Set<String> = []
    private var remoteSdpSetByUid: Set<String> = []
    private var pendingLocalIceByUid: [String: [RTCIceCandidate]] = [:]
    private var pendingRemoteIceByUid: [String: [RTCIceCandidate]] = [:]

    private func guessRemoteUid() -> String {
        return peerConnections.keys.first(where: { $0 != "default" }) ?? ""
    }
    
    // 屏幕共享
    private var screenRecorder: RPScreenRecorder?
    
    // 美颜滤镜
    private var beautyFilter: BeautyFilter?
    
    // 远端视频轨道
    private var remoteVideoTracks: [String: RTCVideoTrack] = [:]

#if canImport(UIKit)
    private weak var localContainerView: UIView?
    private var localRenderer: RTCMTLVideoView?
    private var remoteContainerViews: [String: UIView] = [:]
    private var remoteRenderers: [String: RTCMTLVideoView] = [:]
#endif

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    enum AudioMixingState {
        case stopped
        case playing
        case paused
    }
    
    struct AudioEffectState {
        let config: AudioEffectConfiguration
        let isPlaying: Bool
    }
    
    init(appId: String) {
        self.appId = appId
        initializeAudioSystem()
        initializeWebRTC()
        startMonitorsIfNeeded()
    }

    func setSignalingServerUrl(_ url: String) {
        if !url.isEmpty {
            signalingUrl = url
        }
    }

    func setApiBaseUrl(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        apiBaseUrl = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    func setApiAuthToken(_ token: String) {
        apiAuthToken = token
    }


    // MARK: - 频道（多人语聊 Mesh）
    func join(channelId: String, uid: String, token: String) {
        guard !channelId.trimmingCharacters(in: .whitespaces).isEmpty,
              !uid.trimmingCharacters(in: .whitespaces).isEmpty,
              !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            eventHandler?.onError(code: SyRtcErrorCode.invalidArgument, message: "channelId/uid/token 不能为空")
            return
        }
        currentChannelId = channelId
        currentUid = uid
        currentToken = token
        pendingRejoin = false
        scheduleTokenPrivilegeWatch(token: token)
        offerSentByUid.removeAll()
        remoteSdpSetByUid.removeAll()
        pendingLocalIceByUid.removeAll()
        pendingRemoteIceByUid.removeAll()
        hasFiredJoinSuccess = false
        joinStartTime = Date()

        connectionState = "connecting"
        eventHandler?.onConnectionStateChanged(state: "connecting", reason: "joining")
        reconnectAttempt = 0
        resetIceRecovery()
        openSignaling(channelId: channelId, uid: uid, token: token)
        startQualityMonitor()

        // 本地音频轨道（多人：后续每条 PC 都 addTrack）
        if let factory = peerConnectionFactory, localAudioTrack == nil {
            let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio_track")
        }
    }

    func leave() {
        if callRecorder != nil { stopAudioRecording() }
        connectionState = "disconnecting"
        eventHandler?.onConnectionStateChanged(state: "disconnecting", reason: "leaving")
        signalingGeneration += 1
        reconnectWork?.cancel()
        reconnectWork = nil
        reconnectAttempt = 0
        resetIceRecovery()
        stopQualityMonitor()

        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        offerSentByUid.removeAll()
        remoteSdpSetByUid.removeAll()
        pendingLocalIceByUid.removeAll()
        pendingRemoteIceByUid.removeAll()
        pendingForceOffer.removeAll()
        dataChannelsByPeer.removeAll()
        remoteAudioTracks.removeAll()
        for (uid, renderer) in firstFrameRenderers { remoteVideoTracks[uid]?.remove(renderer) }
        remoteVideoTracks.removeAll()
        firstFrameRenderers.removeAll()
        signalingClient?.disconnect(sendLeave: true)
        signalingClient = nil
        pendingRejoin = false
        cancelTokenPrivilegeWatch()

        let channelId = currentChannelId ?? ""
        currentChannelId = nil
        currentUid = nil
        currentToken = nil
        joinStartTime = nil
        hasFiredJoinSuccess = false
        connectionState = "disconnected"

        eventHandler?.onLeaveChannel(stats: ["channelId": channelId])
        eventHandler?.onConnectionStateChanged(state: "disconnected", reason: "leave")
    }

    private func createPeerConnection(remoteUid: String) -> RTCPeerConnection? {
        guard let factory = peerConnectionFactory else { return nil }
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        // 这里建议配置你自己的 STUN/TURN；先给一个公共 STUN 做最小可用
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let pc = factory.peerConnection(with: config, constraints: constraints, delegate: PeerDelegate(owner: self, remoteUid: remoteUid))
        peerConnections[remoteUid] = pc
        pendingLocalIceByUid[remoteUid] = []
        pendingRemoteIceByUid[remoteUid] = []
        if let pc {
            if let track = localAudioTrack { addTrackIfNeeded(track, to: pc) }
            if let track = localVideoTrack { addTrackIfNeeded(track, to: pc) }
            if let track = screenVideoTrack { addTrackIfNeeded(track, to: pc) }
            attachExistingDataChannels(remoteUid: remoteUid, peerConnection: pc)
            applyVideoBitrateToSenders()
        }
        return pc
    }

    private func handleSignalingMessage(type: String, data: [String: Any], channelId: String) {
        switch type {
        case "kicked":
            let reason = (data["reason"] as? String) ?? "kicked"
            eventHandler?.onKicked(channelId: channelId, reason: reason)
            eventHandler?.onError(code: SyRtcErrorCode.forKicked(data), message: "kicked: \(reason)")
            leave()
        case "user-kicked":
            if let kickedUid = data["uid"] as? String {
                if kickedUid == currentUid {
                    leave()
                } else {
                    eventHandler?.onUserOffline(uid: kickedUid, reason: "kicked")
                }
            }
        case "mute-audio", "unmute-audio":
            let target = (data["uid"] as? String) ?? ""
            let muted = type == "mute-audio" || (data["mutedAudio"] as? Bool) == true
            eventHandler?.onServerMuteAudio(uid: target, muted: muted)
            if target == currentUid {
                localAudioTrack?.isEnabled = !muted
            }
        case "user-list":
            guard let localUid = currentUid, let chId = currentChannelId else { return }
            // 服务端 data.users 可能是 [String] 或 JSON 反序列化后的 [Any]，需兼容
            let users: [String] = (data["users"] as? [String]) ?? (data["users"] as? [Any])?.compactMap { $0 as? String } ?? []
            let rejoining = pendingRejoin
            reconnectAttempt = 0
            connectionState = "connected"
            if !hasFiredJoinSuccess {
                hasFiredJoinSuccess = true
                let elapsed = Int((Date().timeIntervalSince(joinStartTime ?? Date())) * 1000)
                eventHandler?.onJoinChannelSuccess(channelId: chId, uid: localUid, elapsed: max(0, elapsed))
                eventHandler?.onConnectionStateChanged(state: "connected", reason: "join_success")
            } else if pendingRejoin {
                pendingRejoin = false
                let elapsed = Int((Date().timeIntervalSince(joinStartTime ?? Date())) * 1000)
                eventHandler?.onRejoinChannelSuccess(channelId: chId, uid: localUid, elapsed: max(0, elapsed))
                eventHandler?.onConnectionStateChanged(state: "connected", reason: "rejoin_success")
                if reconnectWorkWasSignaling {
                    reconnectWorkWasSignaling = false
                    eventHandler?.onReconnected(reason: "signaling")
                }
            }
            for u in users where u != localUid {
                let known = peerConnections[u] != nil
                if !rejoining || !known {
                    eventHandler?.onUserJoined(uid: u, elapsed: 0)
                }
                if peerConnections[u] == nil { _ = createPeerConnection(remoteUid: u) }
                if !known {
                    republishSideInfo()
                }
                if shouldInitiateOffer(localUid: localUid, remoteUid: u) {
                    startOffer(to: u)
                }
            }
        case "offer":
            guard let from = data["uid"] as? String, let sdp = data["sdp"] as? String else { return }
            let pc = peerConnections[from] ?? createPeerConnection(remoteUid: from)
            guard let pcUnwrapped = pc else { return }
            let remote = RTCSessionDescription(type: .offer, sdp: sdp)
            pcUnwrapped.setRemoteDescription(remote) { [weak self] _ in
                guard let self = self else { return }
                self.remoteSdpSetByUid.insert(from)
                self.flushPendingRemoteIce(from: from)
                let constraints = self.receiveConstraints()
                pcUnwrapped.answer(for: constraints) { sdp, _ in
                    guard let sdp = sdp else { return }
                    pcUnwrapped.setLocalDescription(sdp) { _ in
                        self.signalingClient?.sendAnswer(sdp: sdp.sdp, toUid: from)
                        self.flushPendingLocalIce(to: from)
                        if !self.dataStreamConfigs.isEmpty || self.localVideoTrack != nil || self.screenVideoTrack != nil {
                            self.forceOffer(to: from)
                        }
                    }
                }
            }
        case "answer":
            guard let from = data["uid"] as? String, let sdp = data["sdp"] as? String else { return }
            guard let pc = peerConnections[from] else { return }
            let remote = RTCSessionDescription(type: .answer, sdp: sdp)
            pc.setRemoteDescription(remote, completionHandler: { [weak self] _ in
                self?.remoteSdpSetByUid.insert(from)
                self?.flushPendingRemoteIce(from: from)
            })
        case "ice-candidate":
            guard let from = data["uid"] as? String, let cand = data["candidate"] as? String else { return }
            let mline = (data["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0
            let mid = (data["sdpMid"] as? String) ?? ""
            let c = RTCIceCandidate(sdp: cand, sdpMLineIndex: mline, sdpMid: mid)
            if remoteSdpSetByUid.contains(from), let pc = peerConnections[from] {
                pc.add(c)
            } else {
                pendingRemoteIceByUid[from, default: []].append(c)
            }
        case "user-joined":
            if let uid = data["uid"] as? String {
                eventHandler?.onUserJoined(uid: uid, elapsed: 0)
                if let localUid = currentUid, uid != localUid {
                    let known = peerConnections[uid] != nil
                    if peerConnections[uid] == nil { _ = createPeerConnection(remoteUid: uid) }
                    if !known { republishSideInfo() }
                    if shouldInitiateOffer(localUid: localUid, remoteUid: uid) {
                        startOffer(to: uid)
                    }
                }
            }
        case "user-left":
            if let uid = data["uid"] as? String {
                eventHandler?.onUserOffline(uid: uid, reason: "quit")
                if iceLostPeers.remove(uid) != nil, iceLostPeers.isEmpty, iceRecoveryPending {
                    // 断开的对端已离开，不再为它重连。
                    resetIceRecovery()
                    reconnectAttempt = 0
                }
                peerConnections.removeValue(forKey: uid)?.close()
                offerSentByUid.remove(uid)
                remoteSdpSetByUid.remove(uid)
                pendingLocalIceByUid.removeValue(forKey: uid)
                pendingRemoteIceByUid.removeValue(forKey: uid)
                pendingForceOffer.remove(uid)
                dataChannelsByPeer.removeValue(forKey: uid)
                detachRemoteAudioTap(uid: uid)
                remoteAudioTracks.removeValue(forKey: uid)
                if let renderer = firstFrameRenderers.removeValue(forKey: uid) {
                    remoteVideoTracks[uid]?.remove(renderer)
                }
                remoteVideoTracks.removeValue(forKey: uid)
            }
        case "channel-message":
            let fromUid = (data["uid"] as? String) ?? ""
            let msg = (data["message"] as? String) ?? ""
            switch SyRtcWire.parseChannelMessage(msg) {
            case .streamExtra(let extra):
                eventHandler?.onStreamExtraInfoUpdated(uid: fromUid, extraInfo: extra)
            case .legacyMute(let media, let muted):
                applyRemoteMediaState(media == "audio"
                    ? ["uid": fromUid, "audioMuted": muted]
                    : ["uid": fromUid, "videoMuted": muted])
            case .plain(let text):
                eventHandler?.onChannelMessage(uid: fromUid, message: text)
            }
        case "user-media":
            applyRemoteMediaState(data)
        case "token-will-expire", "token-privilege-will-expire":
            if tokenExpiryDedupe.shouldFire(.willExpire, eventExpireAt: SyRtcTokenExpiryDedupe.expireAt(of: data)) {
                eventHandler?.onTokenPrivilegeWillExpire()
            }
        case "token-expired", "request-token":
            if tokenExpiryDedupe.shouldFire(.expired, eventExpireAt: SyRtcTokenExpiryDedupe.expireAt(of: data)) {
                eventHandler?.onRequestToken()
            }
        case "error":
            eventHandler?.onError(code: SyRtcErrorCode.forSignalingError(data),
                                  message: SyRtcErrorCode.signalingErrorMessage(data))
        default:
            break
        }
    }

    private func shouldInitiateOffer(localUid: String, remoteUid: String) -> Bool {
        return localUid < remoteUid
    }

    private func startOffer(to remoteUid: String, force: Bool = false) {
        guard let pc = peerConnections[remoteUid] else { return }
        if !force && offerSentByUid.contains(remoteUid) { return }
        offerSentByUid.insert(remoteUid)
        let constraints = receiveConstraints()
        pc.offer(for: constraints) { [weak self] sdp, _ in
            guard let self = self, let sdp = sdp else { return }
            pc.setLocalDescription(sdp) { _ in
                self.signalingClient?.sendOffer(sdp: sdp.sdp, toUid: remoteUid)
                self.flushPendingLocalIce(to: remoteUid)
            }
        }
    }

    private final class PeerDelegate: NSObject, RTCPeerConnectionDelegate {
        private weak var owner: SyRtcEngineImpl?
        private let remoteUid: String

        init(owner: SyRtcEngineImpl, remoteUid: String) {
            self.owner = owner
            self.remoteUid = remoteUid
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            guard let owner = owner else { return }
            if owner.offerSentByUid.contains(remoteUid) || owner.remoteSdpSetByUid.contains(remoteUid) {
                owner.signalingClient?.sendIceCandidate(candidate: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid ?? "", toUid: remoteUid)
            } else {
                owner.pendingLocalIceByUid[remoteUid, default: []].append(candidate)
            }
        }

        // MARK: - RTCPeerConnectionDelegate required stubs (GoogleWebRTC)
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
            if stateChanged == .stable {
                owner?.flushRenegotiation(remoteUid: remoteUid)
            }
        }
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
            stream.videoTracks.forEach { owner?.attachRemoteTrack($0, uid: remoteUid) }
            stream.audioTracks.forEach { owner?.attachRemoteTrack($0, uid: remoteUid) }
        }
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
            owner?.handleIceState(newState, remoteUid: remoteUid)
        }
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
            owner?.handleOpenedDataChannel(dataChannel, remoteUid: remoteUid)
        }
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
            if let track = rtpReceiver.track {
                owner?.attachRemoteTrack(track, uid: remoteUid)
            }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didAddReceiver rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
            if let track = rtpReceiver.track {
                owner?.attachRemoteTrack(track, uid: remoteUid)
            }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChangeConnectionState newState: RTCPeerConnectionState) {
            owner?.handlePeerConnectionState(newState, remoteUid: remoteUid)
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
            owner?.handlePeerConnectionState(newState, remoteUid: remoteUid)
        }
    }

    private func flushPendingLocalIce(to remoteUid: String) {
        guard let list = pendingLocalIceByUid[remoteUid], !list.isEmpty else { return }
        pendingLocalIceByUid[remoteUid] = []
        for c in list {
            signalingClient?.sendIceCandidate(candidate: c.sdp, sdpMLineIndex: c.sdpMLineIndex, sdpMid: c.sdpMid ?? "", toUid: remoteUid)
        }
    }

    private func flushPendingRemoteIce(from remoteUid: String) {
        guard let pc = peerConnections[remoteUid] else { return }
        guard let list = pendingRemoteIceByUid[remoteUid], !list.isEmpty else { return }
        pendingRemoteIceByUid[remoteUid] = []
        for c in list { pc.add(c) }
    }
    
    private func initializeWebRTC() {
        // 初始化WebRTC
        RTCInitializeSSL()
        
        // 创建PeerConnectionFactory
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        
        // 默认 APM（回声消除等与之前相同），另挂采集后处理回调，供通话录音取本端 PCM。
        // RTCAudioProcessingConfig 未导出到 Swift，带参 init 不可见；用默认 init 再设 delegate。
        let apm = RTCDefaultAudioProcessingModule()
        apm.capturePostProcessingDelegate = captureAudioTap
        audioProcessingModule = apm
        peerConnectionFactory = RTCPeerConnectionFactory(
            bypassVoiceProcessing: false,
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory,
            audioProcessingModule: apm
        )
        
        print("WebRTC初始化成功")
    }
    
    // MARK: - 初始化
    
    func initialize() {
        print("初始化RTC引擎: appId=\(appId)")
        initializeAudioSystem()
        initializeVideoSystem()
    }
    
    private var audioEngineReady = false
    
    private func initializeAudioSystem() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            
            let engine = AVAudioEngine()
            let _ = engine.outputNode
            let hasInput = audioSession.availableInputs?.isEmpty == false
            if hasInput {
                let _ = engine.inputNode
            }
            audioEngine = engine
            audioEngineReady = true
            print("音频系统初始化成功 (hasInput=\(hasInput))")
        } catch {
            print("音频系统初始化失败: \(error)")
            audioEngineReady = false
        }
    }
    
    private func initializeVideoSystem() {
        print("视频系统初始化")
        // 视频系统初始化逻辑
    }
    
    // MARK: - 音频路由控制
    
    func setEnableSpeakerphone(_ enabled: Bool) {
        speakerphoneEnabled = enabled
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.overrideOutputAudioPort(enabled ? .speaker : .none)
            publishCurrentAudioRoute()
        } catch {
            print("设置扬声器失败: \(error)")
            eventHandler?.onError(code: SyRtcErrorCode.audioRoute, message: "设置扬声器失败")
        }
    }

    func setAudioRoute(_ route: SyRtcAudioRoute) {
        switch route {
        case .speaker:
            setEnableSpeakerphone(true)
        case .earpiece:
            setEnableSpeakerphone(false)
        case .headset, .bluetooth, .unknown:
            eventHandler?.onError(code: SyRtcErrorCode.audioRoute, message: "iOS 只能在扬声器和听筒之间切换，蓝牙和有线耳机由系统路由决定")
            publishCurrentAudioRoute()
        }
    }

    func getAudioRoute() -> SyRtcAudioRoute {
        currentAudioRoute()
    }
    
    func setDefaultAudioRouteToSpeakerphone(_ enabled: Bool) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: enabled ? [.defaultToSpeaker] : [])
            try audioSession.setActive(true)
            speakerphoneEnabled = enabled
            publishCurrentAudioRoute()
        } catch {
            print("设置默认音频路由失败: \(error)")
        }
    }
    
    func isSpeakerphoneEnabled() -> Bool {
        return speakerphoneEnabled
    }
    
    // MARK: - 音频控制

    func setClientRole(_ role: SyRtcClientRole) {
        canPublishMedia = role.canPublish
        localAudioTrack?.isEnabled = canPublishMedia && !localAudioMuted
        localVideoTrack?.isEnabled = canPublishMedia && !localVideoMuted
        screenVideoTrack?.isEnabled = canPublishMedia
        if currentChannelId != nil {
            signalingClient?.sendUserMedia(
                audioMuted: !canPublishMedia || localAudioMuted,
                videoMuted: !canPublishMedia || localVideoMuted
            )
        }
    }

    private var channelProfile: String = "communication"

    func setChannelProfile(_ profile: String) {
        channelProfile = profile
        print("设置频道场景: \(profile)")
    }

    private var volumeIndicationTimer: Timer?

    func enableAudioVolumeIndication(interval: Int, smooth: Int, reportVad: Bool) {
        volumeIntervalMs = max(0, interval)
        volumeSmooth = max(1, smooth)
        self.reportVad = reportVad
        volumeIndicationTimer?.invalidate()
        volumeIndicationTimer = nil
        guard interval > 0 else { return }
        let seconds = Double(interval) / 1000.0
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.volumeIndicationTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                self?.collectStatistics(reportVolume: true, reportQuality: false)
            }
        }
    }

    func getConnectionState() -> String {
        connectionState
    }

    func getNetworkType() -> String {
        networkType
    }

    func enableLocalAudio(_ enabled: Bool) {
        localAudioTrack?.isEnabled = enabled
        if enabled {
            guard audioEngineReady, let engine = audioEngine else {
                print("音频引擎未就绪，跳过启动")
                return
            }
            if engine.isRunning {
                print("音频引擎已在运行")
                return
            }
            let session = AVAudioSession.sharedInstance()
            if session.recordPermission != .granted {
                print("麦克风权限未授权，延迟启动音频引擎")
                session.requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted {
                            self?.safeStartAudioEngine()
                        } else {
                            print("用户拒绝麦克风权限")
                        }
                    }
                }
                return
            }
            safeStartAudioEngine()
        } else {
            audioEngine?.stop()
            print("禁用本地音频采集")
        }
    }
    
    private func safeStartAudioEngine() {
        guard let engine = audioEngine else { return }
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            print("启用本地音频采集")
        } catch {
            print("启用本地音频采集失败: \(error)")
        }
    }
    
    func sendChannelMessage(_ message: String) {
        guard currentChannelId != nil else {
            print("未加入频道，无法发送频道消息")
            return
        }
        signalingClient?.sendChannelMessage(message)
    }

    func muteLocalAudio(_ muted: Bool) {
        localAudioMuted = muted
        localAudioTrack?.isEnabled = !muted && canPublishMedia
        eventHandler?.onLocalAudioStateChanged(state: muted ? "stopped" : "recording", error: "ok")
        signalingClient?.sendUserMedia(audioMuted: muted, videoMuted: nil)
    }

    func isLocalAudioMuted() -> Bool {
        localAudioMuted
    }

    /// 本机屏蔽了该路，或对端自己静音了（`user-media`），都返回 true。
    func isRemoteAudioMuted(uid: String) -> Bool {
        muteAllRemoteAudio || remoteAudioMuted[uid] == true
    }

    func isRemoteVideoMuted(uid: String) -> Bool {
        muteAllRemoteVideo || videoMutedStates[uid] == true
    }
    
    func muteRemoteAudioStream(uid: String, muted: Bool) {
        remoteAudioMuted[uid] = muted
        userVolumes[uid] = muted ? 0 : 100
        remoteAudioTracks[uid]?.isEnabled = !muted && !muteAllRemoteAudio
    }
    
    func muteAllRemoteAudioStreams(_ muted: Bool) {
        muteAllRemoteAudio = muted
        playbackVolume = muted ? 0 : 100
        for (uid, track) in remoteAudioTracks {
            track.isEnabled = !muted && remoteAudioMuted[uid] != true
        }
    }
    
    func adjustUserPlaybackSignalVolume(uid: String, volume: Int) {
        userVolumes[uid] = min(max(volume, 0), 100)
        print("用户 \(uid) 音量调整为: \(volume)")
    }
    
    func adjustPlaybackSignalVolume(_ volume: Int) {
        playbackVolume = min(max(volume, 0), 100)
        print("播放音量调整为: \(volume)")
    }

    func adjustRecordingSignalVolume(_ volume: Int) {
        let v = min(max(volume, 0), 255)
        print("adjustRecordingSignalVolume=\(v) (limited support)")
    }
    
    // MARK: - Token刷新
    
    func renewToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            eventHandler?.onError(code: SyRtcErrorCode.invalidArgument, message: "token 不能为空")
            return
        }
        currentToken = trimmed
        scheduleTokenPrivilegeWatch(token: trimmed)
        guard let channelId = currentChannelId, let uid = currentUid else {
            return
        }
        // 信令 URL 上的 token 才是服务端校验依据。重连 WebSocket，不拆掉已有 PeerConnection。
        let wasInChannel = signalingClient != nil && hasFiredJoinSuccess
        pendingRejoin = wasInChannel
        openSignaling(channelId: channelId, uid: uid, token: trimmed)
    }

    func getQualityTier() -> String {
        currentQualityTier
    }

    /// 按控制面档位切换本地采集参数。`audio|sd|hd|fhd`。
    /// 服务端权益切换请另外调用 `SyRoomService.switchQualityTier`（需要用户 JWT）。
    func setQualityTier(_ tier: String) {
        guard let parsed = SyRtcQualityTier.parse(tier) else {
            eventHandler?.onError(code: SyRtcErrorCode.invalidArgument, message: "未知画质档位: \(tier)，可选 audio/sd/hd/fhd")
            return
        }
        currentQualityTier = parsed.rawValue
        switch parsed {
        case .audio:
            setAudioQuality("low")
            isVideoEnabled = false
            localVideoTrack?.isEnabled = false
        case .sd:
            setAudioQuality("medium")
            enableVideo()
            setVideoEncoderConfiguration(width: 640, height: 360, frameRate: 15, bitrate: 400)
        case .hd:
            setAudioQuality("high")
            enableVideo()
            setVideoEncoderConfiguration(width: 1280, height: 720, frameRate: 15, bitrate: 1200)
        case .fhd:
            setAudioQuality("ultra")
            enableVideo()
            setVideoEncoderConfiguration(width: 1920, height: 1080, frameRate: 30, bitrate: 2500)
        }
    }

    private func cancelTokenPrivilegeWatch() {
        tokenWarnWork?.cancel()
        tokenExpireWork?.cancel()
        tokenWarnWork = nil
        tokenExpireWork = nil
    }

    /// Token 带过期时间（服务端 `expireAt` 或 JWT `exp`）时，过期前 30 秒回调 `onTokenPrivilegeWillExpire`，到期回调 `onRequestToken`。与 Android 相同。
    private let tokenExpiryDedupe = SyRtcTokenExpiryDedupe()

    private func fireLocalTokenEvent(_ kind: SyRtcTokenExpiryDedupe.Kind) {
        guard currentChannelId != nil, tokenExpiryDedupe.shouldFire(kind) else { return }
        switch kind {
        case .willExpire: eventHandler?.onTokenPrivilegeWillExpire()
        case .expired: eventHandler?.onRequestToken()
        }
    }

    private func scheduleTokenPrivilegeWatch(token: String) {
        cancelTokenPrivilegeWatch()
        let exp = SyRtcTokenExpiry.expireAt(token)
        tokenExpiryDedupe.reset(currentExpireAt: exp)
        guard let exp else { return }
        let d = SyRtcTokenExpiry.delays(expireAt: exp, now: Date().timeIntervalSince1970)
        if d.expire <= 0 {
            DispatchQueue.main.async { [weak self] in self?.fireLocalTokenEvent(.expired) }
            return
        }
        let warn = DispatchWorkItem { [weak self] in self?.fireLocalTokenEvent(.willExpire) }
        let expired = DispatchWorkItem { [weak self] in self?.fireLocalTokenEvent(.expired) }
        tokenWarnWork = warn
        tokenExpireWork = expired
        DispatchQueue.main.asyncAfter(deadline: .now() + d.warn, execute: warn)
        DispatchQueue.main.asyncAfter(deadline: .now() + d.expire, execute: expired)
    }
    
    // MARK: - 音频配置
    
    func setAudioProfile(_ profile: String, scenario: String) {
        print("设置音频配置: profile=\(profile), scenario=\(scenario)")
        
        // 根据profile设置音频参数
        let profileLower = profile.lowercased()
        switch profileLower {
        case "speech_low_quality", "low":
            audioSampleRate = 16000
            audioBitrate = 16000
        case "speech_standard", "standard":
            audioSampleRate = 24000
            audioBitrate = 24000
        case "music_standard", "medium":
            audioSampleRate = 48000
            audioBitrate = 48000
        case "music_standard_stereo", "high":
            audioSampleRate = 48000
            audioBitrate = 64000
        case "music_high_quality", "ultra":
            audioSampleRate = 48000
            audioBitrate = 128000
        default:
            audioSampleRate = 48000
            audioBitrate = 48000
        }
        
        // 根据scenario设置音频模式
        let scenarioLower = scenario.lowercased()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [])
            
            switch scenarioLower {
            case "game_streaming":
                try audioSession.setMode(.videoChat)
                try audioSession.overrideOutputAudioPort(.speaker)
            case "chatroom_entertainment":
                try audioSession.setMode(.voiceChat)
                try audioSession.overrideOutputAudioPort(.none)
            case "education":
                try audioSession.setMode(.voiceChat)
                try audioSession.overrideOutputAudioPort(.speaker)
            case "default", "chatroom_gaming":
                try audioSession.setMode(.voiceChat)
            default:
                try audioSession.setMode(.voiceChat)
            }
            
            try audioSession.setActive(true)
        } catch {
            print("设置音频模式失败: \(error)")
        }
        
        // 重新初始化音频系统以应用新配置
        reinitializeAudioSystem(sampleRate: audioSampleRate)
        
        print("音频配置已更新: \(audioSampleRate)Hz, \(audioBitrate)bps, scenario=\(scenario)")
    }
    
    func enableAudio() {
        localAudioTrack?.isEnabled = true
        do {
            try audioEngine?.start()
            print("启用音频模块")
        } catch {
            print("启用音频模块失败: \(error)")
        }
    }
    
    func disableAudio() {
        localAudioTrack?.isEnabled = false
        audioEngine?.stop()
        print("禁用音频模块")
    }
    
    // MARK: - 音频设备管理
    
    func enumerateRecordingDevices() -> [AudioDeviceInfo] {
        let inputs = AVAudioSession.sharedInstance().availableInputs ?? []
        return inputs.map { AudioDeviceInfo(deviceId: $0.uid, deviceName: $0.portName) }
    }
    
    func enumeratePlaybackDevices() -> [AudioDeviceInfo] {
        // 只有这两项会真正改 AVAudioSession。蓝牙和有线耳机由系统路由决定，见 onAudioRoutingChanged。
        return [
            AudioDeviceInfo(deviceId: "speaker", deviceName: "扬声器"),
            AudioDeviceInfo(deviceId: "earpiece", deviceName: "听筒")
        ]
    }
    
    func setRecordingDevice(_ deviceId: String) -> Int {
        let session = AVAudioSession.sharedInstance()
        guard let port = session.availableInputs?.first(where: { $0.uid == deviceId }) else {
            return -1
        }
        do {
            try session.setPreferredInput(port)
            return 0
        } catch {
            print("设置录音设备失败: \(error)")
            return -1
        }
    }
    
    func setPlaybackDevice(_ deviceId: String) -> Int {
        switch deviceId {
        case "speaker":
            setEnableSpeakerphone(true)
            return 0
        case "earpiece":
            setEnableSpeakerphone(false)
            return 0
        default:
            return -1
        }
    }
    
    func getRecordingDeviceVolume() -> Int {
        // iOS 不提供 inputVolume（输入音量）读取能力
        return 0
    }
    
    func setRecordingDeviceVolume(_ volume: Int) {
        // iOS 不支持直接设置输入音量
        print("设置采集音量: \(volume)")
    }
    
    func getPlaybackDeviceVolume() -> Int {
        return Int(AVAudioSession.sharedInstance().outputVolume * 100)
    }
    
    func setPlaybackDeviceVolume(_ volume: Int) {
        // iOS 不支持直接设置输出音量
        print("设置播放音量: \(volume)")
    }
    
    // MARK: - 视频控制
    
    func enableVideo() {
        isVideoEnabled = true
        print("启用视频模块")
    }
    
    func disableVideo() {
        isVideoEnabled = false
        print("禁用视频模块")
    }
    
    func enableLocalVideo(_ enabled: Bool) {
        isLocalVideoEnabled = enabled
        print("启用本地视频: \(enabled)")
    }
    
    func setVideoEncoderConfiguration(_ config: VideoEncoderConfiguration) {
        print("设置视频编码配置: \(config.width)x\(config.height), \(config.frameRate)fps, \(config.bitrate)bps")
        
        // 保存配置
        currentVideoConfig = config
        
        // 应用视频编码配置
        applyVideoEncoderConfiguration(config)
    }
    
    private func applyVideoEncoderConfiguration(_ config: VideoEncoderConfiguration) {
        // 验证配置参数
        let width = max(160, min(3840, config.width))
        let height = max(120, min(2160, config.height))
        let frameRate = max(1, min(60, config.frameRate))
        let bitrate = config.bitrate > 0 ? max(100, min(10000, config.bitrate)) : calculateBitrate(width: width, height: height, frameRate: frameRate)
        
        print("应用视频编码配置: \(width)x\(height), \(frameRate)fps, \(bitrate)kbps")
        
        cameraVideoSource?.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: Int32(frameRate))
        screenVideoSource?.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: Int32(frameRate))
        applyVideoBitrateToSenders()
        print("视频编码器配置已更新: \(width)x\(height), \(frameRate)fps, \(bitrate)kbps")
    }
    
    private func calculateBitrate(width: Int, height: Int, frameRate: Int) -> Int {
        // 根据分辨率和帧率计算推荐码率（kbps）
        let pixels = width * height
        let baseBitrate: Int
        if pixels <= 640 * 480 {
            baseBitrate = 400
        } else if pixels <= 1280 * 720 {
            baseBitrate = 800
        } else if pixels <= 1920 * 1080 {
            baseBitrate = 2000
        } else {
            baseBitrate = 5000
        }
        return max(100, min(10000, baseBitrate * frameRate / 30))
    }
    
    func setVideoEncoderConfiguration(width: Int, height: Int, frameRate: Int, bitrate: Int) {
        let config = VideoEncoderConfiguration(
            width: width,
            height: height,
            frameRate: frameRate,
            bitrate: bitrate
        )
        setVideoEncoderConfiguration(config)
    }
    
    func setAudioQuality(_ quality: String) {
        print("设置音频质量: \(quality)")
        
        let qualityLower = quality.lowercased()
        let (sampleRate, bitrate): (Int, Int)
        
        switch qualityLower {
        case "low":
            // 低质量：降低采样率、码率，减少处理开销
            sampleRate = 16000
            bitrate = 16000
        case "medium":
            // 中等质量：标准采样率、码率
            sampleRate = 24000
            bitrate = 32000
        case "high":
            // 高质量：较高采样率、码率
            sampleRate = 48000
            bitrate = 64000
        case "ultra":
            // 超高质量：最高采样率、码率
            sampleRate = 48000
            bitrate = 128000
        default:
            print("未知的音频质量等级: \(quality)，使用默认中等质量")
            sampleRate = 24000
            bitrate = 32000
        }
        
        // 保存配置
        currentAudioQuality = qualityLower
        audioSampleRate = sampleRate
        audioBitrate = bitrate
        
        print("应用音频质量设置: \(sampleRate)Hz采样率, \(bitrate)bps码率")
        
        // 重新初始化音频系统以应用新配置
        reinitializeAudioSystem(sampleRate: sampleRate)
    }
    
    private func reinitializeAudioSystem(sampleRate: Int) {
        do {
            audioEngine?.stop()
            
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setPreferredSampleRate(Double(sampleRate))
            try audioSession.setActive(true)
            
            let engine = AVAudioEngine()
            let hasInput = audioSession.availableInputs?.isEmpty == false
            
            if hasInput {
                let inputNode = engine.inputNode
                let inputFormat = inputNode.inputFormat(forBus: 0)
                let outputNode = engine.mainMixerNode
                let outputFormat = outputNode.outputFormat(forBus: 0)
                print("音频系统已重新初始化: \(sampleRate)Hz, 输入格式: \(inputFormat), 输出格式: \(outputFormat)")
            } else {
                print("音频系统重新初始化 (无输入设备): \(sampleRate)Hz")
            }
            
            audioEngine = engine
            audioEngineReady = true
        } catch {
            print("重新初始化音频系统失败: \(error)")
            audioEngineReady = false
        }
    }
    
    func startPreview() {
        if customVideoCaptureEnabled {
            eventHandler?.onError(code: SyRtcErrorCode.customCapture, message: "自定义采集已开启，请用 sendCustomVideoFrame 推帧")
            return
        }
        if !isVideoEnabled {
            enableVideo()
        }
        if isPreviewing, videoCapturer is RTCCameraVideoCapturer {
            return
        }
        guard let track = ensureCameraVideoTrack() else {
            eventHandler?.onError(code: SyRtcErrorCode.camera, message: "视频源未就绪")
            return
        }
        isPreviewing = true
        if let config = currentVideoConfig {
            applyVideoEncoderConfiguration(config)
        }
        let relay = ensureCameraFrameRelay()
        let capturer = RTCCameraVideoCapturer(delegate: relay)
        videoCapturer = capturer
        let started = startCamera(capturer, front: preferFrontCamera)
        if started {
            eventHandler?.onLocalVideoStateChanged(state: "capturing", error: "ok")
        }
        attachPublishedVideo(track)
    }
    
    func stopPreview() {
        if !isPreviewing && !customVideoCaptureEnabled {
            return
        }
        isPreviewing = false
        customVideoCaptureEnabled = false
        if let capturer = videoCapturer as? RTCCameraVideoCapturer {
            capturer.stopCapture()
        }
        videoCapturer = nil
        if let track = localVideoTrack {
            removePublishedTrack(track)
        }
        localVideoTrack?.isEnabled = false
        localVideoTrack = nil
        cameraVideoSource = nil
        eventHandler?.onLocalVideoStateChanged(state: "stopped", error: "ok")
    }

    func switchCamera() {
        useFrontCamera(!preferFrontCamera)
    }

    func useFrontCamera(_ front: Bool) {
        preferFrontCamera = front
        guard !customVideoCaptureEnabled, let capturer = videoCapturer as? RTCCameraVideoCapturer else { return }
        _ = startCamera(capturer, front: front)
    }

    func setVideoFrameProcessor(_ processor: SyRtcVideoFrameProcessor?) {
        videoFrameProcessor = processor
    }

    func enableCustomVideoCapture(_ enabled: Bool) {
        if enabled {
            if let capturer = videoCapturer as? RTCCameraVideoCapturer {
                capturer.stopCapture()
            }
            customVideoCaptureEnabled = true
            isVideoEnabled = true
            isPreviewing = true
            guard let source = ensureCameraVideoSource(), let track = ensureCameraVideoTrack() else {
                eventHandler?.onError(code: SyRtcErrorCode.customCapture, message: "自定义采集视频源未就绪")
                return
            }
            videoCapturer = RTCVideoCapturer(delegate: source)
            attachPublishedVideo(track)
            eventHandler?.onLocalVideoStateChanged(state: "capturing", error: "custom")
        } else if customVideoCaptureEnabled {
            stopPreview()
        }
    }

    func sendCustomVideoFrame(pixelBuffer: CVPixelBuffer, rotation: Int, timestampNs: Int64) {
        guard customVideoCaptureEnabled, let source = cameraVideoSource, let capturer = videoCapturer else {
            eventHandler?.onError(code: SyRtcErrorCode.customCapture, message: "请先 enableCustomVideoCapture(true)")
            return
        }
        let processed = videoFrameProcessor?(pixelBuffer, rotation) ?? pixelBuffer
        let buffer = RTCCVPixelBuffer(pixelBuffer: processed)
        let ts = timestampNs > 0 ? timestampNs : Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let frame = RTCVideoFrame(buffer: buffer, rotation: Self.rtcRotation(rotation), timeStampNs: ts)
        source.capturer(capturer, didCapture: frame)
    }

    func setStreamExtraInfo(_ info: String) {
        if info.utf8.count > 1024 {
            eventHandler?.onError(code: SyRtcErrorCode.invalidArgument, message: "流附加信息超过 1024 字节")
            return
        }
        streamExtraInfo = info
        guard currentChannelId != nil else { return }
        signalingClient?.sendChannelMessage(streamExtraPrefix + info)
    }

    func getStreamExtraInfo() -> String {
        streamExtraInfo
    }

    func isLocalVideoMuted() -> Bool {
        localVideoMuted
    }
    
    func muteLocalVideoStream(_ muted: Bool) {
        localVideoMuted = muted
        videoMutedStates["local"] = muted
        localVideoTrack?.isEnabled = !muted && canPublishMedia
        screenVideoTrack?.isEnabled = !muted && canPublishMedia
        eventHandler?.onLocalVideoStateChanged(state: muted ? "stopped" : "capturing", error: "ok")
        signalingClient?.sendUserMedia(audioMuted: nil, videoMuted: muted)
    }
    
    func muteRemoteVideoStream(uid: String, muted: Bool) {
        videoMutedStates[uid] = muted
        remoteVideoTracks[uid]?.isEnabled = !muted && !muteAllRemoteVideo
    }
    
    func muteAllRemoteVideoStreams(_ muted: Bool) {
        muteAllRemoteVideo = muted
        for (uid, track) in remoteVideoTracks {
            track.isEnabled = !muted && videoMutedStates[uid] != true
        }
    }
    
    func setupLocalVideo(viewId: Int) {
        print("设置本地视频视图(viewId): \(viewId) — prefer setupLocalVideo(view:) on iOS")
    }

    func setupRemoteVideo(uid: String, viewId: Int) {
        print("设置远端视频视图(viewId): uid=\(uid), viewId=\(viewId) — prefer setupRemoteVideo(uid:view:)")
        if let track = remoteVideoTracks[uid], let muted = videoMutedStates[uid] {
            track.isEnabled = !muted
        }
    }

#if canImport(UIKit)
    func setupLocalVideo(view: UIView) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.localContainerView = view
            self.localRenderer?.removeFromSuperview()
            let renderer = RTCMTLVideoView(frame: view.bounds)
            renderer.videoContentMode = .scaleAspectFill
            renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(renderer)
            self.localRenderer = renderer
            if let track = self.localVideoTrack {
                track.add(renderer)
            }
            print("本地视频 UIView 已绑定")
        }
    }

    func setupRemoteVideo(uid: String, view: UIView) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.remoteContainerViews[uid] = view
            self.remoteRenderers[uid]?.removeFromSuperview()
            let renderer = RTCMTLVideoView(frame: view.bounds)
            renderer.videoContentMode = .scaleAspectFill
            renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(renderer)
            self.remoteRenderers[uid] = renderer
            if let track = self.remoteVideoTracks[uid] {
                track.add(renderer)
                if let muted = self.videoMutedStates[uid] {
                    track.isEnabled = !muted
                }
            }
            print("远端视频 UIView 已绑定: uid=\(uid)")
        }
    }
#endif
    
    // MARK: - 屏幕共享
    
    func startScreenCapture(_ config: ScreenCaptureConfiguration) {
        if isScreenCapturing {
            return
        }
        guard ensureScreenVideoTrack() != nil else {
            eventHandler?.onError(code: SyRtcErrorCode.screenShare, message: "屏幕共享视频源未就绪")
            return
        }
        screenCaptureConfig = config
        if config.width > 0, config.height > 0 {
            let fps = max(1, config.frameRate)
            screenVideoSource?.adaptOutputFormat(toWidth: Int32(config.width), height: Int32(config.height), fps: Int32(fps))
        }
        let screenRecorder = RPScreenRecorder.shared()
        self.screenRecorder = screenRecorder
        screenRecorder.isMicrophoneEnabled = false
        screenRecorder.isCameraEnabled = false
        screenRecorder.startCapture { [weak self] sampleBuffer, bufferType, error in
            guard let self = self, error == nil, bufferType == .video else { return }
            self.pushScreenSampleBuffer(sampleBuffer)
        } completionHandler: { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.isScreenCapturing = false
                self.screenRecorder = nil
                self.eventHandler?.onError(code: SyRtcErrorCode.screenShare, message: "启动屏幕录制失败: \(error.localizedDescription)")
                return
            }
            self.isScreenCapturing = true
            if let track = self.screenVideoTrack {
                self.attachPublishedVideo(track)
            }
            self.eventHandler?.onLocalVideoStateChanged(state: "capturing", error: "screen")
        }
    }

    func pushScreenSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if screenVideoTrack == nil {
            _ = ensureScreenVideoTrack()
        }
        guard let source = screenVideoSource else { return }
        if screenCapturer == nil {
            screenCapturer = RTCVideoCapturer(delegate: source)
        }
        guard let capturer = screenCapturer else { return }
        let processed = videoFrameProcessor?(pixel, 0) ?? pixel
        let buffer = RTCCVPixelBuffer(pixelBuffer: processed)
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let ts = seconds.isFinite && seconds > 0
            ? Int64(seconds * 1_000_000_000)
            : Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let frame = RTCVideoFrame(buffer: buffer, rotation: Self.rtcRotation(0), timeStampNs: ts)
        source.capturer(capturer, didCapture: frame)
    }
    
    func stopScreenCapture() {
        if !isScreenCapturing && screenVideoTrack == nil {
            return
        }
        isScreenCapturing = false
        screenRecorder?.stopCapture { _ in }
        screenRecorder = nil
        screenCaptureConfig = nil
        if let track = screenVideoTrack {
            removePublishedTrack(track)
        }
        screenVideoTrack = nil
        screenVideoSource = nil
        screenCapturer = nil
        eventHandler?.onLocalVideoStateChanged(state: "stopped", error: "screen")
    }
    
    func updateScreenCaptureConfiguration(_ config: ScreenCaptureConfiguration) {
        if !isScreenCapturing {
            print("屏幕共享未在进行中，无法更新配置")
            return
        }
        
        screenCaptureConfig = config
        print("更新屏幕共享配置: \(config.width)x\(config.height), \(config.frameRate)fps")
        
        // 更新屏幕录制配置
        // ReplayKit不支持动态更新配置，需要重新启动
        if isScreenCapturing {
            stopScreenCapture()
            startScreenCapture(config)
        }
    }
    
    // MARK: - 视频增强
    
    func setBeautyEffectOptions(_ options: BeautyOptions) {
        beautyOptions = options
            print("美颜参数已记录。SDK 不内置美颜渲染，请用 setVideoFrameProcessor 处理 CVPixelBuffer。enabled=\(options.enabled)")
        
        // 应用美颜效果
        if options.enabled {
            // 创建或更新美颜滤镜
            if beautyFilter == nil {
                beautyFilter = BeautyFilter()
            }
            beautyFilter?.setLighteningLevel(options.lighteningLevel)
            beautyFilter?.setSmoothnessLevel(options.smoothnessLevel)
            beautyFilter?.setRednessLevel(options.rednessLevel)
            beautyFilter?.enable()
            
            // 将美颜滤镜应用到视频轨道
            if let track = localVideoTrack {
                // 使用CoreImage进行美颜处理
                // 实际实现需要创建自定义VideoSink进行滤镜处理
            }
            
            print("美颜效果已启用")
        } else {
            beautyFilter?.disable()
            beautyFilter = nil
            print("美颜效果已禁用")
        }
    }
    
    func takeSnapshot(uid: String, filePath: String) {
        print("视频截图: uid=\(uid), path=\(filePath)")
        
        // 从视频轨道截取画面
        let videoTrack: RTCVideoTrack? = (uid == "local") ? localVideoTrack : nil
        
        if let track = videoTrack {
            // 使用WebRTC的VideoRenderer捕获帧
            let frameCapturer = FrameCapturer { [weak self] frame in
                if let image = self?.frameToImage(frame) {
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        try? data.write(to: URL(fileURLWithPath: filePath))
                        print("截图已保存: \(filePath)")
                    }
                }
            }
            track.add(frameCapturer)
            // 等待一帧后移除
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                track.remove(frameCapturer)
            }
        } else {
            print("未找到视频轨道: uid=\(uid)")
        }
    }
    
    // MARK: - 音频混音
    
    func startAudioMixing(_ config: AudioMixingConfiguration) {
        if audioMixingState == .playing {
            print("音频混音已在进行中")
            stopAudioMixing()
        }
        
        audioMixingConfig = config
        audioMixingState = .playing
        print("开始音频混音: \(config.filePath), loopback=\(config.loopback)")
        
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: config.filePath))
            player.numberOfLoops = config.cycle > 1 ? config.cycle - 1 : 0
            player.volume = 0.5 // 默认音量
            player.currentTime = TimeInterval(config.startPos) / 1000.0
            player.play()
            audioMixingPlayer = player
            print("音频混音播放已开始")
        } catch {
            print("启动音频混音失败: \(error)")
            audioMixingState = .stopped
        }
    }
    
    func stopAudioMixing() {
        if audioMixingState == .stopped {
            return
        }
        
        audioMixingState = .stopped
        print("停止音频混音")
        
        audioMixingPlayer?.stop()
        audioMixingPlayer = nil
        audioMixingConfig = nil
    }
    
    func pauseAudioMixing() {
        if audioMixingState != .playing {
            print("音频混音未在播放中，无法暂停")
            return
        }
        
        audioMixingState = .paused
        print("暂停音频混音")
        
        audioMixingPlayer?.pause()
    }
    
    func resumeAudioMixing() {
        if audioMixingState != .paused {
            print("音频混音未在暂停状态，无法恢复")
            return
        }
        
        audioMixingState = .playing
        print("恢复音频混音")
        
        audioMixingPlayer?.play()
    }
    
    func adjustAudioMixingVolume(_ volume: Int) {
        let volumeFloat = Float(min(max(volume, 0), 100)) / 100.0
        print("调整混音音量: \(volume)")
        
        audioMixingPlayer?.volume = volumeFloat
    }
    
    func getAudioMixingCurrentPosition() -> Int {
        return Int((audioMixingPlayer?.currentTime ?? 0) * 1000)
    }
    
    func setAudioMixingPosition(_ position: Int) {
        print("设置混音位置: \(position)")
        
        audioMixingPlayer?.currentTime = TimeInterval(position) / 1000.0
    }
    
    // MARK: - 音效
    
    func playEffect(soundId: Int, config: AudioEffectConfiguration) {
        // 停止已存在的相同音效
        stopEffect(soundId)
        
        print("播放音效: soundId=\(soundId), file=\(config.filePath), loopCount=\(config.loopCount)")
        
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: config.filePath))
            player.numberOfLoops = config.loopCount > 1 || config.loopCount == -1 ? config.loopCount - 1 : 0
            player.currentTime = TimeInterval(config.startPos) / 1000.0
            player.play()
            effectPlayers[soundId] = player
            print("音效播放已开始: soundId=\(soundId)")
        } catch {
            print("播放音效失败: soundId=\(soundId), error=\(error)")
        }
    }
    
    func stopEffect(_ soundId: Int) {
        effectPlayers[soundId]?.stop()
        effectPlayers.removeValue(forKey: soundId)
        print("停止音效: \(soundId)")
    }
    
    func stopAllEffects() {
        effectPlayers.values.forEach { $0.stop() }
        effectPlayers.removeAll()
        print("停止所有音效")
    }
    
    func setEffectsVolume(_ volume: Int) {
        let volumeFloat = Float(min(max(volume, 0), 100)) / 100.0
        print("设置音效音量: \(volume)")
        
        effectPlayers.values.forEach { $0.volume = volumeFloat }
    }
    
    func preloadEffect(_ soundId: Int, filePath: String) {
        print("预加载音效: soundId=\(soundId), file=\(filePath)")
        
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: filePath))
            player.prepareToPlay()
            effectPlayers[soundId] = player
            print("音效预加载完成: soundId=\(soundId)")
        } catch {
            print("预加载音效失败: soundId=\(soundId), error=\(error)")
        }
    }
    
    func unloadEffect(_ soundId: Int) {
        stopEffect(soundId)
        print("卸载音效: \(soundId)")
    }
    
    // MARK: - 音频录制
    
    func startAudioRecording(_ config: AudioRecordingConfiguration) -> Int {
        if audioRecorder != nil || callRecorder != nil {
            print("音频录制已在进行中")
            return -1
        }
        guard let format = SyRtcRecordingFormat.from(codec: config.codecType) else {
            eventHandler?.onError(code: SyRtcErrorCode.invalidArgument, message: "不支持的录音格式 \(config.codecType)，可选 aac（.m4a）或 wav")
            return -1
        }
        guard !config.filePath.isEmpty, (8000...48000).contains(config.sampleRate) else {
            eventHandler?.onError(code: SyRtcErrorCode.invalidArgument, message: "filePath 不能为空，sampleRate 需在 8000–48000")
            return -1
        }
        audioRecordingConfig = config
        let fileURL = URL(fileURLWithPath: config.filePath)
        print("开始音频录制: \(config.filePath), \(config.sampleRate)Hz, codec=\(config.codecType)")

        if signalingClient != nil, localAudioTrack != nil {
            // 频道内：不另开录音器（与 WebRTC 抢采集会录成静音），用 WebRTC 管线里的 PCM。
            do {
                let rec = try SyRtcCallAudioRecorder(url: fileURL, format: format,
                                                     sampleRate: config.sampleRate, bitrate: config.aacBitrate)
                callRecorder = rec
                if config.includeLocal {
                    captureAudioTap.onPcm = { [weak self, weak rec] pcm, rate in
                        guard let self = self, let rec = rec else { return }
                        if self.localAudioMuted || !self.canPublishMedia { return }
                        rec.push(SyRtcCallAudioRecorder.localSource, mono: pcm, sourceRate: rate)
                    }
                }
                if config.includeRemote {
                    for (uid, track) in remoteAudioTracks { attachRemoteAudioTap(uid: uid, track: track) }
                }
                rec.start()
                return 0
            } catch {
                print("启动通话录音失败: \(error)")
                detachAllRecordingTaps()
                callRecorder = nil
                audioRecordingConfig = nil
                return -1
            }
        }

        guard format == .aacM4a else {
            eventHandler?.onError(code: SyRtcErrorCode.invalidArgument, message: "未加入频道时只支持 aac")
            audioRecordingConfig = nil
            return -1
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: config.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: config.aacBitrate,
        ]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.record()
            audioRecorder = recorder
            print("麦克风录音已开始（未在频道内）")
            return 0
        } catch {
            print("启动音频录制失败: \(error)")
            audioRecorder = nil
            audioRecordingConfig = nil
            return -1
        }
    }

    private func attachRemoteAudioTap(uid: String, track: RTCAudioTrack) {
        guard let rec = callRecorder, audioRecordingConfig?.includeRemote == true else { return }
        if let old = remoteAudioTaps.removeValue(forKey: uid) { track.remove(old) }
        let tap = SyRtcRemoteAudioTap { [weak self, weak rec] pcm, rate in
            guard let self = self, let rec = rec else { return }
            // 本端静音了该远端（听不到）就不录他。
            if self.muteAllRemoteAudio || self.remoteAudioMuted[uid] == true { return }
            rec.push(uid, mono: pcm, sourceRate: rate)
        }
        remoteAudioTaps[uid] = tap
        track.add(tap)
    }

    private func detachRemoteAudioTap(uid: String) {
        if let tap = remoteAudioTaps.removeValue(forKey: uid) { remoteAudioTracks[uid]?.remove(tap) }
        callRecorder?.removeSource(uid)
    }

    private func detachAllRecordingTaps() {
        captureAudioTap.onPcm = nil
        for (uid, tap) in remoteAudioTaps { remoteAudioTracks[uid]?.remove(tap) }
        remoteAudioTaps.removeAll()
    }

    func stopAudioRecording() {
        if let rec = callRecorder {
            detachAllRecordingTaps()
            callRecorder = nil
            audioRecordingConfig = nil
            rec.stop()
            print("通话录音已停止")
            return
        }
        if audioRecorder == nil {
            print("音频录制未在进行中")
            return
        }
        audioRecorder?.stop()
        audioRecorder = nil
        audioRecordingConfig = nil
        print("音频录制已停止")
    }
    
    // MARK: - 数据流
    
    func createDataStream(reliable: Bool, ordered: Bool) -> Int {
        let streamId = nextDataStreamId
        nextDataStreamId += 1
        dataStreamConfigs[streamId] = (reliable, ordered)
        dataStreams[streamId] = true
        for uid in peerConnections.keys where uid != "default" {
            guard let pc = peerConnections[uid] else { continue }
            ensureDataChannel(streamId: streamId, remoteUid: uid, peerConnection: pc)
            forceOffer(to: uid)
        }
        return streamId
    }
    
    private class DataChannelDelegate: NSObject, RTCDataChannelDelegate {
        let streamId: Int
        let remoteUid: String
        weak var engine: SyRtcEngineImpl?
        
        init(streamId: Int, remoteUid: String, engine: SyRtcEngineImpl) {
            self.streamId = streamId
            self.remoteUid = remoteUid
            self.engine = engine
        }
        
        func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
            let data = buffer.data
            let uid = remoteUid
            let sid = streamId
            let sei = SyRtcWire.unwrapSei(data)
            DispatchQueue.main.async { [weak engine] in
                guard let handler = engine?.eventHandler else { return }
                handler.onStreamMessage(uid: uid, streamId: sid, data: data)
                if let sei { handler.onSeiMessage(uid: uid, streamId: sid, data: sei) }
            }
        }
        
        func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}
    }
    
    func sendStreamMessage(streamId: Int, data: Data) {
        _ = sendOnDataChannels(streamId: streamId, data: data)
    }

    /// DataChannel 上发 `SYSEI` 前缀消息（与 Android `sendSei` 同格式）。
    /// 返回 0 已写入打开的通道；-1 流不存在或通道未打开（与 Android 相同）。
    func sendSei(streamId: Int, data: Data) -> Int {
        sendOnDataChannels(streamId: streamId, data: SyRtcWire.wrapSei(data))
    }

    private func sendOnDataChannels(streamId: Int, data: Data) -> Int {
        guard dataStreamConfigs[streamId] != nil else {
            eventHandler?.onStreamMessageError(uid: currentUid ?? "", streamId: streamId, code: 2, missed: 0, cached: 0)
            return -1
        }
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        var sent = 0
        for channels in dataChannelsByPeer.values {
            guard let channel = channels[streamId], channel.readyState == .open else { continue }
            channel.sendData(buffer)
            sent += 1
        }
        if sent == 0 {
            eventHandler?.onStreamMessageError(uid: currentUid ?? "", streamId: streamId, code: 1, missed: 0, cached: 0)
            return -1
        }
        return 0
    }
    
    
    // MARK: - 清理
    
    func release() {
        if callRecorder != nil { stopAudioRecording() }
        signalingGeneration += 1
        reconnectWork?.cancel()
        resetIceRecovery()
        stopQualityMonitor()
        volumeIndicationTimer?.invalidate()
        volumeIndicationTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        routeObserver = nil
        SyRtcReplayKitBridge.shared.onVideoSampleBuffer = nil
        cancelTokenPrivilegeWatch()
        pendingRejoin = false
        signalingClient?.disconnect(sendLeave: true)
        signalingClient = nil
        audioEngine?.stop()
        localVideoTrack = nil
        screenVideoTrack = nil
        localAudioTrack = nil
        videoCapturer = nil
        peerConnectionFactory = nil
        screenRecorder?.stopCapture { _ in }
        screenRecorder = nil
        for channels in dataChannelsByPeer.values {
            channels.values.forEach { $0.close() }
        }
        dataChannelsByPeer.removeAll()
        dataChannelMap.removeAll()
        remoteVideoTracks.removeAll()
        remoteAudioTracks.removeAll()
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        effects.removeAll()
        userVolumes.removeAll()
        connectionState = "disconnected"
    }
}

// MARK: - 网格媒体、统计、重连

extension SyRtcEngineImpl {
    fileprivate func startMonitorsIfNeeded() {
        guard !monitorsStarted else { return }
        monitorsStarted = true
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let type: String
            if path.status != .satisfied {
                type = "none"
            } else if path.usesInterfaceType(.wifi) {
                type = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                type = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = "ethernet"
            } else {
                type = "unknown"
            }
            DispatchQueue.main.async {
                self?.networkType = type
            }
        }
        monitor.start(queue: DispatchQueue(label: "sy.rtc.path"))
        pathMonitor = monitor
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.publishCurrentAudioRoute()
        }
        SyRtcReplayKitBridge.shared.onVideoSampleBuffer = { [weak self] sample in
            self?.pushScreenSampleBuffer(sample)
        }
    }

    fileprivate func openSignaling(channelId: String, uid: String, token: String) {
        signalingGeneration += 1
        let generation = signalingGeneration
        signalingClient?.disconnect(sendLeave: false)
        signalingClient = SyRtcSignalingClient(
            signalingUrl: signalingUrl,
            channelId: channelId,
            uid: uid,
            token: token,
            onMessage: { [weak self] type, data in
                self?.handleSignalingMessage(type: type, data: data, channelId: channelId)
            },
            onFailure: { [weak self] in
                guard let self, self.signalingGeneration == generation else { return }
                self.handleSignalingFailure()
            }
        )
        signalingClient?.connect()
    }

    fileprivate func handleSignalingFailure() {
        guard currentChannelId != nil else { return }
        reconnectWork?.cancel()
        reconnectAttempt += 1
        if reconnectAttempt > SyRtcReconnectPolicy.maxAttempts {
            connectionState = "failed"
            reconnectWorkWasSignaling = false
            eventHandler?.onConnectionStateChanged(state: "failed", reason: "signaling")
            eventHandler?.onReconnectFailed(reason: "signaling")
            eventHandler?.onError(code: SyRtcErrorCode.reconnectFailed, message: "信令重连失败")
            return
        }
        let delayMs = SyRtcReconnectPolicy.delayMs(attempt: reconnectAttempt)
        let delay = Double(delayMs) / 1000
        connectionState = "reconnecting"
        reconnectWorkWasSignaling = true
        eventHandler?.onConnectionStateChanged(state: "reconnecting", reason: "signaling")
        eventHandler?.onReconnecting(reason: "signaling", attempt: reconnectAttempt, maxAttempts: SyRtcReconnectPolicy.maxAttempts, delayMs: delayMs)
        let work = DispatchWorkItem { [weak self] in
            guard let self, let channelId = self.currentChannelId, let uid = self.currentUid, let token = self.currentToken else { return }
            self.pendingRejoin = self.hasFiredJoinSuccess
            self.openSignaling(channelId: channelId, uid: uid, token: token)
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    fileprivate func startQualityMonitor() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.qualityTimer?.invalidate()
            self.qualityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.collectStatistics(reportVolume: false, reportQuality: true)
            }
        }
    }

    fileprivate func stopQualityMonitor() {
        let stop = { [weak self] in
            self?.qualityTimer?.invalidate()
            self?.qualityTimer = nil
            self?.lastInboundLost.removeAll()
            self?.lastInboundRecv.removeAll()
        }
        if Thread.isMainThread {
            stop()
        } else {
            DispatchQueue.main.async(execute: stop)
        }
    }

    /// 各对端 ICE 状态只驱动重连逻辑，不再逐条转成 `onConnectionStateChanged`（与 Android 一致）。
    fileprivate func handleIceState(_ state: RTCIceConnectionState, remoteUid: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .disconnected, .failed:
                self.handleIceLost(remoteUid)
            case .connected, .completed:
                self.handleIceRecovered(remoteUid)
            default:
                break
            }
        }
    }

    /// PeerConnection 聚合状态与 ICE 状态重复，只用 ICE 状态驱动重连。
    fileprivate func handlePeerConnectionState(_ state: RTCPeerConnectionState, remoteUid: String) {}

    private func resetIceRecovery() {
        iceRetryWork?.cancel()
        iceRetryWork = nil
        iceLostPeers.removeAll()
        iceRecoveryPending = false
    }

    /// 某个对端 ICE 断开：计一次重连（与信令共用次数），按 `SyRtcReconnectPolicy` 等待后若仍未恢复再计下一次。
    fileprivate func handleIceLost(_ remoteUid: String) {
        guard currentChannelId != nil, hasFiredJoinSuccess, peerConnections[remoteUid] != nil else { return }
        iceLostPeers.insert(remoteUid)
        if iceRecoveryPending {
            restartIce(for: remoteUid)
            return
        }
        iceRecoveryPending = true
        reconnectAttempt += 1
        if reconnectAttempt > SyRtcReconnectPolicy.maxAttempts {
            resetIceRecovery()
            connectionState = "failed"
            eventHandler?.onConnectionStateChanged(state: "failed", reason: "ice")
            eventHandler?.onReconnectFailed(reason: "ice")
            eventHandler?.onError(code: SyRtcErrorCode.reconnectFailed, message: "媒体连接重连失败")
            return
        }
        let delayMs = SyRtcReconnectPolicy.delayMs(attempt: reconnectAttempt)
        connectionState = "reconnecting"
        eventHandler?.onConnectionStateChanged(state: "reconnecting", reason: "ice")
        eventHandler?.onReconnecting(reason: "ice", attempt: reconnectAttempt, maxAttempts: SyRtcReconnectPolicy.maxAttempts, delayMs: delayMs)
        iceLostPeers.forEach { restartIce(for: $0) }
        iceRetryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.iceRecoveryPending, self.currentChannelId != nil else { return }
            self.iceRetryWork = nil
            self.iceLostPeers = self.iceLostPeers.filter { self.peerConnections[$0] != nil }
            self.iceRecoveryPending = false
            guard let next = self.iceLostPeers.first else { return }
            self.handleIceLost(next)
        }
        iceRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(delayMs) / 1000, execute: work)
    }

    /// 字典序较小的一方 restartIce 并重发 offer（与首次 offer 的发起方相同，避免 glare）。
    private func restartIce(for remoteUid: String) {
        guard let pc = peerConnections[remoteUid], let localUid = currentUid else { return }
        pc.restartIce()
        if shouldInitiateOffer(localUid: localUid, remoteUid: remoteUid) {
            forceOffer(to: remoteUid)
        }
    }

    fileprivate func handleIceRecovered(_ remoteUid: String) {
        iceLostPeers.remove(remoteUid)
        guard iceLostPeers.isEmpty, iceRecoveryPending else { return }
        iceRetryWork?.cancel()
        iceRetryWork = nil
        iceRecoveryPending = false
        reconnectAttempt = 0
        connectionState = "connected"
        let elapsed = Int((Date().timeIntervalSince(joinStartTime ?? Date())) * 1000)
        eventHandler?.onRejoinChannelSuccess(channelId: currentChannelId ?? "", uid: currentUid ?? "", elapsed: max(0, elapsed))
        eventHandler?.onConnectionStateChanged(state: "connected", reason: "rejoin_success")
        eventHandler?.onReconnected(reason: "ice")
    }

    fileprivate func receiveConstraints() -> RTCMediaConstraints {
        RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
    }

    fileprivate func addTrackIfNeeded(_ track: RTCMediaStreamTrack, to pc: RTCPeerConnection) {
        let exists = pc.senders.contains { $0.track?.trackId == track.trackId }
        if !exists {
            pc.add(track, streamIds: ["stream"])
        }
    }

    fileprivate func attachPublishedVideo(_ track: RTCVideoTrack) {
        for (uid, pc) in peerConnections where uid != "default" {
            let before = pc.senders.contains { $0.track?.trackId == track.trackId }
            addTrackIfNeeded(track, to: pc)
            applyVideoBitrate(to: pc, trackId: track.trackId)
            if !before {
                forceOffer(to: uid)
            }
        }
#if canImport(UIKit)
        if track.trackId == "video_track", let renderer = localRenderer {
            track.add(renderer)
        }
#endif
    }

    fileprivate func removePublishedTrack(_ track: RTCMediaStreamTrack) {
        for (uid, pc) in peerConnections where uid != "default" {
            if let sender = pc.senders.first(where: { $0.track?.trackId == track.trackId }) {
                pc.removeTrack(sender)
                forceOffer(to: uid)
            }
        }
    }

    fileprivate func forceOffer(to remoteUid: String) {
        guard let pc = peerConnections[remoteUid] else { return }
        if pc.signalingState != .stable {
            pendingForceOffer.insert(remoteUid)
            return
        }
        offerSentByUid.remove(remoteUid)
        startOffer(to: remoteUid, force: true)
    }

    fileprivate func flushRenegotiation(remoteUid: String) {
        guard pendingForceOffer.remove(remoteUid) != nil else { return }
        forceOffer(to: remoteUid)
    }

    fileprivate func applyVideoBitrateToSenders() {
        let kbps = currentVideoConfig?.bitrate ?? 0
        guard kbps > 0 else { return }
        for pc in peerConnections.values {
            if let id = localVideoTrack?.trackId { applyVideoBitrate(to: pc, trackId: id) }
            if let id = screenVideoTrack?.trackId { applyVideoBitrate(to: pc, trackId: id) }
        }
    }

    fileprivate func applyVideoBitrate(to pc: RTCPeerConnection, trackId: String) {
        let kbps = currentVideoConfig?.bitrate ?? screenCaptureConfig?.bitrate ?? 0
        guard kbps > 0 else { return }
        for sender in pc.senders where sender.track?.trackId == trackId {
            var params = sender.parameters
            guard !params.encodings.isEmpty else { continue }
            params.encodings[0].maxBitrateBps = NSNumber(value: kbps * 1000)
            sender.parameters = params
        }
    }

    fileprivate func ensureCameraFrameRelay() -> CameraFrameRelay {
        if let cameraFrameRelay { return cameraFrameRelay }
        let relay = CameraFrameRelay()
        relay.owner = self
        cameraFrameRelay = relay
        return relay
    }

    fileprivate func ensureCameraVideoSource() -> RTCVideoSource? {
        if let cameraVideoSource { return cameraVideoSource }
        guard let factory = peerConnectionFactory else { return nil }
        let source = factory.videoSource()
        cameraVideoSource = source
        return source
    }

    fileprivate func ensureCameraVideoTrack() -> RTCVideoTrack? {
        if let localVideoTrack { return localVideoTrack }
        guard let factory = peerConnectionFactory, let source = ensureCameraVideoSource() else { return nil }
        let track = factory.videoTrack(with: source, trackId: "video_track")
        track.isEnabled = !localVideoMuted && canPublishMedia
        localVideoTrack = track
        attachLocalFrameRenderer(track, key: "camera")
        return track
    }

    fileprivate func ensureScreenVideoTrack() -> RTCVideoTrack? {
        if let screenVideoTrack { return screenVideoTrack }
        guard let factory = peerConnectionFactory else { return nil }
        let source = factory.videoSource()
        screenVideoSource = source
        let track = factory.videoTrack(with: source, trackId: "screen_track")
        track.isEnabled = !localVideoMuted && canPublishMedia
        screenVideoTrack = track
        attachLocalFrameRenderer(track, key: "screen")
        screenCapturer = RTCVideoCapturer(delegate: source)
        return track
    }

    @discardableResult
    fileprivate func startCamera(_ capturer: RTCCameraVideoCapturer, front: Bool) -> Bool {
        let position: AVCaptureDevice.Position = front ? .front : .back
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .back : .front)
        guard let device else {
            eventHandler?.onError(code: SyRtcErrorCode.camera, message: "没有可用摄像头（模拟器或未授权时常见）")
            eventHandler?.onLocalVideoStateChanged(state: "failed", error: "no_camera")
            return false
        }
        let fps = currentVideoConfig?.frameRate ?? 15
        capturer.startCapture(with: device, format: device.activeFormat, fps: fps)
        return true
    }

    fileprivate func deliverCameraFrame(_ frame: RTCVideoFrame, capturer: RTCVideoCapturer) {
        guard let source = cameraVideoSource else { return }
        guard let processor = videoFrameProcessor, let cv = frame.buffer as? RTCCVPixelBuffer else {
            source.capturer(capturer, didCapture: frame)
            return
        }
        let rotation = Self.rotationDegrees(frame.rotation)
        let processed = processor(cv.pixelBuffer, rotation)
        let buffer = RTCCVPixelBuffer(pixelBuffer: processed)
        let next = RTCVideoFrame(buffer: buffer, rotation: frame.rotation, timeStampNs: frame.timeStampNs)
        source.capturer(capturer, didCapture: next)
    }

    fileprivate static func rotationDegrees(_ rotation: RTCVideoRotation) -> Int {
        switch rotation {
        case ._90: return 90
        case ._180: return 180
        case ._270: return 270
        default: return 0
        }
    }

    static func rotationDegreesForSink(_ rotation: RTCVideoRotation) -> Int {
        rotationDegrees(rotation)
    }

    fileprivate static func rtcRotation(_ degrees: Int) -> RTCVideoRotation {
        switch ((degrees % 360) + 360) % 360 {
        case 90: return ._90
        case 180: return ._180
        case 270: return ._270
        default: return ._0
        }
    }

    fileprivate func attachRemoteTrack(_ track: RTCMediaStreamTrack, uid: String) {
        if let video = track as? RTCVideoTrack {
            remoteVideoTracks[uid] = video
            video.isEnabled = videoMutedStates[uid] != true && !muteAllRemoteVideo
#if canImport(UIKit)
            if let renderer = remoteRenderers[uid] {
                video.add(renderer)
            }
#endif
            if let old = firstFrameRenderers[uid] {
                video.remove(old)
            }
            let renderer = FrameTrackingRenderer { [weak self] w, h, rot, change in
                DispatchQueue.main.async { self?.handleRemoteFrame(uid: uid, width: w, height: h, rotation: rot, change: change) }
            }
            firstFrameRenderers[uid] = renderer
            video.add(renderer)
            eventHandler?.onRemoteVideoStateChanged(uid: uid, state: "decoding", reason: "track", elapsed: elapsedSinceJoin())
        } else if let audio = track as? RTCAudioTrack {
            remoteAudioTracks[uid] = audio
            audio.isEnabled = remoteAudioMuted[uid] != true && !muteAllRemoteAudio
            attachRemoteAudioTap(uid: uid, track: audio)
            eventHandler?.onRemoteAudioStateChanged(uid: uid, state: "decoding", reason: "track", elapsed: elapsedSinceJoin())
        }
    }

    /// 首帧回调 onFirstRemoteVideoDecoded / onFirstRemoteVideoFrame；首帧及之后宽高或旋转变化回调
    /// onVideoSizeChanged。sink 常驻到对端离开（3.2.0 只在首帧回调一次尺寸）。与 Android 相同。
    fileprivate func handleRemoteFrame(uid: String, width: Int, height: Int, rotation: Int, change: SyRtcVideoFrameTracker.Change) {
        guard currentChannelId != nil, firstFrameRenderers[uid] != nil else { return }
        let elapsed = elapsedSinceJoin()
        if change.first {
            eventHandler?.onFirstRemoteVideoDecoded(uid: uid, width: width, height: height, elapsed: elapsed)
            eventHandler?.onFirstRemoteVideoFrame(uid: uid, width: width, height: height, elapsed: elapsed)
        }
        if change.sizeChanged {
            eventHandler?.onVideoSizeChanged(uid: uid, width: width, height: height, rotation: rotation)
        }
    }

    /// 本地视频轨（摄像头含自定义采集 / 屏幕）新建后的第一帧回调 onFirstLocalVideoFrame。
    fileprivate func attachLocalFrameRenderer(_ track: RTCVideoTrack, key: String) {
        let renderer = FrameTrackingRenderer { [weak self] w, h, _, change in
            guard change.first else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                let elapsed = self.joinStartTime == nil ? 0 : self.elapsedSinceJoin()
                self.eventHandler?.onFirstLocalVideoFrame(width: w, height: h, elapsed: elapsed)
            }
        }
        localFrameRenderers[key] = renderer
        track.add(renderer)
    }

    fileprivate func elapsedSinceJoin() -> Int {
        Int((Date().timeIntervalSince(joinStartTime ?? Date())) * 1000)
    }

    fileprivate func applyRemoteMediaState(_ data: [String: Any]) {
        let uid = (data["uid"] as? String) ?? ""
        guard !uid.isEmpty, uid != currentUid else { return }
        if let audioMuted = boolValue(data["audioMuted"]) {
            remoteAudioMuted[uid] = audioMuted
            remoteAudioTracks[uid]?.isEnabled = !audioMuted && !muteAllRemoteAudio
            eventHandler?.onUserMuteAudio(uid: uid, muted: audioMuted)
        }
        if let videoMuted = boolValue(data["videoMuted"]) {
            videoMutedStates[uid] = videoMuted
            remoteVideoTracks[uid]?.isEnabled = !videoMuted && !muteAllRemoteVideo
            eventHandler?.onUserMuteVideo(uid: uid, muted: videoMuted)
        }
    }

    fileprivate func republishSideInfo() {
        if !streamExtraInfo.isEmpty {
            signalingClient?.sendChannelMessage(streamExtraPrefix + streamExtraInfo)
        }
        if localAudioMuted || localVideoMuted || !canPublishMedia {
            signalingClient?.sendUserMedia(
                audioMuted: localAudioMuted || !canPublishMedia,
                videoMuted: localVideoMuted || !canPublishMedia
            )
        }
    }

    fileprivate func boolValue(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    fileprivate func ensureDataChannel(streamId: Int, remoteUid: String, peerConnection: RTCPeerConnection) {
        if dataChannelsByPeer[remoteUid]?[streamId] != nil { return }
        guard let cfg = dataStreamConfigs[streamId] else { return }
        let config = RTCDataChannelConfiguration()
        config.isOrdered = cfg.ordered
        if !cfg.reliable {
            config.maxRetransmits = 0
        }
        guard let channel = peerConnection.dataChannel(forLabel: "sy-\(streamId)", configuration: config) else { return }
        channel.delegate = DataChannelDelegate(streamId: streamId, remoteUid: remoteUid, engine: self)
        dataChannelsByPeer[remoteUid, default: [:]][streamId] = channel
        dataChannelMap[streamId] = channel
    }

    fileprivate func attachExistingDataChannels(remoteUid: String, peerConnection: RTCPeerConnection) {
        for streamId in dataStreamConfigs.keys.sorted() {
            ensureDataChannel(streamId: streamId, remoteUid: remoteUid, peerConnection: peerConnection)
        }
    }

    fileprivate func handleOpenedDataChannel(_ channel: RTCDataChannel, remoteUid: String) {
        let label = channel.label
        guard label.hasPrefix("sy-"), let streamId = Int(label.dropFirst(3)) else { return }
        channel.delegate = DataChannelDelegate(streamId: streamId, remoteUid: remoteUid, engine: self)
        dataChannelsByPeer[remoteUid, default: [:]][streamId] = channel
        dataChannelMap[streamId] = channel
        if dataStreamConfigs[streamId] == nil {
            dataStreamConfigs[streamId] = (true, channel.isOrdered)
            dataStreams[streamId] = true
        }
    }

    fileprivate func collectStatistics(reportVolume: Bool, reportQuality: Bool) {
        guard currentChannelId != nil else { return }
        let pcs = peerConnections.filter { $0.key != "default" }
        let localUid = currentUid ?? "local"
        if pcs.isEmpty {
            if reportQuality {
                eventHandler?.onNetworkQuality(uid: localUid, txQuality: "unknown", rxQuality: "unknown")
            }
            if reportVolume && volumeIntervalMs > 0 {
                eventHandler?.onVolumeIndication(speakers: [SyVolumeInfo(uid: localUid, volume: localAudioMuted ? 0 : 0, vad: 0)])
            }
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var samples: [(uid: String, sample: SyRtcStatsSample)] = []
        for (uid, pc) in pcs {
            group.enter()
            pc.statistics { report in
                let parsed = Self.parseStatistics(report)
                lock.lock()
                samples.append((uid, parsed))
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.currentChannelId != nil else { return }
            // 上下行分开（与 Android 相同）：tx = RTT + 上行丢包，rx = 本周期下行丢包 + 抖动。
            let rows = samples.map { item -> (uid: String, tx: String, rx: String, rxLoss: Double?, sample: SyRtcStatsSample, inbound: Double?, outbound: Double?) in
                let s = item.sample
                let rxLoss = SyRtcLinkQuality.intervalLossRate(prevLost: self.lastInboundLost[item.uid], prevReceived: self.lastInboundRecv[item.uid],
                                                               lost: s.inboundPacketsLost, received: s.inboundPacketsReceived)
                if let v = s.inboundPacketsLost { self.lastInboundLost[item.uid] = v }
                if let v = s.inboundPacketsReceived { self.lastInboundRecv[item.uid] = v }
                return (item.uid, SyRtcLinkQuality.tx(rttMs: s.rttMs, outboundLossRate: s.outboundLossRate),
                        SyRtcLinkQuality.rx(inboundLossRate: rxLoss, jitterMs: s.jitterMs), rxLoss, s,
                        s.inboundAudioLevel, s.outboundAudioLevel)
            }
            if reportQuality {
                self.eventHandler?.onNetworkQuality(uid: localUid,
                                                    txQuality: SyRtcNetworkQuality.worst(rows.map(\.tx)),
                                                    rxQuality: SyRtcNetworkQuality.worst(rows.map(\.rx)))
                let sorted = rows.sorted { $0.uid < $1.uid }
                for row in sorted {
                    self.eventHandler?.onNetworkQuality(uid: row.uid, txQuality: row.tx, rxQuality: row.rx)
                }
                // 每个对端一条 onRtcStats（与 Android 相同）。
                for row in sorted {
                    var stats: [String: Any] = [
                        "networkType": self.networkType,
                        "uid": row.uid,
                        "quality": SyRtcNetworkQuality.worst([row.tx, row.rx]),
                        "txQuality": row.tx,
                        "rxQuality": row.rx,
                    ]
                    if let rtt = row.sample.rttMs { stats["rttMs"] = rtt }
                    if let l = row.sample.outboundLossRate { stats["txPacketLossRate"] = l }
                    if let l = row.rxLoss { stats["rxPacketLossRate"] = l }
                    if let j = row.sample.jitterMs { stats["jitterMs"] = j }
                    if let loss = row.sample.outboundLossRate ?? row.rxLoss {
                        stats["packetLoss"] = loss
                        stats["packetLossRate"] = loss
                        stats["lossPercent"] = loss * 100
                    }
                    self.eventHandler?.onRtcStats(stats: stats)
                }
            }
            if reportVolume && self.volumeIntervalMs > 0 {
                var speakers: [SyVolumeInfo] = []
                let localLevel = self.localAudioMuted ? 0 : (rows.compactMap(\.outbound).max() ?? 0)
                speakers.append(self.volumeInfo(uid: localUid, level: localLevel))
                for row in rows {
                    speakers.append(self.volumeInfo(uid: row.uid, level: row.inbound ?? 0))
                }
                self.eventHandler?.onVolumeIndication(speakers: speakers)
            }
        }
    }

    fileprivate func volumeInfo(uid: String, level: Double) -> SyVolumeInfo {
        let raw = min(1, max(0, level))
        let prev = smoothedVolumes[uid] ?? raw
        let next = volumeSmooth <= 1 ? raw : (prev * Double(volumeSmooth - 1) + raw) / Double(volumeSmooth)
        smoothedVolumes[uid] = next
        let volume = Int((next * 255).rounded())
        let vad = reportVad && raw > 0.02 ? 1 : 0
        return SyVolumeInfo(uid: uid, volume: volume, vad: vad)
    }

    fileprivate static func qualityRank(_ quality: String) -> Int {
        SyRtcNetworkQuality.rank(quality)
    }

    fileprivate static func parseStatistics(_ report: RTCStatisticsReport) -> SyRtcStatsSample {
        SyRtcStatsSample.parse(report.statistics.values.map { ($0.type, $0.values as [String: Any], Self.isAudioStat($0)) })
    }

    fileprivate static func isAudioStat(_ stat: RTCStatistics) -> Bool {
        if (stat.values["kind"] as? String) == "audio" { return true }
        return stat.id.contains("audio")
    }

    fileprivate func publishCurrentAudioRoute() {
        let route = currentAudioRoute()
        speakerphoneEnabled = route == .speaker
        eventHandler?.onAudioRoutingChanged(routing: route.rawValue)
    }

    fileprivate func currentAudioRoute() -> SyRtcAudioRoute {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        for port in outputs {
            switch port.portType {
            case .builtInSpeaker:
                return .speaker
            case .builtInReceiver:
                return .earpiece
            case .headphones, .headsetMic:
                return .headset
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return .bluetooth
            default:
                continue
            }
        }
        return .unknown
    }
}

private final class CameraFrameRelay: NSObject, RTCVideoCapturerDelegate {
    weak var owner: SyRtcEngineImpl?

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        owner?.deliverCameraFrame(frame, capturer: capturer)
    }

    func capturer(_ capturer: RTCVideoCapturer, didCaptureVideoFrame frame: RTCVideoFrame) {
        owner?.deliverCameraFrame(frame, capturer: capturer)
    }
}

/// 常驻视频 sink：每帧交给 `SyRtcVideoFrameTracker`，只在首帧或尺寸变化时回调（渲染线程）。
private final class FrameTrackingRenderer: NSObject, RTCVideoRenderer {
    private let tracker = SyRtcVideoFrameTracker()
    private let onChange: (Int, Int, Int, SyRtcVideoFrameTracker.Change) -> Void

    init(onChange: @escaping (Int, Int, Int, SyRtcVideoFrameTracker.Change) -> Void) {
        self.onChange = onChange
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let w = Int(frame.width), h = Int(frame.height)
        let rot = SyRtcEngineImpl.rotationDegreesForSink(frame.rotation)
        let change = tracker.onFrame(width: w, height: h, rotation: rot)
        if change.first || change.sizeChanged { onChange(w, h, rot, change) }
    }
}

// MARK: - 配置数据类

public struct AudioDeviceInfo {
    public let deviceId: String
    public let deviceName: String
    
    public init(deviceId: String, deviceName: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
    }
}

public struct VideoEncoderConfiguration {
    public let width: Int
    public let height: Int
    public let frameRate: Int
    public let minFrameRate: Int
    public let bitrate: Int
    public let minBitrate: Int
    public let orientationMode: String
    public let degradationPreference: String
    public let mirrorMode: String
    
    public init(width: Int = 640, height: Int = 480, frameRate: Int = 15,
                minFrameRate: Int = -1, bitrate: Int = 0, minBitrate: Int = -1,
                orientationMode: String = "adaptative",
                degradationPreference: String = "maintainQuality",
                mirrorMode: String = "auto") {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.minFrameRate = minFrameRate
        self.bitrate = bitrate
        self.minBitrate = minBitrate
        self.orientationMode = orientationMode
        self.degradationPreference = degradationPreference
        self.mirrorMode = mirrorMode
    }
}

public struct ScreenCaptureConfiguration {
    public let captureMouseCursor: Bool
    public let captureWindow: Bool
    public let frameRate: Int
    public let bitrate: Int
    public let width: Int
    public let height: Int
    
    public init(captureMouseCursor: Bool = true, captureWindow: Bool = false,
                frameRate: Int = 15, bitrate: Int = 0,
                width: Int = 0, height: Int = 0) {
        self.captureMouseCursor = captureMouseCursor
        self.captureWindow = captureWindow
        self.frameRate = frameRate
        self.bitrate = bitrate
        self.width = width
        self.height = height
    }
}

public struct BeautyOptions {
    public let enabled: Bool
    public let lighteningLevel: Double
    public let rednessLevel: Double
    public let smoothnessLevel: Double
    
    public init(enabled: Bool = false, lighteningLevel: Double = 0.5,
                rednessLevel: Double = 0.1, smoothnessLevel: Double = 0.5) {
        self.enabled = enabled
        self.lighteningLevel = lighteningLevel
        self.rednessLevel = rednessLevel
        self.smoothnessLevel = smoothnessLevel
    }
}

public struct AudioMixingConfiguration {
    public let filePath: String
    public let loopback: Bool
    public let replace: Bool
    public let cycle: Int
    public let startPos: Int
    
    public init(filePath: String, loopback: Bool = false, replace: Bool = false,
                cycle: Int = 1, startPos: Int = 0) {
        self.filePath = filePath
        self.loopback = loopback
        self.replace = replace
        self.cycle = cycle
        self.startPos = startPos
    }
}

public struct AudioEffectConfiguration {
    public let filePath: String
    public let loopCount: Int
    public let publish: Bool
    public let startPos: Int
    
    public init(filePath: String, loopCount: Int = 1, publish: Bool = false,
                startPos: Int = 0) {
        self.filePath = filePath
        self.loopCount = loopCount
        self.publish = publish
        self.startPos = startPos
    }
}

/// 本地录音配置。与 Android 相同：
/// - `codecType`：`aac` / `aacLc` / `m4a` → AAC（MPEG-4，建议 `.m4a`）；`wav` / `pcm` → 16 bit WAV。
///   **不支持 mp3**，传入回调 `onError(1000)` 并返回 -1。
/// - 频道内：录 WebRTC 管线里的 PCM（本端采集后处理 + 远端解码），混成单声道，不另开录音器。
///   `includeLocal` / `includeRemote` 控制是否包含本端、远端。本端静音时不录本端，本端静音了某远端时不录他。
/// - 频道外：AVAudioRecorder 录麦克风，仅 AAC。
/// - `channels` 目前只支持 1；`quality`：`low` 32 kbps、`medium` 64 kbps、`high` 128 kbps（仅 AAC）。leave 时自动停止。
public struct AudioRecordingConfiguration {
    public let filePath: String
    public let sampleRate: Int
    public let channels: Int
    public let codecType: String
    public let quality: String
    public let includeLocal: Bool
    public let includeRemote: Bool
    
    public init(filePath: String, sampleRate: Int = 32000, channels: Int = 1,
                codecType: String = "aacLc", quality: String = "medium",
                includeLocal: Bool = true, includeRemote: Bool = true) {
        self.filePath = filePath
        self.sampleRate = sampleRate
        self.channels = channels
        self.codecType = codecType
        self.quality = quality
        self.includeLocal = includeLocal
        self.includeRemote = includeRemote
    }

    /// AAC 码率（bit/s）。
    public var aacBitrate: Int {
        switch quality.lowercased() {
        case "low": return 32_000
        case "high": return 128_000
        default: return 64_000
        }
    }
}


// MARK: - WebRTC辅助类

private class FrameCapturer: NSObject, RTCVideoRenderer {
    private let onFrame: (RTCVideoFrame) -> Void
    
    init(onFrame: @escaping (RTCVideoFrame) -> Void) {
        self.onFrame = onFrame
    }
    
    func setSize(_ size: CGSize) {
        // 设置渲染尺寸
    }
    
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else { return }
        onFrame(frame)
    }
}

// MARK: - SyRtcEngineImpl扩展

// MARK: - 美颜滤镜类

private class BeautyFilter {
    private var lighteningLevel: Double = 0.5
    private var smoothnessLevel: Double = 0.5
    private var rednessLevel: Double = 0.1
    private var enabled: Bool = false
    
    func setLighteningLevel(_ level: Double) {
        lighteningLevel = max(0.0, min(1.0, level))
    }
    
    func setSmoothnessLevel(_ level: Double) {
        smoothnessLevel = max(0.0, min(1.0, level))
    }
    
    func setRednessLevel(_ level: Double) {
        rednessLevel = max(0.0, min(1.0, level))
    }
    
    func enable() {
        enabled = true
    }
    
    func disable() {
        enabled = false
    }
    
    func isEnabled() -> Bool {
        return enabled
    }
    
    // 应用美颜效果到视频帧
    func apply(_ frame: RTCVideoFrame) -> RTCVideoFrame {
        if !enabled { return frame }
        
        // 实际实现需要使用CoreImage进行美颜处理
        // 这里简化处理，返回原帧
        return frame
    }
}

// MARK: - 美颜滤镜VideoSink

private class BeautyFilterVideoSink: NSObject, RTCVideoRenderer {
    private let onFrame: (RTCVideoFrame) -> Void
    
    init(onFrame: @escaping (RTCVideoFrame) -> Void) {
        self.onFrame = onFrame
    }
    
    func setSize(_ size: CGSize) {
        // 设置渲染尺寸
    }
    
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else { return }
        onFrame(frame)
    }
}

// MARK: - SyRtcEngineImpl扩展

extension SyRtcEngineImpl {
    private func frameToImage(_ frame: RTCVideoFrame) -> UIImage? {
        // 将RTCVideoFrame转换为UIImage
        // 使用WebRTC的I420Buffer转换为UIImage
        let i420Buffer = frame.buffer.toI420()
        let width = Int(i420Buffer.width)
        let height = Int(i420Buffer.height)
        
        // 创建CVPixelBuffer并转换为UIImage
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("创建CVPixelBuffer失败")
            return nil
        }
        
        // 将I420数据转换为RGB并填充到CVPixelBuffer
        // 这里简化处理，实际应该使用更高效的转换方法
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        // 创建CIImage并转换为UIImage
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

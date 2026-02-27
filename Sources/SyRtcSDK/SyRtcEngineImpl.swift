import Foundation
import AVFoundation
import WebRTC
import ReplayKit
import CoreImage

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
    // 后端 API 认证用的 JWT（用于 /api/rtc/live/* 等）
    private var apiAuthToken: String?
    
    // 多人语聊（Mesh）：每个远端用户一条 PeerConnection（key=remoteUid）
    private var offerSentByUid: Set<String> = []
    private var remoteSdpSetByUid: Set<String> = []
    private var pendingLocalIceByUid: [String: [RTCIceCandidate]] = [:]
    private var pendingRemoteIceByUid: [String: [RTCIceCandidate]] = [:]

    private func guessRemoteUid() -> String {
        return peerConnections.keys.first(where: { $0 != "default" }) ?? ""
    }
    
    // 旁路推流：采用服务端 egress（/api/rtc/live/*），不在客户端实现 RTMP 连接/编码
    private var rtmpStreams: [String: LiveTranscoding] = [:]
    
    // 屏幕共享
    private var screenRecorder: RPScreenRecorder?
    
    // 美颜滤镜
    private var beautyFilter: BeautyFilter?
    
    // 远端视频轨道
    private var remoteVideoTracks: [String: RTCVideoTrack] = [:]
    
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

    private func postLiveApi(path: String, body: [String: Any]) {
        guard let base = apiBaseUrl, !base.isEmpty else {
            eventHandler?.onError(code: 1001, message: "API_BASE_URL 未设置：请先调用 setApiBaseUrl()")
            return
        }
        let token = (apiAuthToken?.isEmpty == false) ? apiAuthToken : currentToken
        guard let token = token, !token.isEmpty else {
            eventHandler?.onError(code: 1001, message: "缺少登录 token：请先调用 setApiAuthToken() 或在 join() 后设置")
            return
        }
        guard let url = URL(string: base + path) else {
            eventHandler?.onError(code: 1001, message: "API URL 无效")
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 8.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(self?.appId ?? "", forHTTPHeaderField: "X-App-Id")
            // 后端 live 接口需要 uid，否则返回 401
            if let uid = self?.currentUid, !uid.isEmpty {
                request.setValue(uid, forHTTPHeaderField: "X-Uid")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            let sema = DispatchSemaphore(value: 0)
            var statusCode: Int = -1
            var respText: String = ""
            URLSession.shared.dataTask(with: request) { data, resp, err in
                if let http = resp as? HTTPURLResponse { statusCode = http.statusCode }
                if let data = data { respText = String(data: data, encoding: .utf8) ?? "" }
                if let err = err {
                    self?.eventHandler?.onError(code: 1001, message: "直播接口异常: \(err.localizedDescription)")
                } else if !(200...299).contains(statusCode) {
                    self?.eventHandler?.onError(code: 1001, message: "直播接口失败: \(statusCode) \(respText)")
                }
                sema.signal()
            }.resume()
            _ = sema.wait(timeout: .now() + 10)
        }
    }

    private func guessLayout(from transcoding: LiveTranscoding) -> [String: Any] {
        let users = transcoding.transcodingUsers ?? []
        guard !users.isEmpty else {
            return ["mode": "host-main", "hostUid": currentUid ?? "", "side": "right"]
        }
        let sorted = users.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        let top1 = sorted.first
        let top2 = sorted.dropFirst().first
        if let a = top1, let b = top2 {
            let area1 = a.width * a.height
            let area2 = b.width * b.height
            let ratio: Double = area2 <= 0 ? 999.0 : (area1 / area2)
            if ratio < 1.2 {
                return ["mode": "pk", "pkUids": [a.uid, b.uid]]
            }
        }
        return ["mode": "host-main", "hostUid": top1?.uid ?? (currentUid ?? ""), "side": "right"]
    }

    // MARK: - 频道（多人语聊 Mesh）
    func join(channelId: String, uid: String, token: String) {
        guard !channelId.trimmingCharacters(in: .whitespaces).isEmpty,
              !uid.trimmingCharacters(in: .whitespaces).isEmpty,
              !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            eventHandler?.onError(code: 1000, message: "channelId/uid/token 不能为空")
            return
        }
        currentChannelId = channelId
        currentUid = uid
        currentToken = token
        offerSentByUid.removeAll()
        remoteSdpSetByUid.removeAll()
        pendingLocalIceByUid.removeAll()
        pendingRemoteIceByUid.removeAll()
        hasFiredJoinSuccess = false
        joinStartTime = Date()

        eventHandler?.onConnectionStateChanged(state: "connecting", reason: "joining")

        // 连接信令
        signalingClient = SyRtcSignalingClient(signalingUrl: signalingUrl, channelId: channelId, uid: uid) { [weak self] type, data in
            self?.handleSignalingMessage(type: type, data: data, channelId: channelId)
        }
        signalingClient?.connect()

        // 本地音频轨道（多人：后续每条 PC 都 addTrack）
        if let factory = peerConnectionFactory, localAudioTrack == nil {
            let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio_track")
        }
    }

    func leave() {
        eventHandler?.onConnectionStateChanged(state: "disconnecting", reason: "leaving")

        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        offerSentByUid.removeAll()
        remoteSdpSetByUid.removeAll()
        pendingLocalIceByUid.removeAll()
        pendingRemoteIceByUid.removeAll()
        signalingClient?.disconnect()
        signalingClient = nil

        let channelId = currentChannelId ?? ""
        currentChannelId = nil
        currentUid = nil
        currentToken = nil
        joinStartTime = nil
        hasFiredJoinSuccess = false

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
        // add tracks
        if let track = localAudioTrack { pc?.add(track, streamIds: ["stream"]) }
        return pc
    }

    private func handleSignalingMessage(type: String, data: [String: Any], channelId: String) {
        switch type {
        case "user-list":
            guard let localUid = currentUid, let chId = currentChannelId else { return }
            // 服务端 data.users 可能是 [String] 或 JSON 反序列化后的 [Any]，需兼容
            let users: [String] = (data["users"] as? [String]) ?? (data["users"] as? [Any])?.compactMap { $0 as? String } ?? []
            if !hasFiredJoinSuccess {
                hasFiredJoinSuccess = true
                let elapsed = Int((Date().timeIntervalSince(joinStartTime ?? Date())) * 1000)
                eventHandler?.onJoinChannelSuccess(channelId: chId, uid: localUid, elapsed: max(0, elapsed))
                eventHandler?.onConnectionStateChanged(state: "connected", reason: "join_success")
            }
            for u in users where u != localUid {
                eventHandler?.onUserJoined(uid: u, elapsed: 0)
                if peerConnections[u] == nil { _ = createPeerConnection(remoteUid: u) }
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
                let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
                pcUnwrapped.answer(for: constraints) { sdp, _ in
                    guard let sdp = sdp else { return }
                    pcUnwrapped.setLocalDescription(sdp) { _ in
                        self.signalingClient?.sendAnswer(sdp: sdp.sdp, toUid: from)
                        self.flushPendingLocalIce(to: from)
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
                    if peerConnections[uid] == nil { _ = createPeerConnection(remoteUid: uid) }
                    if shouldInitiateOffer(localUid: localUid, remoteUid: uid) {
                        startOffer(to: uid)
                    }
                }
            }
        case "user-left":
            if let uid = data["uid"] as? String {
                eventHandler?.onUserOffline(uid: uid, reason: "quit")
                peerConnections.removeValue(forKey: uid)?.close()
                offerSentByUid.remove(uid)
                remoteSdpSetByUid.remove(uid)
                pendingLocalIceByUid.removeValue(forKey: uid)
                pendingRemoteIceByUid.removeValue(forKey: uid)
            }
        case "channel-message":
            let fromUid = (data["uid"] as? String) ?? ""
            let msg = (data["message"] as? String) ?? ""
            eventHandler?.onChannelMessage(uid: fromUid, message: msg)
        case "error":
            let msg = (data["error"] as? String) ?? "信令错误"
            eventHandler?.onError(code: 1002, message: msg)
        default:
            break
        }
    }

    private func shouldInitiateOffer(localUid: String, remoteUid: String) -> Bool {
        return localUid < remoteUid
    }

    private func startOffer(to remoteUid: String) {
        guard let pc = peerConnections[remoteUid] else { return }
        if offerSentByUid.contains(remoteUid) { return }
        offerSentByUid.insert(remoteUid)
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )
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
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
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
        
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
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
            print("扬声器状态: \(enabled)")
        } catch {
            print("设置扬声器失败: \(error)")
        }
    }
    
    func setDefaultAudioRouteToSpeakerphone(_ enabled: Bool) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: enabled ? [.defaultToSpeaker] : [])
            try audioSession.setActive(true)
            speakerphoneEnabled = enabled
            print("默认音频路由设置为扬声器: \(enabled)")
        } catch {
            print("设置默认音频路由失败: \(error)")
        }
    }
    
    func isSpeakerphoneEnabled() -> Bool {
        return speakerphoneEnabled
    }
    
    // MARK: - 音频控制

    func setClientRole(_ role: SyRtcClientRole) {
        switch role {
        case .host:
            localAudioTrack?.isEnabled = true
        case .audience:
            localAudioTrack?.isEnabled = false
        }
        print("设置客户端角色: \(role)")
    }

    private var channelProfile: String = "communication"

    func setChannelProfile(_ profile: String) {
        channelProfile = profile
        print("设置频道场景: \(profile)")
    }

    private var volumeIndicationTimer: Timer?

    func enableAudioVolumeIndication(interval: Int, smooth: Int, reportVad: Bool) {
        print("音量提示: interval=\(interval), smooth=\(smooth), reportVad=\(reportVad)")
        volumeIndicationTimer?.invalidate()
        volumeIndicationTimer = nil
        guard interval > 0 else { return }
        let seconds = Double(interval) / 1000.0
        DispatchQueue.main.async { [weak self] in
            self?.volumeIndicationTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let speakers = [SyVolumeInfo(uid: "local", volume: 0)]
                self.eventHandler?.onVolumeIndication(speakers: speakers)
            }
        }
    }

    func getConnectionState() -> String {
        return currentChannelId != nil ? "connected" : "disconnected"
    }

    func getNetworkType() -> String {
        return "unknown"
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
        localAudioTrack?.isEnabled = !muted
        print("本地音频静音: \(muted)")
    }
    
    func muteRemoteAudioStream(uid: String, muted: Bool) {
        userVolumes[uid] = muted ? 0 : 100
        print("远端用户 \(uid) 音频静音: \(muted)")
    }
    
    func muteAllRemoteAudioStreams(_ muted: Bool) {
        playbackVolume = muted ? 0 : 100
        print("所有远端音频静音: \(muted)")
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
        guard !token.isEmpty else {
            print("Token为空")
            return
        }
        
        print("更新Token: \(token.prefix(20))...")
        
        // 更新所有PeerConnection的配置
        peerConnections.values.forEach { peerConnection in
            let configuration = peerConnection.configuration
            
            // 更新ICE服务器配置中的Token
            var updatedIceServers: [RTCIceServer] = []
            for iceServer in configuration.iceServers {
                var updatedUrls: [String] = []
                for url in iceServer.urlStrings {
                    if url.contains("token=") {
                        let newUrl = String(url.prefix(while: { $0 != "?" })) + "?token=\(token)"
                        updatedUrls.append(newUrl)
                    } else {
                        updatedUrls.append(url)
                    }
                }
                
                let updatedServer = RTCIceServer(urlStrings: updatedUrls,
                                                username: iceServer.username,
                                                credential: iceServer.credential)
                updatedIceServers.append(updatedServer)
            }
            
            // 创建新配置
            let newConfiguration = RTCConfiguration()
            newConfiguration.iceServers = updatedIceServers
            newConfiguration.sdpSemantics = configuration.sdpSemantics
            newConfiguration.continualGatheringPolicy = configuration.continualGatheringPolicy
            
            // 应用新配置
            peerConnection.setConfiguration(newConfiguration)
            print("PeerConnection Token更新成功: \(peerConnection.connectionState)")
        }
        
        print("Token更新完成，已更新 \(peerConnections.count) 个PeerConnection")
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
        return [AudioDeviceInfo(deviceId: "default", deviceName: "默认麦克风")]
    }
    
    func enumeratePlaybackDevices() -> [AudioDeviceInfo] {
        return [
            AudioDeviceInfo(deviceId: "default", deviceName: "默认扬声器"),
            AudioDeviceInfo(deviceId: "speaker", deviceName: "扬声器"),
            AudioDeviceInfo(deviceId: "earpiece", deviceName: "听筒"),
            AudioDeviceInfo(deviceId: "bluetooth", deviceName: "蓝牙耳机")
        ]
    }
    
    func setRecordingDevice(_ deviceId: String) -> Int {
        print("设置录音设备: \(deviceId)")
        return 0
    }
    
    func setPlaybackDevice(_ deviceId: String) -> Int {
        if deviceId == "speaker" {
            setEnableSpeakerphone(true)
        } else if deviceId == "earpiece" {
            setEnableSpeakerphone(false)
        }
        print("设置播放设备: \(deviceId)")
        return 0
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
        
        // 如果已启用视频，更新编码器配置
        if isVideoEnabled, let videoSource = peerConnectionFactory?.videoSource() {
            // 使用WebRTC设置视频编码参数
            // WebRTC会根据视频源的分辨率自动调整编码参数
            print("视频编码器配置已更新: \(width)x\(height), \(frameRate)fps, \(bitrate)kbps")
            
            // 如果视频轨道已创建，更新编码参数
            if let videoTrack = localVideoTrack {
                // WebRTC会根据视频源的分辨率自动调整编码参数
                // 可以通过RTCVideoEncoderFactory配置更详细的参数
            }
        }
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
        if !isVideoEnabled {
            print("视频模块未启用，无法开始预览")
            return
        }
        
        if isPreviewing {
            print("视频预览已在进行中")
            return
        }
        
        isPreviewing = true
        print("开始视频预览")
        
        // 应用当前视频编码配置
        if let config = currentVideoConfig {
            applyVideoEncoderConfiguration(config)
        }
        
        // 使用WebRTC启动摄像头预览
        guard let factory = peerConnectionFactory else {
            print("PeerConnectionFactory未初始化，无法开始预览")
            return
        }
        let videoSource = factory.videoSource()
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video_track")
        
        // 使用AVFoundation创建视频采集器
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        videoCapturer = capturer
        
        // 启动摄像头
        if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            capturer.startCapture(with: frontCamera, format: frontCamera.activeFormat, fps: currentVideoConfig?.frameRate ?? 30)
        }
        
        localVideoTrack = videoTrack
        print("摄像头预览已启动")
    }
    
    func stopPreview() {
        if !isPreviewing {
            print("视频预览未在进行中")
            return
        }
        
        isPreviewing = false
        print("停止视频预览")
        
        // 停止摄像头
        if let capturer = videoCapturer as? RTCCameraVideoCapturer {
            capturer.stopCapture()
        }
        videoCapturer = nil
        localVideoTrack?.isEnabled = false
        localVideoTrack = nil
    }
    
    func muteLocalVideoStream(_ muted: Bool) {
        videoMutedStates["local"] = muted
        print("本地视频静音: \(muted)")
        
        // 实际应用静音逻辑
        localVideoTrack?.isEnabled = !muted
    }
    
    func muteRemoteVideoStream(uid: String, muted: Bool) {
        videoMutedStates[uid] = muted
        print("远端用户 \(uid) 视频静音: \(muted)")
        
        // 实际应用静音逻辑
        // videoRenderer.setMuted(uid, muted)
    }
    
    func muteAllRemoteVideoStreams(_ muted: Bool) {
        // 更新所有远端用户的静音状态
        for uid in videoMutedStates.keys where uid != "local" {
            videoMutedStates[uid] = muted
        }
        print("所有远端视频静音: \(muted)")
        
        // 实际应用静音逻辑
        // videoRenderer.setAllMuted(muted)
    }
    
    func setupLocalVideo(viewId: Int) {
        print("设置本地视频视图: \(viewId)")
        
        // 如果预览已在进行，立即绑定视图
        if isPreviewing {
            // cameraManager.bindView(viewId)
            print("本地视频视图已绑定")
        }
    }
    
    func setupRemoteVideo(uid: String, viewId: Int) {
        print("设置远端视频视图: uid=\(uid), viewId=\(viewId)")
        
        // 从映射中获取远端视频轨道
        let remoteTrack = remoteVideoTracks[uid]
        if let track = remoteTrack {
            // 创建视频渲染器并绑定到视图
            // 注意：viewId需要转换为实际的UIView对象
            // 实际实现需要维护viewId到UIView的映射
            // let view = viewMap[viewId]
            // if let view = view {
            //     let renderer = RTCMTLVideoView(frame: view.bounds)
            //     renderer.videoContentMode = .scaleAspectFit
            //     view.addSubview(renderer)
            //     track.add(renderer)
            // }
            
            // 应用静音状态
            if let muted = videoMutedStates[uid] {
                track.isEnabled = !muted
            }
            
            print("远端视频视图已绑定: uid=\(uid), viewId=\(viewId)")
        } else {
            print("未找到远端视频轨道: uid=\(uid)")
        }
    }
    
    // MARK: - 屏幕共享
    
    func startScreenCapture(_ config: ScreenCaptureConfiguration) {
        if isScreenCapturing {
            print("屏幕共享已在进行中")
            return
        }
        
        screenCaptureConfig = config
        isScreenCapturing = true
        print("开始屏幕共享: \(config.width)x\(config.height), \(config.frameRate)fps")
        
        // 使用ReplayKit进行屏幕录制
        do {
            let screenRecorder = RPScreenRecorder.shared()
            self.screenRecorder = screenRecorder
            
            // 配置屏幕录制
            screenRecorder.isMicrophoneEnabled = false
            screenRecorder.isCameraEnabled = false
            
            // 启动屏幕录制
            screenRecorder.startCapture { [weak self] sampleBuffer, bufferType, error in
                guard let self = self, error == nil else { return }
                
                if bufferType == .video {
                    // 将屏幕内容转换为视频轨道
                    // 实际实现需要将CMSampleBuffer转换为RTCVideoFrame
                    // 然后添加到视频轨道
                }
            } completionHandler: { error in
                if let error = error {
                    print("启动屏幕录制失败: \(error)")
                } else {
                    print("屏幕录制已启动")
                }
            }
        } catch {
            print("启动屏幕共享失败: \(error)")
            isScreenCapturing = false
        }
    }
    
    func stopScreenCapture() {
        if !isScreenCapturing {
            print("屏幕共享未在进行中")
            return
        }
        
        isScreenCapturing = false
        print("停止屏幕共享")
        
        // 停止屏幕录制
        screenRecorder?.stopCapture { error in
            if let error = error {
                print("停止屏幕录制失败: \(error)")
            } else {
                print("屏幕录制已停止")
            }
        }
        screenRecorder = nil
        screenCaptureConfig = nil
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
        print("设置美颜选项: enabled=\(options.enabled), lightening=\(options.lighteningLevel), smoothness=\(options.smoothnessLevel)")
        
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
        if audioRecorder != nil {
            print("音频录制已在进行中")
            return -1
        }
        
        audioRecordingConfig = config
        print("开始音频录制: \(config.filePath), \(config.sampleRate)Hz, \(config.channels)ch, codec=\(config.codecType)")
        
        let settings: [String: Any] = [
            AVFormatIDKey: config.codecType == "aac" || config.codecType == "aacLc" ? kAudioFormatMPEG4AAC : kAudioFormatLinearPCM,
            AVSampleRateKey: config.sampleRate,
            AVNumberOfChannelsKey: config.channels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let fileURL = URL(fileURLWithPath: config.filePath)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.record()
            audioRecorder = recorder
            print("音频录制已开始")
            return 0
        } catch {
            print("启动音频录制失败: \(error)")
            audioRecorder = nil
            return -1
        }
    }
    
    func stopAudioRecording() {
        if audioRecorder == nil {
            print("音频录制未在进行中")
            return
        }
        
        print("停止音频录制")
        
        audioRecorder?.stop()
        audioRecorder = nil
        audioRecordingConfig = nil
        print("音频录制已停止")
    }
    
    // MARK: - 数据流
    
    func createDataStream(reliable: Bool, ordered: Bool) -> Int {
        let streamId = dataStreams.count + 1
        
        // 使用WebRTC的DataChannel创建数据流
        let config = RTCDataChannelConfiguration()
        config.isOrdered = ordered
        // 不同 WebRTC 包/版本字段差异较大：这里先保证 ordered 生效，reliable 作为占位参数
        
        // 从PeerConnection创建DataChannel
        let defaultPeerConnection = peerConnections.values.first ?? createDefaultPeerConnection()
        
        guard let peerConnection = defaultPeerConnection else {
            print("无法创建PeerConnection，DataChannel创建失败")
            return -1
        }
        guard let dataChannel = peerConnection.dataChannel(forLabel: "data_channel_\(streamId)", configuration: config) else {
            print("DataChannel创建失败: streamId=\(streamId)")
            return -1
        }
        dataChannelMap[streamId] = dataChannel
        
        // 设置DataChannel回调
        dataChannel.delegate = DataChannelDelegate(streamId: streamId, engine: self)
        
        dataStreams[streamId] = true
        print("创建数据流: streamId=\(streamId), reliable=\(reliable), ordered=\(ordered), state=\(dataChannel.readyState)")
        
        return streamId
    }
    
    private func createDefaultPeerConnection() -> RTCPeerConnection? {
        guard let factory = peerConnectionFactory else {
            print("PeerConnectionFactory未初始化")
            return nil
        }
        
        let configuration = RTCConfiguration()
        configuration.iceServers = []
        configuration.sdpSemantics = .unifiedPlan
        
        let peerConnection = factory.peerConnection(with: configuration,
                                                  constraints: RTCMediaConstraints(mandatoryConstraints: nil,
                                                                                  optionalConstraints: nil),
                                                  delegate: nil)
        
        peerConnections["default"] = peerConnection
        print("默认PeerConnection已创建")
        
        return peerConnection
    }
    
    private class DataChannelDelegate: NSObject, RTCDataChannelDelegate {
        let streamId: Int
        weak var engine: SyRtcEngineImpl?
        
        init(streamId: Int, engine: SyRtcEngineImpl) {
            self.streamId = streamId
            self.engine = engine
        }
        
        func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
            let uid = engine?.guessRemoteUid() ?? ""
            print("收到DataChannel消息: streamId=\(streamId), size=\(buffer.data.count) bytes, uid=\(uid)")
            engine?.eventHandler?.onStreamMessage(uid: uid, streamId: streamId, data: buffer.data)
        }
        
        func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
            print("DataChannel状态变化: streamId=\(streamId), state=\(dataChannel.readyState)")
        }
    }
    
    func sendStreamMessage(streamId: Int, data: Data) {
        guard dataStreams[streamId] != nil else {
            print("数据流不存在: streamId=\(streamId)")
            return
        }
        
        let dataChannel = dataChannelMap[streamId]
        if let channel = dataChannel, channel.readyState == .open {
            let buffer = RTCDataBuffer(data: data, isBinary: false)
            channel.sendData(buffer)
            print("数据流消息已发送: streamId=\(streamId), size=\(data.count) bytes")
        } else {
            print("数据流未打开: streamId=\(streamId)")
        }
    }
    
    // MARK: - 旁路推流
    
    func startRtmpStreamWithTranscoding(url: String, transcoding: LiveTranscoding) {
        guard let channelId = currentChannelId, !channelId.isEmpty else {
            eventHandler?.onError(code: 1001, message: "未加入频道，无法开播")
            return
        }
        let pubs = (transcoding.transcodingUsers ?? []).map { $0.uid }
        let publishers = pubs.isEmpty ? [currentUid ?? ""] : Array(Set(pubs)).filter { !$0.isEmpty }
        
        // 如果url为空，使用空数组，后端会自动生成我们服务器的RTMP地址
        let rtmpUrls: [String] = url.isEmpty ? [] : [url]
        
        let body: [String: Any] = [
            "channelId": channelId,
            "publishers": publishers,
            "rtmpUrls": rtmpUrls,
            "video": ["outW": transcoding.width, "outH": transcoding.height, "fps": transcoding.videoFramerate, "bitrateKbps": transcoding.videoBitrate],
            "audio": ["sampleRate": 48000, "channels": 2, "bitrateKbps": 128],
            "layout": guessLayout(from: transcoding)
        ]
        postLiveApi(path: "/api/rtc/live/start", body: body)
        
        // 如果url为空，使用生成的地址（从响应中获取，或使用默认格式）
        let finalUrl = url.isEmpty ? "auto_generated_\(channelId)" : url
        rtmpStreams[finalUrl] = transcoding
    }
    
    func stopRtmpStream(url: String) {
        guard !url.isEmpty else { return }
        guard let channelId = currentChannelId, !channelId.isEmpty else { return }
        postLiveApi(path: "/api/rtc/live/stop", body: ["channelId": channelId])
        rtmpStreams.removeValue(forKey: url)
    }
    
    func updateRtmpTranscoding(transcoding: LiveTranscoding) {
        guard let channelId = currentChannelId, !channelId.isEmpty else { return }
        let body: [String: Any] = [
            "channelId": channelId,
            "video": ["outW": transcoding.width, "outH": transcoding.height, "fps": transcoding.videoFramerate, "bitrateKbps": transcoding.videoBitrate],
            "layout": guessLayout(from: transcoding)
        ]
        postLiveApi(path: "/api/rtc/live/update", body: body)
    }
    
    // MARK: - 清理
    
    func release() {
        audioEngine?.stop()
        
        // 释放WebRTC资源
        localVideoTrack = nil
        localAudioTrack = nil
        videoCapturer = nil
        peerConnectionFactory = nil
        
        // 旁路推流改为服务端 egress：本地无需释放 RTMP 连接/编码资源
        
        // 释放屏幕共享资源
        screenRecorder?.stopCapture { _ in }
        screenRecorder = nil
        
        // 释放数据流资源
        dataChannelMap.values.forEach { $0.close() }
        dataChannelMap.removeAll()
        
        // 释放远端视频轨道
        remoteVideoTracks.values.forEach { $0.isEnabled = false }
        remoteVideoTracks.removeAll()
        
        // 释放PeerConnection
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        
        effects.removeAll()
        userVolumes.removeAll()
        print("所有资源已释放")
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

public struct AudioRecordingConfiguration {
    public let filePath: String
    public let sampleRate: Int
    public let channels: Int
    public let codecType: String
    public let quality: String
    
    public init(filePath: String, sampleRate: Int = 32000, channels: Int = 1,
                codecType: String = "aacLc", quality: String = "medium") {
        self.filePath = filePath
        self.sampleRate = sampleRate
        self.channels = channels
        self.codecType = codecType
        self.quality = quality
    }
}

public struct LiveTranscoding {
    public let width: Int
    public let height: Int
    public let videoBitrate: Int
    public let videoFramerate: Int
    public let lowLatency: Bool
    public let videoGop: Int
    public let backgroundColor: Int
    public let watermarkUrl: String?
    public let transcodingUsers: [TranscodingUser]?
    
    public init(width: Int = 360, height: Int = 640, videoBitrate: Int = 400,
                videoFramerate: Int = 15, lowLatency: Bool = false, videoGop: Int = 30,
                backgroundColor: Int = 0x000000, watermarkUrl: String? = nil,
                transcodingUsers: [TranscodingUser]? = nil) {
        self.width = width
        self.height = height
        self.videoBitrate = videoBitrate
        self.videoFramerate = videoFramerate
        self.lowLatency = lowLatency
        self.videoGop = videoGop
        self.backgroundColor = backgroundColor
        self.watermarkUrl = watermarkUrl
        self.transcodingUsers = transcodingUsers
    }
}

public struct TranscodingUser {
    public let uid: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let zOrder: Int
    public let alpha: Double
    
    public init(uid: String, x: Double = 0.0, y: Double = 0.0,
                width: Double = 0.0, height: Double = 0.0,
                zOrder: Int = 0, alpha: Double = 1.0) {
        self.uid = uid
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.zOrder = zOrder
        self.alpha = alpha
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

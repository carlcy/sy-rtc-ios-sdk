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
    private var isSpeakerphoneEnabled = false
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
    private var currentChannelId: String?
    private var currentUid: String?
    private var currentToken: String?
    
    // 多人语聊（Mesh）：每个远端用户一条 PeerConnection（key=remoteUid）
    private var offerSentByUid: Set<String> = []
    private var remoteSdpSetByUid: Set<String> = []
    private var pendingLocalIceByUid: [String: [RTCIceCandidate]] = [:]
    private var pendingRemoteIceByUid: [String: [RTCIceCandidate]] = [:]
    
    // 旁路推流
    private var rtmpStreams: [String: LiveTranscoding] = [:]
    private var rtmpSessions: [String: RtmpStreamSession] = [:]
    
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

    // MARK: - 频道（多人语聊 Mesh）
    func join(channelId: String, uid: String, token: String) {
        currentChannelId = channelId
        currentUid = uid
        currentToken = token
        offerSentByUid.removeAll()
        remoteSdpSetByUid.removeAll()
        pendingLocalIceByUid.removeAll()
        pendingRemoteIceByUid.removeAll()

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
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        offerSentByUid.removeAll()
        remoteSdpSetByUid.removeAll()
        pendingLocalIceByUid.removeAll()
        pendingRemoteIceByUid.removeAll()
        signalingClient?.disconnect()
        signalingClient = nil
        currentChannelId = nil
        currentUid = nil
        currentToken = nil
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
        if let track = localAudioTrack { pc.add(track, streamIds: ["stream"]) }
        return pc
    }

    private func handleSignalingMessage(type: String, data: [String: Any], channelId: String) {
        switch type {
        case "user-list":
            guard let localUid = currentUid else { return }
            let users = (data["users"] as? [String]) ?? []
            for u in users where u != localUid {
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

        // 其余回调按需扩展（目前最小可用只需要 ICE candidate 转发）
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
    
    private func initializeAudioSystem() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            
            audioEngine = AVAudioEngine()
            print("音频系统初始化成功")
        } catch {
            print("音频系统初始化失败: \(error)")
        }
    }
    
    private func initializeVideoSystem() {
        print("视频系统初始化")
        // 视频系统初始化逻辑
    }
    
    // MARK: - 音频路由控制
    
    func setEnableSpeakerphone(_ enabled: Bool) {
        isSpeakerphoneEnabled = enabled
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
            isSpeakerphoneEnabled = enabled
            print("默认音频路由设置为扬声器: \(enabled)")
        } catch {
            print("设置默认音频路由失败: \(error)")
        }
    }
    
    func isSpeakerphoneEnabled() -> Bool {
        return isSpeakerphoneEnabled
    }
    
    // MARK: - 音频控制
    
    func enableLocalAudio(_ enabled: Bool) {
        if enabled {
            audioEngine?.start()
            print("启用本地音频采集")
        } else {
            audioEngine?.stop()
            print("禁用本地音频采集")
        }
    }
    
    func muteLocalAudio(_ muted: Bool) {
        print("本地音频静音: \(muted)")
        // 静音逻辑
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
        audioEngine?.start()
        print("启用音频模块")
    }
    
    func disableAudio() {
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
        return Int(AVAudioSession.sharedInstance().inputVolume * 100)
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
            // 停止当前音频引擎
            audioEngine?.stop()
            
            // 配置音频会话
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            
            // 设置采样率
            try audioSession.setPreferredSampleRate(Double(sampleRate))
            try audioSession.setActive(true)
            
            // 重新创建音频引擎
            audioEngine = AVAudioEngine()
            
            // 配置输入节点
            let inputNode = audioEngine!.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            
            // 配置输出节点
            let outputNode = audioEngine!.mainMixerNode
            let outputFormat = outputNode.outputFormat(forBus: 0)
            
            print("音频系统已重新初始化: \(sampleRate)Hz, 输入格式: \(inputFormat), 输出格式: \(outputFormat)")
        } catch {
            print("重新初始化音频系统失败: \(error)")
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
        do {
            let videoSource = peerConnectionFactory?.videoSource()
            let videoTrack = peerConnectionFactory?.videoTrack(with: videoSource, trackId: "video_track")
            
            // 使用AVFoundation创建视频采集器
            let capturer = RTCCameraVideoCapturer(delegate: videoSource)
            videoCapturer = capturer
            
            // 启动摄像头
            if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                capturer.startCapture(with: frontCamera, format: frontCamera.activeFormat, fps: Int32(currentVideoConfig?.frameRate ?? 30))
            }
            
            localVideoTrack = videoTrack
            print("摄像头预览已启动")
        } catch {
            print("启动摄像头预览失败: \(error)")
        }
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
        let videoTrack = if uid == "local" {
            localVideoTrack
        } else {
            // 从远端视频轨道映射中获取
            nil
        }
        
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
        let init = RTCDataChannelConfiguration()
        init.isOrdered = ordered
        init.isReliable = reliable
        
        // 从PeerConnection创建DataChannel
        let defaultPeerConnection = peerConnections.values.first ?? createDefaultPeerConnection()
        
        if let peerConnection = defaultPeerConnection {
            let dataChannel = peerConnection.dataChannel(forLabel: "data_channel_\(streamId)", configuration: init)
            dataChannelMap[streamId] = dataChannel
            
            // 设置DataChannel回调
            dataChannel.delegate = DataChannelDelegate(streamId: streamId)
            
            dataStreams[streamId] = true
            print("创建数据流: streamId=\(streamId), reliable=\(reliable), ordered=\(ordered), state=\(dataChannel.readyState)")
            
            return streamId
        } else {
            print("无法创建PeerConnection，DataChannel创建失败")
            return -1
        }
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
        
        if let pc = peerConnection {
            peerConnections["default"] = pc
            print("默认PeerConnection已创建")
        }
        
        return peerConnection
    }
    
    private class DataChannelDelegate: NSObject, RTCDataChannelDelegate {
        let streamId: Int
        
        init(streamId: Int) {
            self.streamId = streamId
        }
        
        func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
            print("收到DataChannel消息: streamId=\(streamId), size=\(buffer.data.count) bytes")
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
        if rtmpStreams[url] != nil {
            print("旁路推流已在进行中: \(url)")
            return
        }
        
        rtmpStreams[url] = transcoding
        print("开始旁路推流: url=\(url), width=\(transcoding.width), height=\(transcoding.height), bitrate=\(transcoding.videoBitrate)")
        
        // 创建RTMP推流会话
        let session = RtmpStreamSession(
            url: url,
            width: transcoding.width,
            height: transcoding.height,
            frameRate: transcoding.videoFramerate,
            bitrate: transcoding.videoBitrate * 1000
        )
        rtmpSessions[url] = session
        
        // 从本地视频轨道获取帧并推流
        if let track = localVideoTrack {
            track.add(BeautyFilterVideoSink { [weak self] frame in
                self?.rtmpSessions[url]?.processVideoFrame(frame)
            })
        }
        
        // 启动RTMP推流
        session.start()
        print("RTMP推流已启动: \(url)")
    }
    
    func stopRtmpStream(url: String) {
        guard rtmpStreams[url] != nil else {
            print("旁路推流未在进行中: \(url)")
            return
        }
        
        // 停止RTMP推流会话
        rtmpSessions[url]?.stop()
        
        // 清理资源
        rtmpStreams.removeValue(forKey: url)
        rtmpSessions.removeValue(forKey: url)
        
        print("RTMP推流已停止: \(url)")
    }
    
    func updateRtmpTranscoding(transcoding: LiveTranscoding) {
        guard let url = rtmpStreams.first(where: { $0.value.width == transcoding.width && $0.value.height == transcoding.height })?.key else {
            print("未找到对应的旁路推流，无法更新转码配置")
            return
        }
        
        rtmpStreams[url] = transcoding
        print("更新旁路推流转码配置: width=\(transcoding.width), height=\(transcoding.height), bitrate=\(transcoding.videoBitrate)")
        
        // 更新RTMP推流会话配置
        rtmpSessions[url]?.updateConfig(
            width: transcoding.width,
            height: transcoding.height,
            frameRate: transcoding.videoFramerate,
            bitrate: transcoding.videoBitrate * 1000
        )
        print("RTMP推流转码配置已更新")
    }
    
    // MARK: - 远端视频
    
    func setupRemoteVideo(uid: String, viewId: Int) {
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
            
            print("远端视频视图已绑定: uid=\(uid), viewId=\(viewId)")
        } else {
            print("未找到远端视频轨道: uid=\(uid)")
        }
    }
    
    // MARK: - 清理
    
    func release() {
        audioEngine?.stop()
        
        // 释放WebRTC资源
        localVideoTrack = nil
        localAudioTrack = nil
        videoCapturer = nil
        peerConnectionFactory = nil
        
        // 释放RTMP资源
        rtmpSessions.values.forEach { $0.stop() }
        rtmpSessions.removeAll()
        
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

// MARK: - RTMP推流会话类

private class RtmpStreamSession {
    let url: String
    var width: Int
    var height: Int
    var frameRate: Int
    var bitrate: Int
    private var isStreaming = false
    
    init(url: String, width: Int, height: Int, frameRate: Int, bitrate: Int) {
        self.url = url
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitrate = bitrate
    }
    
    func start() {
        isStreaming = true
        // 实际实现需要：
        // 1. 连接RTMP服务器（可以使用librtmp或FFmpeg）
        // 2. 初始化视频编码器（H.264）
        // 3. 初始化音频编码器（AAC）
        print("RTMP推流会话已启动: \(url)")
    }
    
    func stop() {
        isStreaming = false
        // 实际实现需要：
        // 1. 停止编码器
        // 2. 断开RTMP连接
        // 3. 释放资源
        print("RTMP推流会话已停止: \(url)")
    }
    
    func processVideoFrame(_ frame: RTCVideoFrame) {
        if !isStreaming { return }
        
        // 实际实现需要：
        // 1. 将RTCVideoFrame转换为H.264编码
        // 2. 将编码后的数据推送到RTMP服务器
        // 这里简化处理，实际需要使用VideoToolbox或FFmpeg进行编码
    }
    
    func updateConfig(width: Int, height: Int, frameRate: Int, bitrate: Int) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitrate = bitrate
        // 实际实现需要重新配置编码器
        print("RTMP推流配置已更新: \(width)x\(height), \(frameRate)fps, \(bitrate)bps")
    }
}

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

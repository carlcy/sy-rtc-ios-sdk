import Foundation

/// SY RTC引擎主类
/// 
/// SY RTC 引擎主类，提供实时音视频通信功能
public class SyRtcEngine {
    private var appId: String?
    private var eventHandler: SyRtcEventHandler?
    private var impl: SyRtcEngineImpl?
    
    /// 单例
    public static let shared = SyRtcEngine()
    
    private init() {}
    
    // MARK: - 初始化

    public func initialize(appId: String) {
        self.appId = appId
        impl = SyRtcEngineImpl(appId: appId)
        impl?.initialize()
    }
    
    public func `init`(_ appId: String) {
        initialize(appId: appId)
    }

    public func setSignalingServerUrl(_ url: String) {
        impl?.setSignalingServerUrl(url)
    }

    public func setApiBaseUrl(_ url: String) {
        impl?.setApiBaseUrl(url)
    }

    public func setApiAuthToken(_ token: String) {
        impl?.setApiAuthToken(token)
    }

    public func setEventHandler(_ handler: SyRtcEventHandler) {
        self.eventHandler = handler
        impl?.eventHandler = handler
    }

    // MARK: - 频道管理

    public func join(channelId: String, uid: String, token: String) {
        impl?.eventHandler = eventHandler
        impl?.join(channelId: channelId, uid: uid, token: token)
    }
    
    public func leave() {
        impl?.leave()
    }

    // MARK: - 音频控制

    public func enableLocalAudio(_ enabled: Bool) {
        impl?.enableLocalAudio(enabled)
    }
    
    public func muteLocalAudio(_ muted: Bool) {
        impl?.muteLocalAudio(muted)
    }

    public func sendChannelMessage(_ message: String) {
        impl?.sendChannelMessage(message)
    }

    public func setClientRole(_ role: SyRtcClientRole) {
        impl?.setClientRole(role)
    }

    /// 设置频道场景
    ///
    /// 必须在 `join` 之前调用。
    /// - Parameter profile: 场景："communication"（通信）或 "liveBroadcasting"（直播）
    public func setChannelProfile(_ profile: String) {
        impl?.setChannelProfile(profile)
    }

    /// 启用用户音量提示
    ///
    /// 启用后，SDK 会按设定间隔触发 `onVolumeIndication` 回调。
    /// - Parameters:
    ///   - interval: 回调间隔（毫秒），建议 200ms。设为 0 禁用。
    ///   - smooth: 平滑系数，建议 3
    ///   - reportVad: 是否报告本地用户的人声检测，默认 false
    public func enableAudioVolumeIndication(interval: Int = 200, smooth: Int = 3, reportVad: Bool = false) {
        impl?.enableAudioVolumeIndication(interval: interval, smooth: smooth, reportVad: reportVad)
    }

    /// 获取当前连接状态
    public func getConnectionState() -> String {
        return impl?.getConnectionState() ?? "disconnected"
    }

    /// 获取当前网络类型
    public func getNetworkType() -> String {
        return impl?.getNetworkType() ?? "unknown"
    }

    // MARK: - 音频路由

    public func setEnableSpeakerphone(_ enabled: Bool) {
        impl?.setEnableSpeakerphone(enabled)
    }

    public func setDefaultAudioRouteToSpeakerphone(_ enabled: Bool) {
        impl?.setDefaultAudioRouteToSpeakerphone(enabled)
    }

    public func isSpeakerphoneEnabled() -> Bool {
        return impl?.isSpeakerphoneEnabled() ?? false
    }

    // MARK: - 远端音频控制

    public func muteRemoteAudioStream(uid: String, muted: Bool) {
        impl?.muteRemoteAudioStream(uid: uid, muted: muted)
    }

    public func muteAllRemoteAudioStreams(_ muted: Bool) {
        impl?.muteAllRemoteAudioStreams(muted)
    }

    public func adjustUserPlaybackSignalVolume(uid: String, volume: Int) {
        impl?.adjustUserPlaybackSignalVolume(uid: uid, volume: volume)
    }

    public func adjustPlaybackSignalVolume(_ volume: Int) {
        impl?.adjustPlaybackSignalVolume(volume)
    }

    // MARK: - Token 刷新

    public func renewToken(_ token: String) {
        impl?.renewToken(token)
    }

    // MARK: - 音频配置

    public func setAudioProfile(_ profile: String, scenario: String) {
        impl?.setAudioProfile(profile, scenario: scenario)
    }

    public func enableAudio() {
        impl?.enableAudio()
    }

    public func disableAudio() {
        impl?.disableAudio()
    }

    public func setAudioQuality(_ quality: String) {
        impl?.setAudioQuality(quality)
    }

    // MARK: - 音频设备管理

    public func enumerateRecordingDevices() -> [AudioDeviceInfo] {
        return impl?.enumerateRecordingDevices() ?? []
    }

    public func enumeratePlaybackDevices() -> [AudioDeviceInfo] {
        return impl?.enumeratePlaybackDevices() ?? []
    }

    public func setRecordingDevice(_ deviceId: String) -> Int {
        return impl?.setRecordingDevice(deviceId) ?? -1
    }

    public func setPlaybackDevice(_ deviceId: String) -> Int {
        return impl?.setPlaybackDevice(deviceId) ?? -1
    }

    public func getRecordingDeviceVolume() -> Int {
        return impl?.getRecordingDeviceVolume() ?? 0
    }

    public func setRecordingDeviceVolume(_ volume: Int) {
        impl?.setRecordingDeviceVolume(volume)
    }

    public func getPlaybackDeviceVolume() -> Int {
        return impl?.getPlaybackDeviceVolume() ?? 0
    }

    public func setPlaybackDeviceVolume(_ volume: Int) {
        impl?.setPlaybackDeviceVolume(volume)
    }

    // MARK: - 音频采集控制

    public func adjustRecordingSignalVolume(_ volume: Int) {
        impl?.adjustRecordingSignalVolume(volume)
    }

    public func muteRecordingSignal(_ muted: Bool) {
        impl?.muteLocalAudio(muted)
    }

    // MARK: - 视频基础

    public func enableVideo() {
        impl?.enableVideo()
    }

    public func disableVideo() {
        impl?.disableVideo()
    }

    public func enableLocalVideo(_ enabled: Bool) {
        impl?.enableLocalVideo(enabled)
    }

    public func setVideoEncoderConfiguration(_ config: VideoEncoderConfiguration) {
        impl?.setVideoEncoderConfiguration(config)
    }

    public func setVideoEncoderConfiguration(width: Int, height: Int, frameRate: Int, bitrate: Int) {
        impl?.setVideoEncoderConfiguration(width: width, height: height, frameRate: frameRate, bitrate: bitrate)
    }

    public func startPreview() {
        impl?.startPreview()
    }

    public func stopPreview() {
        impl?.stopPreview()
    }

    public func muteLocalVideoStream(_ muted: Bool) {
        impl?.muteLocalVideoStream(muted)
    }

    public func muteRemoteVideoStream(uid: String, muted: Bool) {
        impl?.muteRemoteVideoStream(uid: uid, muted: muted)
    }

    public func muteAllRemoteVideoStreams(_ muted: Bool) {
        impl?.muteAllRemoteVideoStreams(muted)
    }

    // MARK: - 视频渲染

    public func setupLocalVideo(viewId: Int) {
        impl?.setupLocalVideo(viewId: viewId)
    }

    public func setupRemoteVideo(uid: String, viewId: Int) {
        impl?.setupRemoteVideo(uid: uid, viewId: viewId)
    }

    // MARK: - 屏幕共享

    public func startScreenCapture(_ config: ScreenCaptureConfiguration) {
        impl?.startScreenCapture(config)
    }

    public func stopScreenCapture() {
        impl?.stopScreenCapture()
    }

    public func updateScreenCaptureConfiguration(_ config: ScreenCaptureConfiguration) {
        impl?.updateScreenCaptureConfiguration(config)
    }

    // MARK: - 视频增强

    public func setBeautyEffectOptions(_ options: BeautyOptions) {
        impl?.setBeautyEffectOptions(options)
    }

    public func takeSnapshot(uid: String, filePath: String) {
        impl?.takeSnapshot(uid: uid, filePath: filePath)
    }

    // MARK: - 音乐文件播放

    public func startAudioMixing(_ config: AudioMixingConfiguration) {
        impl?.startAudioMixing(config)
    }

    public func stopAudioMixing() {
        impl?.stopAudioMixing()
    }

    public func pauseAudioMixing() {
        impl?.pauseAudioMixing()
    }

    public func resumeAudioMixing() {
        impl?.resumeAudioMixing()
    }

    public func adjustAudioMixingVolume(_ volume: Int) {
        impl?.adjustAudioMixingVolume(volume)
    }

    public func getAudioMixingCurrentPosition() -> Int {
        return impl?.getAudioMixingCurrentPosition() ?? 0
    }

    public func setAudioMixingPosition(_ position: Int) {
        impl?.setAudioMixingPosition(position)
    }

    // MARK: - 音效播放

    public func playEffect(soundId: Int, config: AudioEffectConfiguration) {
        impl?.playEffect(soundId: soundId, config: config)
    }

    public func stopEffect(_ soundId: Int) {
        impl?.stopEffect(soundId)
    }

    public func stopAllEffects() {
        impl?.stopAllEffects()
    }

    public func setEffectsVolume(_ volume: Int) {
        impl?.setEffectsVolume(volume)
    }

    public func preloadEffect(_ soundId: Int, filePath: String) {
        impl?.preloadEffect(soundId, filePath: filePath)
    }

    public func unloadEffect(_ soundId: Int) {
        impl?.unloadEffect(soundId)
    }

    // MARK: - 音频录制

    public func startAudioRecording(_ config: AudioRecordingConfiguration) -> Int {
        return impl?.startAudioRecording(config) ?? -1
    }

    public func stopAudioRecording() {
        impl?.stopAudioRecording()
    }

    // MARK: - 数据流

    public func createDataStream(reliable: Bool, ordered: Bool) -> Int {
        return impl?.createDataStream(reliable: reliable, ordered: ordered) ?? 0
    }

    public func sendStreamMessage(streamId: Int, data: Data) {
        impl?.sendStreamMessage(streamId: streamId, data: data)
    }

    // MARK: - 旁路推流

    public func startRtmpStreamWithTranscoding(url: String, transcoding: LiveTranscoding) {
        impl?.startRtmpStreamWithTranscoding(url: url, transcoding: transcoding)
    }

    public func stopRtmpStream(url: String) {
        impl?.stopRtmpStream(url: url)
    }

    public func updateRtmpTranscoding(transcoding: LiveTranscoding) {
        impl?.updateRtmpTranscoding(transcoding: transcoding)
    }

    // MARK: - 释放

    public func release() {
        impl?.release()
        impl = nil
        eventHandler = nil
        appId = nil
    }
}

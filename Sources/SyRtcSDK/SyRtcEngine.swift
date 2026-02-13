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
    
    /// 初始化引擎
    /// 
    /// - Parameter appId: 应用ID
    public func initialize(appId: String) {
        self.appId = appId
        impl = SyRtcEngineImpl(appId: appId)
        impl?.initialize()
    }
    
    /// 初始化引擎（兼容旧API）
    public func `init`(_ appId: String) {
        initialize(appId: appId)
    }
    
    /// 加入频道
    /// 
    /// - Parameters:
    ///   - channelId: 频道ID
    ///   - uid: 用户ID
    ///   - token: 鉴权Token
    public func join(channelId: String, uid: String, token: String) {
        impl?.eventHandler = eventHandler
        impl?.join(channelId: channelId, uid: uid, token: token)
    }
    
    /// 离开频道
    public func leave() {
        impl?.leave()
    }
    
    /// 启用/禁用本地音频
    /// 
    /// - Parameter enabled: true为启用，false为禁用
    public func enableLocalAudio(_ enabled: Bool) {
        impl?.enableLocalAudio(enabled)
    }
    
    /// 静音本地音频
    /// 
    /// - Parameter muted: true为静音，false为取消静音
    public func muteLocalAudio(_ muted: Bool) {
        impl?.muteLocalAudio(muted)
    }
    
    /// 设置客户端角色
    /// 
    /// - Parameter role: 角色：.host 或 .audience
    public func setClientRole(_ role: SyRtcClientRole) {
        impl?.setClientRole(role)
    }
    
    /// 设置事件处理器
    /// 
    /// - Parameter handler: 事件处理器
    public func setEventHandler(_ handler: SyRtcEventHandler) {
        self.eventHandler = handler
        impl?.eventHandler = handler
    }

    /// 设置信令服务器地址（可选）
    public func setSignalingServerUrl(_ url: String) {
        impl?.setSignalingServerUrl(url)
    }

    /// 设置后端 API Base URL（用于直播旁路：开播/关播/切布局/更新转码等）
    public func setApiBaseUrl(_ url: String) {
        impl?.setApiBaseUrl(url)
    }

    /// 设置后端 API 认证 Token（JWT）
    /// 用于调用 /api/rtc/live/* 等需要登录认证的接口
    public func setApiAuthToken(_ token: String) {
        impl?.setApiAuthToken(token)
    }
    
    /// 启用视频模块
    public func enableVideo() {
        impl?.enableVideo()
    }
    
    /// 设置视频编码配置
    public func setVideoEncoderConfiguration(width: Int, height: Int, frameRate: Int, bitrate: Int) {
        impl?.setVideoEncoderConfiguration(width: width, height: height, frameRate: frameRate, bitrate: bitrate)
    }
    
    /// 开始视频预览
    public func startPreview() {
        impl?.startPreview()
    }
    
    /// 停止视频预览
    public func stopPreview() {
        impl?.stopPreview()
    }
    
    /// 设置本地视频视图
    /// 
    /// - Parameter viewId: 视图ID（UIView的hash值）
    public func setupLocalVideo(viewId: Int) {
        impl?.setupLocalVideo(viewId: viewId)
    }
    
    /// 设置远端视频视图
    /// 
    /// - Parameters:
    ///   - uid: 用户ID
    ///   - viewId: 视图ID（UIView的hash值）
    public func setupRemoteVideo(uid: String, viewId: Int) {
        impl?.setupRemoteVideo(uid: uid, viewId: viewId)
    }
    
    /// 设置音频质量
    public func setAudioQuality(_ quality: String) {
        impl?.setAudioQuality(quality)
    }
    
    /// 释放资源
    public func release() {
        eventHandler = nil
        appId = nil
    }
}

import Foundation

/// SY RTC事件处理器协议
public protocol SyRtcEventHandler: AnyObject {
    /// 用户加入回调
    /// 
    /// - Parameters:
    ///   - uid: 用户ID
    ///   - elapsed: 加入耗时（毫秒）
    func onUserJoined(uid: String, elapsed: Int)
    
    /// 用户离开回调
    /// 
    /// - Parameters:
    ///   - uid: 用户ID
    ///   - reason: 离开原因
    func onUserOffline(uid: String, reason: String)
    
    /// 音量指示回调
    /// 
    /// - Parameter speakers: 说话者列表
    func onVolumeIndication(speakers: [SyVolumeInfo])

    /// 错误回调（可选）
    ///
    /// - Parameters:
    ///   - code: 错误码（自定义）
    ///   - message: 错误信息
    func onError(code: Int, message: String)

    /// 数据流消息回调（可选）
    ///
    /// - Parameters:
    ///   - uid: 发送方用户ID（未知时可能为空字符串）
    ///   - streamId: 数据流ID
    ///   - data: 二进制数据
    func onStreamMessage(uid: String, streamId: Int, data: Data)

    /// 数据流消息错误回调（可选）
    ///
    /// - Parameters:
    ///   - uid: 发送方用户ID（未知时可能为空字符串）
    ///   - streamId: 数据流ID
    ///   - code: 错误码
    ///   - missed: 丢失消息数
    ///   - cached: 缓存消息数
    func onStreamMessageError(uid: String, streamId: Int, code: Int, missed: Int, cached: Int)

    /// 频道消息回调
    ///
    /// - Parameters:
    ///   - uid: 发送方用户ID
    ///   - message: 消息内容（JSON字符串）
    func onChannelMessage(uid: String, message: String)
}

// MARK: - Optional callbacks (default empty implementations)

/// 默认实现：保持向后兼容（实现方可选择不实现以下可选回调）
public extension SyRtcEventHandler {
    func onJoinChannelSuccess(channelId: String, uid: String, elapsed: Int) {}
    func onLeaveChannel(stats: [String: Any]) {}
    func onRejoinChannelSuccess(channelId: String, uid: String, elapsed: Int) {}
    func onRtcStats(stats: [String: Any]) {}
    func onUserMuteAudio(uid: String, muted: Bool) {}
    func onConnectionStateChanged(state: String, reason: String) {}
    func onNetworkQuality(uid: String, txQuality: String, rxQuality: String) {}
    func onTokenPrivilegeWillExpire() {}
    func onRequestToken() {}
    func onLocalAudioStateChanged(state: String, error: String) {}
    func onRemoteAudioStateChanged(uid: String, state: String, reason: String, elapsed: Int) {}
    func onLocalVideoStateChanged(state: String, error: String) {}
    func onRemoteVideoStateChanged(uid: String, state: String, reason: String, elapsed: Int) {}
    func onFirstRemoteVideoDecoded(uid: String, width: Int, height: Int, elapsed: Int) {}
    func onFirstRemoteVideoFrame(uid: String, width: Int, height: Int, elapsed: Int) {}
    func onVideoSizeChanged(uid: String, width: Int, height: Int, rotation: Int) {}
    func onAudioRoutingChanged(routing: Int) {}
    func onAudioPublishStateChanged(channelId: String, oldState: String, newState: String, elapsed: Int) {}
    func onAudioSubscribeStateChanged(channelId: String, uid: String, oldState: String, newState: String, elapsed: Int) {}
}

/// 音量信息
public struct SyVolumeInfo {
    public let uid: String
    public let volume: Int
    
    public init(uid: String, volume: Int) {
        self.uid = uid
        self.volume = volume
    }
}

/// 默认实现：保持向后兼容（实现方可选择不实现 onError）
public extension SyRtcEventHandler {
    func onError(code: Int, message: String) {}
    func onStreamMessage(uid: String, streamId: Int, data: Data) {}
    func onStreamMessageError(uid: String, streamId: Int, code: Int, missed: Int, cached: Int) {}
    func onChannelMessage(uid: String, message: String) {}
}

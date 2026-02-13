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
}

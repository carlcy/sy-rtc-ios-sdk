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


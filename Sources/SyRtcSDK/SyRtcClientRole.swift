import Foundation

/// 客户端角色（对齐控制面 Token role：host|audience|publisher|subscriber）
public enum SyRtcClientRole {
    case host
    case audience
    case publisher
    case subscriber

    public var canPublish: Bool {
        switch self {
        case .host, .publisher: return true
        case .audience, .subscriber: return false
        }
    }

    public var apiRole: String {
        switch self {
        case .host: return "host"
        case .audience: return "audience"
        case .publisher: return "publisher"
        case .subscriber: return "subscriber"
        }
    }

    public static func fromApi(_ role: String?) -> SyRtcClientRole {
        switch role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "host": return .host
        case "publisher": return .publisher
        case "subscriber": return .subscriber
        default: return .audience
        }
    }
}

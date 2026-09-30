import Foundation

/// 控制面业务错误。`fetchToken` / `renewToken` 在 HTTP 4xx 时仍会读取 JSON 里的 `code`。
///
/// - 4031 凭证已停用
/// - 4032 凭证已吊销
/// - 4033 凭证已过期
public enum SyRtcServiceError: LocalizedError, Equatable {
    case credentialSuspended(detail: String)
    case credentialRevoked(detail: String)
    case credentialExpired(detail: String)
    case business(code: Int, message: String)
    case invalidRequest
    case noData
    case parseError
    case httpError(statusCode: Int, message: String)

    public var businessCode: Int? {
        switch self {
        case .credentialSuspended: return 4031
        case .credentialRevoked: return 4032
        case .credentialExpired: return 4033
        case .business(let code, _): return code
        case .httpError(let status, _): return status
        case .invalidRequest, .noData, .parseError: return nil
        }
    }

    /// 把控制面 `code` 转成可展示的错误。4031/4032/4033 使用固定中文说明，并附上服务端 `msg`（若有）。
    public static func make(code: Int, serverMessage: String?, fallback: String) -> SyRtcServiceError {
        let server = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        func compose(_ base: String) -> String {
            if server.isEmpty || server == base { return base }
            return "\(base)（\(server)）"
        }
        switch code {
        case 4031:
            return .credentialSuspended(detail: compose("凭证已停用，请到控制台检查应用或账号状态"))
        case 4032:
            return .credentialRevoked(detail: compose("凭证已吊销，请重新申请 AppSecret 或重新登录"))
        case 4033:
            return .credentialExpired(detail: compose("凭证已过期，请重新登录或刷新凭证后再获取 Token"))
        default:
            return .business(code: code, message: server.isEmpty ? fallback : server)
        }
    }

    public static func codeValue(_ value: Any?) -> Int? {
        switch value {
        case let code as Int:
            return code
        case let code as NSNumber:
            return code.intValue
        case let code as String:
            return Int(code.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .credentialSuspended(let detail), .credentialRevoked(let detail), .credentialExpired(let detail):
            return detail
        case .business(let code, let message):
            return "业务错误 \(code): \(message)"
        case .invalidRequest:
            return "请求地址无效"
        case .noData:
            return "没有收到数据"
        case .parseError:
            return "响应解析失败"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        }
    }
}

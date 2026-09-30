import Foundation

/// 控制面画质档位，与 Token 参数 `qualityTier` 以及 `POST /api/rtc/quality/switch` 一致。
///
/// - audio: 纯音频
/// - sd: 标清
/// - hd: 高清
/// - fhd: 全高清
public enum SyRtcQualityTier: String, CaseIterable {
    case audio
    case sd
    case hd
    case fhd

    /// 将后台或业务传入的字符串规范成档位；无法识别时返回 nil。
    public static func parse(_ raw: String) -> SyRtcQualityTier? {
        SyRtcQualityTier(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

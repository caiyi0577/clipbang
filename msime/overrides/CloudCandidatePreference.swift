import Foundation

/// 定制版云候选恒开，端点固定 Google 输入工具。
///
/// 源码确认唯一构造点：`crates/client-core/src/cloud/candidates.rs` 的
/// `build_google_url` → `https://inputtools.google.com/request?text=<拼音串>&itc=zh-t-i0-pinyin`。
/// 设置页不再提供开关，App Group 里旧版本存过的值一律忽略；共享偏好文档由
/// `MetasequoiaInputSessionBridge` 用这里的恒值覆盖，桌面同步来的文档也关不掉它。
///
/// 请求仍需键盘的「允许完全访问」（iOS 系统限制），且只发当前组字的拼音串，
/// 不发已上屏内容、词库、剪贴板或历史。
enum CloudCandidatePreference {
  static let key = "candidate.cloudCandidates"

  static var defaults: UserDefaults {
    InputSchemePreference.appGroupDefaults
  }

  static var enabled: Bool {
    get { true }
    set { /* 恒开：setter 保留给既有调用点，但不落盘、不改变行为 */ }
  }
}

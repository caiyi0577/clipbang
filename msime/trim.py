#!/usr/bin/env python3
"""MSIME 定制裁剪层。

CI 从固定 SHA 拉取上游 ``metasequoiaime/msime`` 作为不变的底座，然后在编译前
执行本脚本，把「不需要的功能」从源码里裁掉。定制代码全部留在本仓库，后续每
一轮裁剪只改这里和 ``overrides/``，push 即触发重新出包。

用法::

    python3 trim.py <msime-source-root>

第一轮：语言与方案 —— 只保留「全拼 26 键」和「手写」。

为什么不物理删除 ``ChineseInputScheme`` 的 case：
    这个枚举与 Rust host-api 的 ``TouchKeyboardScheme::ALL`` 一一对应，
    ``sharedIdentifier`` / ``engineScheme`` / ``cloudSchema`` / ``title`` 都是
    穷尽 switch，500+ 个 Swift 文件引用它。删 case 会让全项目编译崩掉，
    还会让共享偏好文档里的 identifier 映射错位。正确做法是在唯一的开关
    ``isOfferedByEdition`` 上收敛：设置页语言行、启用列表、引导页、键盘方案
    面板、写进共享文档交给引擎的 enabled 列表全都经过它。

为什么不动 ``shared/contracts/editions.json``：
    它被 ``crates/client-core/src/edition.rs`` 用 ``include_str!`` 编译进
    Rust，``install_resources`` / ``verify_resources`` 按它决定随包资源清单，
    改它会牵动整个资源校验链；而 iOS 运行时根本不读它（``MSIMEAppEdition``
    从 Info.plist 读版本，full 不带键）。语言与方案的可见集合由 Swift 决定。
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OVERRIDES = HERE / "overrides"

IOS = "platforms/ios"
PREF = f"{IOS}/SharedUI/preferences/InputSchemePreference.swift"
LANGUAGE = f"{IOS}/App/Sources/settings/InputLanguage.swift"
WELCOME = f"{IOS}/App/Sources/app/WelcomeFlowView.swift"
LANGUAGE_TESTS = f"{IOS}/KeyboardTests/settings/InputLanguageTests.swift"
VOICE_PRESETS = f"{IOS}/App/Sources/settings/FeatureSettingsViews.swift"
CLOUD_CANDIDATE_PREF = f"{IOS}/SharedUI/candidate/CloudCandidatePreference.swift"
CANDIDATE_OPTIONS = f"{IOS}/App/Sources/settings/CandidateOptionsSettingsView.swift"
ONBOARDING = f"{IOS}/App/Sources/app/OnboardingView.swift"
KEYBOARD_VC = f"{IOS}/KeyboardExtension/Sources/keyboard/KeyboardViewController.swift"
KEYBOARD_LAYOUT_VIEW = f"{IOS}/App/Sources/keyboard/KeyboardLayoutSettingsView.swift"
KEYBOARD_LAYOUT_PREF = f"{IOS}/SharedUI/preferences/KeyboardLayoutPreference.swift"
PLUGIN_DETAIL = f"{IOS}/App/Sources/plugins/PluginDetailView.swift"
RUST_OPTIONS = "crates/engine/src/host/options.rs"
TRANSLATION_PREF = f"{IOS}/SharedUI/candidate/TranslationProviderPreference.swift"
TRANSLATION_STORE = f"{IOS}/KeyboardExtension/Sources/candidate/CandidateTranslationStore.swift"
TRANSLATION_SETTINGS = f"{IOS}/App/Sources/settings/TranslationProviderSettingsView.swift"
GLOSS_CARD = f"{IOS}/KeyboardExtension/Sources/candidate/CandidateGlossCard.swift"
SYS_TRANSLATION = f"{IOS}/KeyboardExtension/Sources/candidate/SystemCandidateTranslationService.swift"
RUST_PREFS = "crates/client-core/src/preferences.rs"


def source_root() -> Path:
    if len(sys.argv) < 2:
        raise SystemExit("usage: trim.py <msime-source-root>")
    root = Path(sys.argv[1]).resolve()
    if not (root / IOS / "project.yml").is_file():
        raise SystemExit(f"not an MSIME source root: {root}")
    return root


def read(root: Path, rel: str) -> str:
    return (root / rel).read_text(encoding="utf-8")


def write(root: Path, rel: str, text: str) -> None:
    (root / rel).write_text(text, encoding="utf-8")


def replace_once(root: Path, rel: str, old: str, new: str, label: str) -> None:
    """精确替换一处；上游一变就立刻报错，绝不悄悄漏裁。"""
    text = read(root, rel)
    hits = text.count(old)
    if hits != 1:
        raise SystemExit(f"[FAIL] {label}: expected 1 match in {rel}, found {hits}")
    write(root, rel, text.replace(old, new))
    print(f"[patch] {label} -> {rel}", flush=True)


def overlay(root: Path, rel: str, name: str, label: str) -> None:
    """用本仓库的完整文件覆盖上游同名文件。"""
    src = OVERRIDES / name
    if not src.is_file():
        raise SystemExit(f"[FAIL] missing override: {src}")
    write(root, rel, src.read_text(encoding="utf-8"))
    print(f"[override] {label} -> {rel}", flush=True)


# ---------------------------------------------------------------------------
# R1：唯一的方案总开关。所有入口、启用列表、引导页、共享文档都经过这里。
# ---------------------------------------------------------------------------
OFFERED_COMMENT_OLD = "  /// 本版本是否提供这个入口：入口背后的方案在本版本里时提供。手写面板写出的是汉字，所以只在提供中文方案的版本里有（full、拼音版、五笔版），日文、越南文和藏文版没有。与 client-core 的 `Edition::offers_touch_scheme` 一致。\n"

OFFERED_OLD = """  var isOfferedByEdition: Bool {
    guard self == .handwriting else { return MSIMEAppEdition.offers(engineScheme) }
    return Self.chineseEngineSchemes.contains(where: MSIMEAppEdition.offers)
  }"""

OFFERED_NEW = """  /// 定制版只提供「全拼」与「手写」。
  ///
  /// 全拼的 26 键、9 键、14 键、18 键都是全拼自己的布局，全部保留；双拼（含九键双拼、
  /// 粤语双拼）、五笔、注音、笔画、粤拼、日语、韩语、越南语、藏文一律不提供。
  /// 设置页语言行、启用列表、引导页方案卡、键盘「输入方式」面板以及写进共享文档
  /// 交给 host-api 的 `touch_keyboard_schemes.enabled` 都经过这里。
  /// 枚举 case 本身保留：它与 Rust `TouchKeyboardScheme::ALL` 一一对应，删 case 会让
  /// 全项目的穷尽 switch 失配，也会破坏共享偏好文档的 identifier 映射。
  var isOfferedByEdition: Bool {
    switch self {
    case .quanpin, .nineKey, .fourteenKey, .eighteenKey, .handwriting: true
    default: false
    }
  }"""

# ---------------------------------------------------------------------------
# R2：引导页不再宣称有 9 键 / 双拼 / 五笔，并把「手写」补成可选卡片。
# ---------------------------------------------------------------------------
CHOICES_OLD = """  private static let schemeChoices: [(scheme: ChineseInputScheme, title: String, detail: String)] = [
    (.quanpin, "全拼 26 键", "最常用，完整拼音"),
    (.nineKey, "全拼 9 键", "单手更顺手"),
    (.shuangpin, "双拼", "每字两键 · 默认小鹤"),
    (.wubi, "五笔", "形码 · 默认 86 版"),
  ].filter { $0.scheme.isOfferedByEdition }"""

CHOICES_NEW = """  /// 定制版引导页只提供全拼（26 / 9 键）与手写。
  private static let schemeChoices: [(scheme: ChineseInputScheme, title: String, detail: String)] = [
    (.quanpin, "全拼 26 键", "最常用，完整拼音"),
    (.nineKey, "全拼 9 键", "单手更顺手"),
    (.handwriting, "手写", "直接写，不认识的字也能打"),
  ].filter { $0.scheme.isOfferedByEdition }"""

BODY_OLD = """  private static var schemeStepBody: String {
    if MSIMEAppEdition.isFull { return "全拼、9 键、双拼和五笔用的是同一套引擎，词库和自造词通用。" }
    if schemeChoices.count > 1 {
      return schemeChoices.map(\\.title).joined(separator: "、") + "用的是同一套引擎，词库和自造词通用。"
    }
    return "之后可以在设置里调整方案的细项。"
  }"""

BODY_NEW = """  /// 定制版只提供全拼与手写，引导页不再宣称有 9 键、双拼或五笔。
  private static var schemeStepBody: String {
    return "全拼与手写共用同一套引擎，词库和自造词通用。"
  }"""

# 上游在方案卡/文案上方留的两行注释，描述的都是已删掉的多方案版本表。
STALE_COMMENT_CHOICES = "  /// 只列本版本提供的入口：五笔版只剩五笔，拼音版没有五笔。五笔这一行的副标题写正在用的码表，画的时候按 `wubiProfile` 换掉这里的 86 版。\n"
STALE_COMMENT_BODY = "  /// full 的说法不变；其他版本只说本版本提供的入口。\n"


# ---------------------------------------------------------------------------
# 第二轮：语音去云端 / 云联想恒开 / 云剪贴板改本地 / 翻译走离线释义
# ---------------------------------------------------------------------------
# 语音出厂默认已是 local（preferences.rs 的 Default），只需把设置页服务商列表
# 收敛到设备端，杜绝误开云端。case 保留以兼容已存配置与 Rust provider 目录。
VOICE_OLD = "    return VoiceProviderPreset.allCases.map { provider in"
VOICE_NEW = (
    "    // 定制版只提供设备端识别：云端 provider 的 case 保留以兼容已存配置与 Rust 目录，\n"
    "    // 但设置页服务商列表只列 local/system，录音不会离开设备。\n"
    "    return VoiceProviderPreset.allCases.filter(\\.isOnDevice).map { provider in"
)

CLOUD_DECL_OLD = """  @AppStorage(CloudCandidatePreference.key, store: CloudCandidatePreference.defaults)
  private var cloudCandidates = false
"""

CLOUD_TOGGLE_OLD = """          // 副标题就是隐私说明：只有打开这个开关，输入的编码才会离开设备。
          DesignToggleRow(title: "云候选", info: "仅将当前拼写发送给 \\(cloudRecipient)，不发送已上屏内容、词库或历史；需允许完全访问",
                          isOn: $cloudCandidates)
            .accessibilityIdentifier("cloudCandidates")
          DesignDivider()
"""
CLOUD_TOGGLE_NEW = """          // 定制版云候选恒开（Google 输入工具），设置页不再提供开关。
          EmptyView()
"""

CLIPBOARD_CLOUD_OLD = """    let cloud = privacyGate.allows(.cloudClipboard) ? KeyboardCloudClipboard(hasFullAccess: hasFullAccess) : nil
    cloud?.fieldAllowsCloud = { [weak self] in self?.privacyGate.allows(.cloudClipboard) ?? false }
"""
CLIPBOARD_CLOUD_NEW = """    // 定制版云剪贴板已移除：键盘只显示本机剪贴板历史，不构造云端面板、不发任何云请求。
    let cloud: KeyboardCloudClipboard? = nil
"""

RUST_CLIPBOARD_OLD = """            clipboard_history: false,
            clipboard_history_limit: default_clipboard_history_limit(),"""
RUST_CLIPBOARD_NEW = """            clipboard_history: true,
            clipboard_history_limit: default_clipboard_history_limit(),"""

RUST_GLOSS_OLD = """            candidate_translations: false,
            candidate_translation_scope: CandidateTranslationScope::Highlighted,
            candidate_english_gloss: false,"""
RUST_GLOSS_NEW = """            candidate_translations: false,
            candidate_translation_scope: CandidateTranslationScope::Highlighted,
            candidate_english_gloss: true,"""

# ---------------------------------------------------------------------------
# 第四轮：彻底移除辅助码（用户明确表示从来没用过、整个功能删掉）
#
# 五道门同时关：设置页整组不渲染、Shift 开关不显示、偏好恒 false（⇧ 固定变
# 「分词」）、插件页不再有入口、引擎 helpcode/show_helpcode 默认 false。
# helpcodes/ 下 7 张静态码表仍随包：它们由 stage-resources.sh 与引擎资源校验链
# 固定打包，删文件会破坏 verify_resources；但引擎已不加载、界面也看不到。
# ---------------------------------------------------------------------------
HELPCODE_GROUP_OLD = """        chineseGroup
        helpcodeGroup
        translationGroup"""
HELPCODE_GROUP_NEW = """        chineseGroup
        translationGroup"""

SHIFT_TOGGLE_OLD = """      DesignToggleRow(title: "组字时保留 Shift", info: "全拼 26 键组字时左下角保留 ⇧，点一下再输字母即辅助码；默认开启，关闭后这一键改为「分词」，用来断开音节",
                      isOn: Binding(get: { quanpinShift }, set: { saveQuanpinShift($0) }))
        .accessibilityIdentifier("appQuanpinShiftToggle")
"""

SHIFT_PREF_OLD = """  static func sharedQuanpinShift(in preferences: [String: Any]?) -> Bool {
    preferences?[quanpinShiftDocumentKey] as? Bool ?? true
  }

  static var quanpinShift: Bool {
    get { defaults.object(forKey: quanpinShiftKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: quanpinShiftKey) }
  }"""
SHIFT_PREF_NEW = """  /// 辅助码已整体移除：共享文档与 App Group 旧值一律忽略，⇧ 固定为「分词」键。
  static func sharedQuanpinShift(in preferences: [String: Any]?) -> Bool { false }

  static var quanpinShift: Bool {
    get { false }
    set { /* 恒关：辅助码已移除 */ }
  }"""

PLUGIN_LINK_OLD = """      NavigationLink("前往辅助码设置") { HelpcodeSettingsView() }
"""

RUST_HELPCODE_OLD = """        helpcode: true,
        strict_quanpin_helpcode: false,
        show_helpcode: true,"""
RUST_HELPCODE_NEW = """        helpcode: false,
        strict_quanpin_helpcode: false,
        show_helpcode: false,"""

# ---------------------------------------------------------------------------
# 第五轮：候选释义改走 Apple 设备端系统翻译（用户选定）
#
# 内置 msime-english.db 的 zh_en_glosses 只有 18,474 条、单字仅 2 条（「牛」没有），
# 且由英文维基词典反向对齐而来，质量很差。改接 Translation.framework 的
# TranslationSession（iOS 26+）：翻译全在设备端，Apple 只收 bundle ID 与语言对。
# 前提：系统「设置 → 翻译」里已下载简体中文和目标语言；没装时安静返回空结果，
# 由候选栏回退到随包离线释义（仍需 candidate_english_gloss = true 作为显示总开关）。
# ---------------------------------------------------------------------------
SYS_PROVIDER_CASE_OLD = "  case off, account, niutrans, tencent, custom, ai"
SYS_PROVIDER_CASE_NEW = "  case off, account, niutrans, tencent, custom, ai, system"

SYS_PROVIDER_TITLE_OLD = """    case .custom: "自定义接口（DeepLX 或 DeepL API）"
    case .ai: "AI 辅助"
    }"""
SYS_PROVIDER_TITLE_NEW = """    case .custom: "自定义接口（DeepLX 或 DeepL API）"
    case .ai: "AI 辅助"
    case .system: "系统翻译（设备端，推荐）"
    }"""

SYS_ROUTE_CASE_OLD = """  case ai(provider: String, endpoint: String, model: String, token: String)
  /// Nothing was chosen"""
SYS_ROUTE_CASE_NEW = """  case ai(provider: String, endpoint: String, model: String, token: String)
  case system
  /// Nothing was chosen"""

SYS_ROUTE_PROVIDER_OLD = "    case .ai: .ai\n    case .none: nil"
SYS_ROUTE_PROVIDER_NEW = "    case .ai: .ai\n    case .system: .system\n    case .none: nil"

SYS_ROUTE_SCOPE_OLD = '    case .none: "none"'
SYS_ROUTE_SCOPE_NEW = '    case .system: "system-apple"\n    case .none: "none"'

SYS_CLIENT_SWITCH_OLD = "    case .account, .none:\n      break"
SYS_CLIENT_SWITCH_NEW = "    case .account, .none, .system:\n      break"

SYS_PREFERRED_GLOSS_OLD = "    case .niutrans, .tencent, .custom, .ai: return online ?? offline"
SYS_PREFERRED_GLOSS_NEW = "    case .niutrans, .tencent, .custom, .ai, .system: return online ?? offline"

SYS_ROUTE_IN_OLD = """  static func route(in preferences: [String: Any]?) -> TranslationRoute {
    let niutrans = """
SYS_ROUTE_IN_NEW = """  static func route(in preferences: [String: Any]?) -> TranslationRoute {
    // 定制版：iOS 26+ 一律走 Apple 设备端系统翻译，不再读取任何在线服务配置。
    if #available(iOS 26.0, *) { return .system }
    let niutrans = """

SYS_CARD_SOURCE_OLD = "    case offline, account, tencent, niutrans, custom, ai"
SYS_CARD_SOURCE_NEW = "    case offline, account, tencent, niutrans, custom, ai, system"

SYS_CARD_INIT_OLD = "      case .ai: self = .ai\n      case .none: return nil"
SYS_CARD_INIT_NEW = "      case .ai: self = .ai\n      case .system: self = .system\n      case .none: return nil"

SYS_CARD_TITLE_OLD = """      case .ai: "AI 辅助"
      }"""
SYS_CARD_TITLE_NEW = """      case .ai: "AI 辅助"
      case .system: "系统翻译"
      }"""

SYS_STORE_INIT_OLD = """  init(service: any CandidateTranslationService = ProviderCandidateTranslationService(route: .none), scope: String = "none",
       cacheLimit: Int = 2_000) {
    self.service = service
    self.scope = scope
    self.cacheLimit = cacheLimit
  }"""
SYS_STORE_INIT_NEW = """  init(service: (any CandidateTranslationService)? = nil, scope: String = "system-apple",
       cacheLimit: Int = 2_000) {
    if let service {
      self.service = service
    } else if #available(iOS 26.0, *) {
      self.service = SystemCandidateTranslationService()
    } else {
      self.service = ProviderCandidateTranslationService(route: .none)
    }
    self.scope = scope
    self.cacheLimit = cacheLimit
  }"""

SYS_APPLY_ROUTE_OLD = """    translations.use(route == .account ? BackendCandidateTranslationService() : ProviderCandidateTranslationService(route: route),
                     scope: scope)"""
SYS_APPLY_ROUTE_NEW = """    // 定制版：候选释义一律由 Apple 设备端系统翻译提供，不发任何网络请求。
    if #available(iOS 26.0, *) {
      translations.use(SystemCandidateTranslationService(), scope: "system-apple")
    } else {
      // 低版本没有设备端系统翻译，直接不发任何翻译请求。
      translations.use(ProviderCandidateTranslationService(route: .none), scope: "none")
    }"""

SYS_SETTINGS_SWITCH_OLD = "      case .off, .account:\n        EmptyView()"
SYS_SETTINGS_SWITCH_NEW = "      case .off, .account, .system:\n        EmptyView()"

SYS_SETTINGS_INFO_OLD = '    case .off: return "键盘不会把候选词发给任何在线服务；英文释义仍来自离线词库。\\n\\n" + general'
SYS_SETTINGS_INFO_NEW = '    case .off, .system: return "候选词由 iOS 系统翻译在这台设备上翻译，原文和译文都不离开设备。需先在「设置 → 翻译」下载简体中文与目标语言。\\n\\n" + general'

# 设置页要用 TranslationSession 做「测试」，必须 import Translation（键盘扩展那份有自己的 import）。
SYS_SETTINGS_IMPORT_OLD = "import SwiftUI\n\n/// 「翻译服务」: which service fills candidate glosses"
SYS_SETTINGS_IMPORT_NEW = "import SwiftUI\nimport Translation\n\n/// 「翻译服务」: which service fills candidate glosses"

SYS_RUST_DEFAULTS_OLD = """            candidate_translations: false,
            candidate_translation_scope: CandidateTranslationScope::Highlighted,
            candidate_english_gloss: true,"""
SYS_RUST_DEFAULTS_NEW = """            candidate_translations: true,
            candidate_translation_scope: CandidateTranslationScope::Highlighted,
            candidate_english_gloss: true,"""

# 设置页「测试」按钮仍走旧的 HTTP 探针（TranslationProviderClient），而 system 路由
# 在客户端 switch 里是空操作，必然报「测试失败：请检查凭据、地址与网络」。
# 改成直接调用系统翻译，失败时给出「去系统设置下载语言包」的明确指引。
SYS_TEST_OLD = """  private func test() {
    var document: [String: Any] = [:]
    write(into: &document)
    let route = TranslationProviderPreference.route(in: document)
    guard route != .none, route != .account else { status = "凭据不完整。"; return }
    testing = true
    status = nil
    let id = testGeneration.begin()
    operation = Task {
      let result = await TranslationProviderClient().translate(words: ["你好"], target: "EN", route: route)
      guard testGeneration.isCurrent(id) else { return }
      testing = false
      operation = nil
      if let gloss = result.first ?? nil {
        status = "测试成功：你好 → \\(gloss)"
      } else {
        status = "测试失败：请检查凭据、地址与网络。"
      }
    }
  }"""
SYS_TEST_NEW = """  private func test() {
    var document: [String: Any] = [:]
    write(into: &document)
    let route = TranslationProviderPreference.route(in: document)
    if #available(iOS 26.0, *) {
      // 定制版：候选释义走 Apple 设备端系统翻译，测试也不再发任何网络请求。
      // （翻译协议在键盘扩展 target，主 App 这里直接内联调用 TranslationSession。）
      testing = true
      status = nil
      let id = testGeneration.begin()
      operation = Task {
        do {
          let session = TranslationSession(
            installedSource: Locale.Language(identifier: "zh-Hans"),
            target: Locale.Language(identifier: "en-US"))
          let ready = await session.isReady
          guard ready, testGeneration.isCurrent(id) else {
            testing = false; operation = nil
            status = "测试失败：请先在「设置 → 翻译 → 已下载的语言」下载 简体中文 与 English"
            return
          }
          let response = try await session.translate("你好")
          guard testGeneration.isCurrent(id) else { return }
          testing = false
          operation = nil
          status = "测试成功：你好 → \\(response.targetText)"
        } catch {
          guard testGeneration.isCurrent(id) else { return }
          testing = false
          operation = nil
          status = "测试失败：请先在「设置 → 翻译 → 已下载的语言」下载 简体中文 与 English"
        }
      }
      return
    }
    guard route != .none, route != .account else { status = "凭据不完整。"; return }
    testing = true
    status = nil
    let id = testGeneration.begin()
    operation = Task {
      let result = await TranslationProviderClient().translate(words: ["你好"], target: "EN", route: route)
      guard testGeneration.isCurrent(id) else { return }
      testing = false
      operation = nil
      if let gloss = result.first ?? nil {
        status = "测试成功：你好 → \\(gloss)"
      } else {
        status = "测试失败：请检查凭据、地址与网络。"
      }
    }
  }"""


# ---------------------------------------------------------------------------
# iOS 化：App 界面回归系统观感。只改设计 token 的内部实现（API 不变），
# 30 个使用 DesignKit 的页面自动生效。
#
# 键盘走的是另一条取色链路：KeyboardTheme → client-services 解析出的主题
# 目录 / AppThemePalette 季节 seed / Native·System·Season 三组 Swift 兜底
# token，完全不读 MetasequoiaTheme。下面 KB_* 规则按皮肤规则在源头统一品牌色：
# 只替换 accent / onAccent / candidateAccent / accentSoft 这些品牌槽位，
# 各皮肤自己的背景、按键、文字、分隔线公式保留；自定义皮肤 design 分支不动。
# ---------------------------------------------------------------------------
THEME_FILE = f"{IOS}/SharedUI/core/MetasequoiaTheme.swift"
DESIGN_KIT = f"{IOS}/App/Sources/app/DesignKit.swift"

UI_ACCENT_OLD = """  // 文字、图标、选中态和开关用的强调色：季节强调色，回退为经典 #2C7A4B / #5FBF84。
  static let accentUIColor = UIColor { traits in
    palette(traits)?.accent ?? forestUIColor.resolvedColor(with: traits)
  }"""
UI_ACCENT_NEW = """  // 文字、图标、选中态和开关用的强调色：固定品牌绿 #2C7A4B / #5FBF84。App 界面不再随季节换色（四季色只保留在键盘皮肤里）。
  static let accentUIColor = forestUIColor"""

UI_ACCENT_SOFT_OLD = """  static let accentSoft = Color(uiColor: UIColor { traits in
    if let palette = palette(traits) { return palette.accentSoft }
    return traits.userInterfaceStyle == .dark"""
UI_ACCENT_SOFT_NEW = """  static let accentSoft = Color(uiColor: UIColor { traits in
    return traits.userInterfaceStyle == .dark"""

UI_ON_ACCENT_OLD = """  static let onAccent = Color(uiColor: UIColor { traits in
    palette(traits)?.onAccent ?? onForestUIColor.resolvedColor(with: traits)
  })"""
UI_ON_ACCENT_NEW = """  static let onAccent = Color(uiColor: onForestUIColor)"""

UI_ACCENT_SYS_OLD = """  // 文字、图标、选中态和开关用的强调色：固定品牌绿 #2C7A4B / #5FBF84。App 界面不再随季节换色（四季色只保留在键盘皮肤里）。
  static let accentUIColor = forestUIColor"""
UI_ACCENT_SYS_NEW = """  // 文字、图标、选中态和开关用的强调色：iOS 系统强调色（systemBlue #007AFF / #0A84FF）。
  static let accentUIColor = UIColor.systemBlue"""

UI_ON_ACCENT_SYS_OLD = """  static let onAccent = Color(uiColor: onForestUIColor)"""
UI_ON_ACCENT_SYS_NEW = """  // systemBlue 填充上的文字：两种模式都是白色（Apple 自家蓝色按钮的标准做法）。
  static let onAccent = Color.white"""

UI_ACCENT_SOFT_SYS_OLD = """  static let accentSoft = Color(uiColor: UIColor { traits in
    return traits.userInterfaceStyle == .dark
      ? UIColor(red: 95 / 255, green: 191 / 255, blue: 132 / 255, alpha: 0.26)
      : UIColor(red: 44 / 255, green: 122 / 255, blue: 75 / 255, alpha: 0.14)
  })"""
UI_ACCENT_SOFT_SYS_NEW = """  static let accentSoft = Color(uiColor: UIColor { traits in
    UIColor.systemBlue
      .resolvedColor(with: traits)
      .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.26 : 0.14)
  })"""

UI_FOREST_COMMENT_OLD = """  // 经典品牌强调色 #2C7A4B / #5FBF84：应用主题解析不出时作为 `accentUIColor` 的回退，也用在需要固定品牌绿的地方。"""
UI_FOREST_COMMENT_NEW = """  // 经典品牌强调色 #2C7A4B / #5FBF84：用于键盘原生皮肤、标志等固定品牌绿的地方（App 界面强调色已改用系统蓝）。"""

UI_CANVAS_OLD = """  // 页面背景：季节 bg；经典值 #F2F2F7 / #000。
  static let canvasUIColor = UIColor { traits in
    if let palette = palette(traits) { return palette.background }
    return traits.userInterfaceStyle == .dark ? .black : UIColor(red: 242 / 255, green: 242 / 255, blue: 247 / 255, alpha: 1)
  }"""
UI_CANVAS_NEW = """  // 页面背景：iOS 系统分组背景（浅色 #F2F2F7，深色 #000）。
  static let canvasUIColor = UIColor.systemGroupedBackground"""

UI_SURFACE_OLD = """  // 卡片和行背景：季节 card；经典值 #FFF / #1C1C1E。
  static let surfaceUIColor = UIColor { traits in
    if let palette = palette(traits) { return palette.card }
    return traits.userInterfaceStyle == .dark ? UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1) : .white
  }"""
UI_SURFACE_NEW = """  // 卡片和行背景：iOS 系统二级分组背景（浅色白，深色 #1C1C1E）。
  static let surfaceUIColor = UIColor.secondarySystemGroupedBackground"""

UI_HAIR_OLD = """  // 细线和分隔线：浅色下用季节 hair（经典：系统分隔线色）；深色下固定为 rgba(84,84,88,.6)，按 iOS 设计稿覆盖 Rust 的深色 hair。
  static let hairUIColor = UIColor { traits in
    if traits.userInterfaceStyle == .dark { return UIColor(red: 84 / 255, green: 84 / 255, blue: 88 / 255, alpha: 0.6) }
    return palette(traits)?.hair ?? UIColor.separator.resolvedColor(with: traits)
  }"""
UI_HAIR_NEW = """  // 细线和分隔线：iOS 系统分隔线色。
  static let hairUIColor = UIColor.separator"""

UI_SUB_OLD = """  // 次要文字、数值和箭头：#8A8A8E / #8E8E93。
  static let subUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
      : UIColor(red: 138 / 255, green: 138 / 255, blue: 142 / 255, alpha: 1)
  }"""
UI_SUB_NEW = """  // 次要文字、数值和箭头：iOS 系统次要标签色。
  static let subUIColor = UIColor.secondaryLabel"""

UI_RADIUS_OLD = """  // 设置标签页上分组卡片的圆角。
  static let cardRadius: CGFloat = 26"""
UI_RADIUS_NEW = """  // 设置标签页上分组卡片的圆角：iOS 分组列表的 10pt（原为 Material 风格的 26pt）。
  static let cardRadius: CGFloat = 10"""

UI_PALETTE_FN_OLD = """  private static func palette(_ traits: UITraitCollection) -> AppThemePalette.Resolved? {
    AppThemePalette.resolved(dark: traits.userInterfaceStyle == .dark)
  }

  static let needle"""
UI_PALETTE_FN_NEW = """  static let needle"""

UI_SUBTEXT_OLD = """  func designSubtext() -> some View {
    font(.system(size: 13)).foregroundStyle(MetasequoiaTheme.sub)
  }"""
UI_SUBTEXT_NEW = """  func designSubtext() -> some View {
    font(.footnote).foregroundStyle(MetasequoiaTheme.sub)
  }"""

UI_ROW_METRICS_OLD = """    .padding(.vertical, 8)
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .contentShape(Rectangle())"""
UI_ROW_METRICS_NEW = """    .padding(.vertical, 8)
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())"""

UI_TOGGLE_ON_OLD = """      .tint(MetasequoiaTheme.switchOn)
      .padding(.vertical, 8)
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)"""
UI_TOGGLE_ON_NEW = """      .tint(MetasequoiaTheme.switchOn)
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)"""

UI_TOGGLE_OFF_OLD = """      .opacity(Self.disabledOpacity)
      .padding(.vertical, 8)
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)"""
UI_TOGGLE_OFF_NEW = """      .opacity(Self.disabledOpacity)
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)"""

UI_GROUP_TITLE_OLD = """          Text(title).font(.system(size: 13)).foregroundStyle(MetasequoiaTheme.groupTitle)
            .accessibilityAddTraits(.isHeader)
          if let info { DesignInfoTip(text: info, subject: title) }
        }
        .padding(.horizontal, 20)"""
UI_GROUP_TITLE_NEW = """          Text(title).font(.footnote).foregroundStyle(MetasequoiaTheme.groupTitle)
            .accessibilityAddTraits(.isHeader)
          if let info { DesignInfoTip(text: info, subject: title) }
        }
        .padding(.horizontal, 16)"""

UI_GROUP_FOOTER_OLD = """    Text(text).designSubtext()
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 20)"""
UI_GROUP_FOOTER_NEW = """    Text(text).designSubtext()
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 16)"""

UI_GROUP_HEADER_OLD = """    Text(title).font(.system(size: 13)).foregroundStyle(MetasequoiaTheme.groupTitle).textCase(nil)"""
UI_GROUP_HEADER_NEW = """    Text(title).font(.footnote).foregroundStyle(MetasequoiaTheme.groupTitle).textCase(nil)"""

UI_INFO_TITLE_FONT_OLD = """  var font: Font = .system(size: 17)"""
UI_INFO_TITLE_FONT_NEW = """  var font: Font = .body"""

UI_NAV_VALUE_OLD = """          Text(value).font(.system(size: 16)).foregroundStyle(MetasequoiaTheme.sub).lineLimit(1)"""
UI_NAV_VALUE_NEW = """          Text(value).font(.callout).foregroundStyle(MetasequoiaTheme.sub).lineLimit(1)"""

UI_VALUE_ROW_OLD = """      Text(value).font(.system(size: 16)).foregroundStyle(MetasequoiaTheme.sub).lineLimit(1)"""
UI_VALUE_ROW_NEW = """      Text(value).font(.callout).foregroundStyle(MetasequoiaTheme.sub).lineLimit(1)"""

UI_SELECT_VALUE_OLD = """        Text(valueTitle).font(.system(size: 16)).foregroundStyle(MetasequoiaTheme.sub).lineLimit(1)"""
UI_SELECT_VALUE_NEW = """        Text(valueTitle).font(.callout).foregroundStyle(MetasequoiaTheme.sub).lineLimit(1)"""

UI_INLINE_BTN_OLD = """          .font(.system(size: 13)).foregroundStyle(MetasequoiaTheme.accent)"""
UI_INLINE_BTN_NEW = """          .font(.footnote).foregroundStyle(MetasequoiaTheme.accent)"""

UI_CHEVRON_OLD = """  var fontSize: CGFloat = 13
  var opacity: Double = 0.55"""
UI_CHEVRON_NEW = """  var fontSize: CGFloat = 13
  var opacity: Double = 1"""

UI_EXT_LINK_OLD = """      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(MetasequoiaTheme.sub.opacity(0.55))"""
UI_EXT_LINK_NEW = """      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(MetasequoiaTheme.sub)"""


# ---------------------------------------------------------------------------
# 键盘皮肤品牌色：iOS 系统蓝。
#
# 取色链路（上游注释在 KeyboardTheme.swift 文件头）：
#   design（用户自定义皮肤，优先，不动）
#     > drawnPalette（Rust 主题目录解析出的 palette，或 SeasonKeyboardTokens 季节配色）
#     > native / 经典兜底（SystemKeyboardTokens / NativeKeyboardTokens）
#   CandidatePalette 在 followsDesktop 时还会用 Rust 的 candidate.accent 覆盖。
# 所以要在 drawnPalette 收口一处，再把三组兜底 token 与主题预览色同步改掉，
# 才能让 system / native / 内置主题 / 跟随系统 / 候选条都不留绿色。
# ---------------------------------------------------------------------------
KB_GLOBAL_THEME = f"{IOS}/SharedUI/core/GlobalTheme.swift"
KB_KEYBOARD_THEME = f"{IOS}/SharedUI/keyboard/KeyboardTheme.swift"
KB_CANDIDATE_PALETTE = f"{IOS}/SharedUI/candidate/CandidatePalette.swift"

KB_NATIVE_OLD = """  /// 品牌强调色：输入中的回车键、开启态磁贴和胶囊。候选条首选的字色另见 `candidateAccent`。
  static let accent = adaptiveColor(0x2C7A4B, 0x5FBF84)
  static let accentSoft = adaptiveColor(0x2C7A4B, 0x5FBF84, lightAlpha: 0.14, darkAlpha: 0.26)
  /// 触屏候选条首选的字色。浅色的 `accent` 画在键盘底色 `#D1D4DB` 上只有约 3.5:1，换成同一色相在 OKLCH 里降低明度的 `#15683B`（约 4.6:1，候选底片 `#FFFFFF` 上约 6.8:1）；深色不变。
  static let candidateAccent = adaptiveColor(0x15683B, 0x5FBF84)"""
KB_NATIVE_NEW = """  /// 键盘品牌强调色：与 App 界面同用 iOS 系统蓝（浅色 #007AFF / 深色 #0A84FF）。
  static let accent = UIColor.systemBlue
  static let accentSoft = UIColor { traits in
    UIColor.systemBlue.resolvedColor(with: traits)
      .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.26 : 0.14)
  }
  /// 候选条首选字色也用系统蓝；系统蓝在键盘底色上对比度足够，不再需要加深绿 `#15683B`。
  static let candidateAccent = UIColor.systemBlue"""

KB_SYSTEM_OLD = """  /// 原生皮肤以低饱和水杉绿强调回车、候选和激活状态，不跟季节。
  static let accent = adaptiveColor(0x32664B, 0x8AC4A2)
  /// 水杉绿填充上的文字：浅色用白色，深色用黑色。
  static let onAccent = adaptiveColor(0xFFFFFF, 0x000000)
  static let accentSoft = adaptiveColor(0x32664B, 0x8AC4A2, lightAlpha: 0.14, darkAlpha: 0.26)
  /// 工具栏 logo 的圆底：水杉绿混入系统卡片底，不跟季节。
  static let logoCircle = UIColor { traits in
    let dark = traits.userInterfaceStyle == .dark
    return AppThemePalette.mix(accent.resolvedColor(with: traits), dark ? 22 : 14, rgbColor(dark ? 0x1C1C1E : 0xFFFFFF))
  }
  /// 圆底里的 logo 图形使用深绿，保留白色折线描边的对比度。
  static let logoMark = UIColor { traits in
    AppThemePalette.mix(accent.resolvedColor(with: traits), traits.userInterfaceStyle == .dark ? 38 : 82, .black)
  }"""
KB_SYSTEM_NEW = """  /// 原生皮肤同样用 iOS 系统蓝强调回车、候选和激活状态，不跟季节。
  static let accent = UIColor.systemBlue
  /// 系统蓝填充上的文字：两种模式都用白色。
  static let onAccent = UIColor.white
  static let accentSoft = UIColor { traits in
    UIColor.systemBlue.resolvedColor(with: traits)
      .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.26 : 0.14)
  }
  /// 工具栏 logo 的圆底：系统蓝混入系统卡片底，不跟季节。
  static let logoCircle = UIColor { traits in
    let dark = traits.userInterfaceStyle == .dark
    return AppThemePalette.mix(accent.resolvedColor(with: traits), dark ? 22 : 14, rgbColor(dark ? 0x1C1C1E : 0xFFFFFF))
  }
  /// 圆底里的 logo 图形用系统蓝加深，保留白色折线描边的对比度。
  static let logoMark = UIColor { traits in
    AppThemePalette.mix(accent.resolvedColor(with: traits), traits.userInterfaceStyle == .dark ? 38 : 82, .black)
  }"""

KB_SEASON_PALETTE_OLD = """      accent: UIColor { traits in
        AppThemePalette.resolved(dark: traits.userInterfaceStyle == .dark)?.accent
          ?? NativeKeyboardTokens.accent.resolvedColor(with: traits)
      },
      // Rust 的 `on_accent`：浅色一般是白色，秋杉的银杏金上是深色；深色是 mix(accent 25%, #000)，因为白色压在深色模式偏浅的强调色上对比度不到 2:1。没有解析出季节时浅色白、深色黑。
      onAccent: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        return AppThemePalette.resolved(dark: dark)?.onAccent ?? (dark ? .black : .white)
      },
      // 首选候选用 Rust 给的 `candidate_accent`：浅色是加深到 AA 的强调色，深色就是强调色。
      candidateAccent: UIColor { traits in
        AppThemePalette.resolved(dark: traits.userInterfaceStyle == .dark)?.candidateAccent
          ?? NativeKeyboardTokens.candidateAccent.resolvedColor(with: traits)
      })"""
KB_SEASON_PALETTE_NEW = """      accent: UIColor.systemBlue,
      // 系统蓝填充上的文字统一白色，不再跟季节的 on_accent 走。
      onAccent: UIColor.white,
      // 候选首选字色也用系统蓝。
      candidateAccent: UIColor.systemBlue)"""

KB_SEASON_MIX_OLD = """      let accent = season.accent
      let made = dark"""
KB_SEASON_MIX_NEW = """      // 键盘底板与功能键的混色源也统一为系统蓝，四季绿不再渗进整套键盘。
      let accent = rgbColor(dark ? 0x0A84FF : 0x007AFF)
      let made = dark"""

KB_PREVIEW_OLD = """        guard let background = ThemeColor.parse(preview["background"]), let panel = ThemeColor.parse(preview["panel"]),
              let accent = ThemeColor.parse(preview["accent"]), let text = ThemeColor.parse(preview["text"]) else { return nil }
        return GlobalThemeEntry.Preview(background: background, panel: panel, accent: accent, text: text)"""
KB_PREVIEW_NEW = """        guard let background = ThemeColor.parse(preview["background"]), let panel = ThemeColor.parse(preview["panel"]),
              let text = ThemeColor.parse(preview["text"]) else { return nil }
        return GlobalThemeEntry.Preview(background: background, panel: panel, accent: UIColor.systemBlue, text: text)"""

KB_NATIVE_PALETTE_OLD = """  private static let nativePalette = ThemeKeyboardPalette(
    background: NativeKeyboardTokens.background, key: NativeKeyboardTokens.key, functionKey: NativeKeyboardTokens.functionKey,
    text: NativeKeyboardTokens.text, secondary: NativeKeyboardTokens.secondary, accent: NativeKeyboardTokens.accent,
    onAccent: UIColor { $0.userInterfaceStyle == .dark ? .black : .white },
    candidateAccent: NativeKeyboardTokens.candidateAccent)"""
KB_NATIVE_PALETTE_NEW = """  private static let nativePalette = ThemeKeyboardPalette(
    background: NativeKeyboardTokens.background, key: NativeKeyboardTokens.key, functionKey: NativeKeyboardTokens.functionKey,
    text: NativeKeyboardTokens.text, secondary: NativeKeyboardTokens.secondary, accent: UIColor.systemBlue,
    onAccent: UIColor.white,
    candidateAccent: UIColor.systemBlue)"""

KB_DRAWN_OLD = """  private var drawnPalette: ThemeKeyboardPalette? {
    guard let palette, let darkPalette else { return palette }
    func byMode(_ light: UIColor, _ dark: UIColor) -> UIColor {
      UIColor { traits in (traits.userInterfaceStyle == .dark ? dark : light).resolvedColor(with: traits) }
    }
    return ThemeKeyboardPalette(
      background: byMode(palette.background, darkPalette.background), key: byMode(palette.key, darkPalette.key),
      functionKey: byMode(palette.functionKey, darkPalette.functionKey), text: byMode(palette.text, darkPalette.text),
      secondary: byMode(palette.secondary, darkPalette.secondary), accent: byMode(palette.accent, darkPalette.accent),
      onAccent: byMode(palette.onAccent, darkPalette.onAccent),
      candidateAccent: byMode(palette.candidateAccent ?? palette.accent, darkPalette.candidateAccent ?? darkPalette.accent))
  }"""
KB_DRAWN_NEW = """  private var drawnPalette: ThemeKeyboardPalette? {
    guard let palette, let darkPalette else { return self.palette.map { Self.branded($0) } }
    func byMode(_ light: UIColor, _ dark: UIColor) -> UIColor {
      UIColor { traits in (traits.userInterfaceStyle == .dark ? dark : light).resolvedColor(with: traits) }
    }
    return Self.branded(ThemeKeyboardPalette(
      background: byMode(palette.background, darkPalette.background), key: byMode(palette.key, darkPalette.key),
      functionKey: byMode(palette.functionKey, darkPalette.functionKey), text: byMode(palette.text, darkPalette.text),
      secondary: byMode(palette.secondary, darkPalette.secondary), accent: byMode(palette.accent, darkPalette.accent),
      onAccent: byMode(palette.onAccent, darkPalette.onAccent),
      candidateAccent: byMode(palette.candidateAccent ?? palette.accent, darkPalette.candidateAccent ?? darkPalette.accent)))
  }

  /// 所有非自定义皮肤的键盘品牌色统一为 iOS 系统蓝，背景、按键、文字仍按各自皮肤绘制。
  /// 只替换 `drawnPalette` 的返回值：存储属性 `palette` 不变，`drawsNativeBackground`
  /// 与 `SeasonKeyboardTokens.palette` 的相等比较照旧；各 getter 里 `design` 分支优先，
  /// 用户自己设计的皮肤与候选皮肤包不受影响。
  private static func branded(_ palette: ThemeKeyboardPalette) -> ThemeKeyboardPalette {
    ThemeKeyboardPalette(
      background: palette.background, key: palette.key, functionKey: palette.functionKey,
      text: palette.text, secondary: palette.secondary, accent: UIColor.systemBlue,
      onAccent: UIColor.white, candidateAccent: UIColor.systemBlue)
  }"""

KB_ACTION_FG_OLD = """  var actionForeground: UIColor {
    if let design { return CustomKeyboardSkin.color(CustomKeyboardSkin.readableText(on: design.actionBackground)) }
    if let palette = drawnPalette { return palette.onAccent }
    if isNative { return SystemKeyboardTokens.onAccent }
    return UIColor { $0.userInterfaceStyle == .dark ? .black : .white }
  }"""
KB_ACTION_FG_NEW = """  var actionForeground: UIColor {
    if let design { return CustomKeyboardSkin.color(CustomKeyboardSkin.readableText(on: design.actionBackground)) }
    if let palette = drawnPalette { return palette.onAccent }
    if isNative { return SystemKeyboardTokens.onAccent }
    return UIColor.white
  }"""

KB_ON_ACCENT_OLD = """  var onAccent: UIColor {
    if let design { return CustomKeyboardSkin.color(CustomKeyboardSkin.readableText(on: design.accent)) }
    if let palette = drawnPalette { return palette.onAccent }
    if isNative { return SystemKeyboardTokens.onAccent }
    return UIColor { $0.userInterfaceStyle == .dark ? .black : .white }
  }"""
KB_ON_ACCENT_NEW = """  var onAccent: UIColor {
    if let design { return CustomKeyboardSkin.color(CustomKeyboardSkin.readableText(on: design.accent)) }
    if let palette = drawnPalette { return palette.onAccent }
    if isNative { return SystemKeyboardTokens.onAccent }
    return UIColor.white
  }"""

KB_CANDIDATE_ACCENT_OLD = """      accent: candidate?.accent ?? keyboard.accent,"""
KB_CANDIDATE_ACCENT_NEW = """      accent: keyboard.accent,"""


# ---------------------------------------------------------------------------
# 品牌改名与换标：水杉输入法 → ccboard。
#
# 名称全部写死在 iOS 侧（project.yml 的 INFOPLIST_KEY_CFBundleDisplayName、
# 键盘扩展 Info.plist、LaunchScreen.storyboard、约 100 个 Swift 文件里的 UI 文案），
# 不经 Rust：shared/contracts/editions.json 被 include_str! 编进资源校验链，不能动。
# CFBundleIdentifier / PRODUCT_NAME / 类名 / msime:// 等技术标识保持不变，否则会
# 破坏 App Group、签名和覆盖安装。
#
# logo 除了 Assets.xcassets 里 60 张 PNG，还有一份用代码画出来的旧标志
# （MSIMELogoShape.swift，绿边折线），工具栏/皮肤选择器/启动页都用它；
# 必须连绘图实现一起换，只覆盖 PNG 会留下旧图形。
# ---------------------------------------------------------------------------
BRAND_ASSETS = HERE / "assets"
LOGO_SHAPE = f"{IOS}/SharedUI/core/MSIMELogoShape.swift"
PROJECT_YML = f"{IOS}/project.yml"
EXT_PLIST = f"{IOS}/KeyboardExtension/Resources/Info.plist"

BRAND_TEXT_EXT = {
    ".swift", ".plist", ".storyboard", ".yml", ".pbxproj", ".md", ".py",
    ".json", ".strings", ".entitlements", ".xcconfig", ".svg", ".txt",
}
BRAND_REPLACEMENTS = [
    ("水杉输入法", "ccboard"),
    ("水杉", "ccboard"),
    ("METASEQUOIA IME", "CCBOARD"),
    ("© 2026 Metasequoia", "© 2026 ccboard"),
]


def iter_text_files(root: Path):
    for path in sorted((root / IOS).rglob("*")):
        if path.is_file() and path.suffix.lower() in BRAND_TEXT_EXT:
            yield path


def install_brand_assets(root: Path) -> None:
    """把本仓库 assets/ 下的全套新图标与 SVG 覆盖到上游同名路径。

    文件名与尺寸都和上游一致，Contents.json 的映射不用改。
    """
    if not BRAND_ASSETS.is_dir():
        raise SystemExit(f"[FAIL] 缺少品牌资源目录: {BRAND_ASSETS}")
    count = 0
    for src in sorted(BRAND_ASSETS.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(BRAND_ASSETS)
        dst = root / rel
        if not dst.is_file():
            raise SystemExit(f"[FAIL] 品牌资源目标不存在: {rel.as_posix()}")
        shutil.copy2(src, dst)
        count += 1
    print(f"[patch] R71 品牌图标资源覆盖 {count} 个文件", flush=True)


def rebrand(root: Path) -> None:
    """把所有用户可见的中文品牌文案改成 ccboard（技术标识不受影响）。"""
    files, hits = 0, 0
    for path in iter_text_files(root):
        try:
            with path.open("r", encoding="utf-8", newline="") as f:
                text = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        updated = text
        for old, new in BRAND_REPLACEMENTS:
            hits += updated.count(old)
            updated = updated.replace(old, new)
        if updated != text:
            with path.open("w", encoding="utf-8", newline="") as f:
                f.write(updated)
            files += 1
    print(f"[patch] R72 品牌文案 {files} 个文件 / {hits} 处替换", flush=True)
    if hits < 250:
        raise SystemExit(f"[FAIL] 品牌文案命中过少 ({hits})，上游结构可能变了")


def verify(root: Path) -> None:
    """把裁剪结果打进 CI 日志，便于事后核对这一轮到底生效了没有。"""
    offered = read(root, PREF)
    language = read(root, LANGUAGE)
    welcome = read(root, WELCOME)

    assert "case .quanpin, .nineKey, .fourteenKey, .eighteenKey, .handwriting: true" in offered
    assert "case quanpin, handwriting" in language
    assert "case .quanpin: [.quanpin, .fourteenKey, .eighteenKey, .nineKey]" in language
    for gone in ("shuangpin", "wubi", "zhuyin", "stroke", "cantonese",
                 "japanese", "korean", "vietnamese", "tibetan"):
        assert gone not in language, f"InputLanguage.swift still mentions {gone}"
    for gone in (".shuangpin,", ".wubi,", "9 键、双拼和五笔"):
        assert gone not in welcome, f"WelcomeFlowView.swift still mentions {gone!r}"

    print("=== trim summary: 语言与方案 ===", flush=True)
    print("  提供方案: 全拼（26 键 / 9 键 / 14 键 / 18 键）+ 手写", flush=True)
    print("  已移除: 双拼/自然码/微软/首道/九键双拼/五笔/注音/笔画/粤拼/粤语双拼/"
          "日语/日语九键/韩语/越南语/藏文", flush=True)
    print("  保留: MLKitDigitalInkRecognition + HandwritingInputView.swift（手写依赖）", flush=True)
    print("  资源: MSIME_IOS_OMIT_ON_DEMAND=1 瘦包本来就不带粤拼/注音/笔画/日文/五笔词库", flush=True)

    voice = read(root, VOICE_PRESETS)
    cloud_pref = read(root, CLOUD_CANDIDATE_PREF)
    options = read(root, CANDIDATE_OPTIONS)
    kvc = read(root, KEYBOARD_VC)
    rust = read(root, RUST_PREFS)

    assert "filter(\\.isOnDevice).map" in voice, "语音设置页仍列云端服务商"
    assert "get { true }" in cloud_pref, "云候选没有恒开"
    assert "cloudCandidates" not in options, "云候选开关仍在设置页"
    assert "let cloud: KeyboardCloudClipboard? = nil" in kvc, "云剪贴板未移除"
    assert "clipboard_history: true," in rust, "本机剪贴板历史未默认开"
    assert "candidate_english_gloss: true," in rust, "离线英文释义未默认显示"

    print("=== trim summary: 云与隐私 ===", flush=True)
    print("  语音: 只保留设备端 local/system，云端 ASR 选项全部移除", flush=True)
    print("  云联想: 恒开，端点 inputtools.google.com，设置页无开关", flush=True)
    print("  云剪贴板: 移除，键盘只有本机剪贴板历史且默认开启", flush=True)
    print("  翻译: 离线释义（英文内置 + 六语言 zh-*.db 由 CI 打进包），零联网", flush=True)

    onboarding = read(root, ONBOARDING)
    layout_view = read(root, KEYBOARD_LAYOUT_VIEW)
    layout_pref = read(root, KEYBOARD_LAYOUT_PREF)
    plugin_detail = read(root, PLUGIN_DETAIL)
    rust_options = read(root, RUST_OPTIONS)

    assert "        helpcodeGroup\n" not in onboarding, "设置页仍渲染辅助码组"
    assert "组字时保留 Shift" not in layout_view, "Shift 开关仍在设置页"
    assert "static func sharedQuanpinShift(in preferences: [String: Any]?) -> Bool { false }" in layout_pref
    assert 'NavigationLink("前往辅助码设置")' not in plugin_detail, "插件页仍有辅助码入口"
    assert "helpcode: false," in rust_options and "show_helpcode: false," in rust_options

    print("=== trim summary: 辅助码已移除 ===", flush=True)
    print("  设置页「辅助码」整组、Shift 开关、插件页入口全部移除", flush=True)
    print("  ⇧ 固定为分词键；引擎 helpcode / show_helpcode 默认关", flush=True)

    tpref = read(root, TRANSLATION_PREF)
    tstore = read(root, TRANSLATION_STORE)
    tsettings = read(root, TRANSLATION_SETTINGS)
    gcard = read(root, GLOSS_CARD)
    sys_file = read(root, SYS_TRANSLATION)

    assert "import Translation" in sys_file, "系统翻译服务未落地"
    assert "case off, account, niutrans, tencent, custom, ai, system" in tpref
    assert "  case system\n" in tpref
    assert "if #available(iOS 26.0, *) { return .system }" in tpref
    assert "SystemCandidateTranslationService()" in tstore
    assert 'SystemCandidateTranslationService(), scope: "system-apple"' in kvc
    assert "case offline, account, tencent, niutrans, custom, ai, system" in gcard
    assert "candidate_translations: true," in rust
    assert 'TranslationSession(' in tsettings and 'response.targetText' in tsettings
    assert "import Translation" in tsettings
    assert "Picker(" not in tsettings and "请检查凭据、地址与网络" not in tsettings
    assert "系统翻译（设备端）" in tsettings

    print("=== trim summary: Apple 系统翻译 ===", flush=True)
    print("  TranslationSession 设备端翻译，原文译文不出设备、零联网", flush=True)
    print("  前提：系统「设置 → 翻译」已下载简体中文与目标语言", flush=True)
    print("  离线表保留为语言包未装时的兜底；在线服务不再被选中", flush=True)

    theme_file = read(root, THEME_FILE)
    kit = read(root, DESIGN_KIT)

    assert "static let accentUIColor = UIColor.systemBlue" in theme_file, "强调色未改用系统蓝"
    assert "static let onAccent = Color.white" in theme_file, "蓝底前景未改白色"
    assert "UIColor.systemBlue" in theme_file and "withAlphaComponent" in theme_file, "着色底未跟随系统蓝"
    assert "static let accentUIColor = forestUIColor" not in theme_file, "强调色仍是品牌绿"
    assert "UIColor.systemGroupedBackground" in theme_file, "页面背景未系统化"
    assert "UIColor.secondarySystemGroupedBackground" in theme_file, "卡片背景未系统化"
    assert "static let hairUIColor = UIColor.separator" in theme_file, "分隔线未系统化"
    assert "static let subUIColor = UIColor.secondaryLabel" in theme_file, "次要文字未系统化"
    assert "static let cardRadius: CGFloat = 10" in theme_file, "卡片圆角未改为 10"
    assert "cardRadius: CGFloat = 26" not in theme_file, "旧圆角残留"
    assert "palette(traits)" not in theme_file, "季节解析函数仍被引用"
    assert "AppThemePalette.mix" in theme_file, "mixUIColor 不应受影响"

    assert "minHeight: 44" in kit and "minHeight: 52" not in kit, "行高未改为 44"
    assert "var font: Font = .body" in kit, "行标题未改语义字体"
    assert "font(.footnote).foregroundStyle(MetasequoiaTheme.sub)" in kit, "副文字未改语义字体"
    assert ".font(.callout).foregroundStyle(MetasequoiaTheme.sub)" in kit, "行值未改语义字体"
    assert "font(.system(size: 17))" not in kit, "固定 17pt 标题残留"

    global_theme = read(root, KB_GLOBAL_THEME)
    keyboard_theme = read(root, KB_KEYBOARD_THEME)
    candidate_palette = read(root, KB_CANDIDATE_PALETTE)

    assert global_theme.count("static let accent = UIColor.systemBlue") == 2, "键盘兜底 token 未全部改系统蓝"
    for gone in ("adaptiveColor(0x2C7A4B", "adaptiveColor(0x32664B", "adaptiveColor(0x15683B"):
        assert gone not in global_theme, f"键盘 token 仍有品牌绿 {gone}"
    assert "let accent = rgbColor(dark ? 0x0A84FF : 0x007AFF)" in global_theme, "季节混色源仍是绿"
    assert "accent: UIColor.systemBlue, text: text" in global_theme, "皮肤选择器预览色仍是绿"
    assert "private static func branded(" in keyboard_theme, "drawnPalette 未收口"
    assert "self.palette.map { Self.branded($0) }" in keyboard_theme, "通用明暗分支未收口"
    assert "accent: UIColor.systemBlue," in keyboard_theme, "nativePalette 未改系统蓝"
    assert "return UIColor { $0.userInterfaceStyle == .dark ? .black : .white }" not in keyboard_theme, "蓝底黑字兜底仍在"
    assert "accent: keyboard.accent," in candidate_palette, "候选条仍会被 Rust 绿色 accent 覆盖"

    print("=== trim summary: iOS 化 ===", flush=True)
    print("  卡片圆角 26→10，行高 52→44，行内边距 20→16", flush=True)
    print("  页面/卡片/分隔线/次要文字 → iOS 系统分组色；强调色用系统蓝（systemBlue）", flush=True)
    print("  语义字体 .body/.callout/.footnote，支持动态字体", flush=True)
    print("=== trim summary: 键盘皮肤品牌色 ===", flush=True)
    print("  键盘走 KeyboardTheme 独立取色链路，不读 MetasequoiaTheme；品牌色在源头统一", flush=True)
    print("  Native/System/Season 三组兜底 token、季节混色源、主题预览色 → 系统蓝", flush=True)
    print("  drawnPalette 收口：system/native/内置主题/跟随系统的 accent·onAccent·候选首选统一",
          flush=True)
    print("  各皮肤背景/按键/文字公式保留；自定义皮肤 design 与候选皮肤包不动", flush=True)

    project = read(root, PROJECT_YML)
    ext_plist = read(root, EXT_PLIST)
    logo_shape = read(root, LOGO_SHAPE)

    assert "INFOPLIST_KEY_CFBundleDisplayName: ccboard" in project, "主 App 显示名未改"
    assert "CFBundleDisplayName: ccboard" in project, "键盘扩展显示名未改"
    assert "<string>ccboard</string>" in ext_plist, "键盘扩展 Info.plist 未改"
    assert "app.msime.ios" in project and "PRODUCT_NAME: MSIMEApp" in project, "技术标识被误改"

    assert "UIColor.systemBlue" in logo_shape, "绘图 logo 未用系统蓝"
    assert "0xA8 / 255.0" not in logo_shape, "旧绿边仍在绘图 logo 里"
    for symbol in ("MSIMELogoStroke", "MSIMELogoFrame", "MSIMELogoMark",
                   "strokeDrawn", "static func draw(in"):
        assert symbol in logo_shape, f"绘图 logo 缺少 API {symbol}"

    leftovers = []
    for path in iter_text_files(root):
        try:
            with path.open("r", encoding="utf-8", newline="") as f:
                text = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        if any(old in text for old in ("水杉", "METASEQUOIA IME", "© 2026 Metasequoia")):
            leftovers.append(path.relative_to(root).as_posix())
    assert not leftovers, f"品牌名残留: {leftovers[:5]}"

    asset_count = 0
    for src in sorted(BRAND_ASSETS.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(BRAND_ASSETS)
        dst = root / rel
        assert dst.is_file() and dst.read_bytes() == src.read_bytes(), f"品牌资源未覆盖: {rel.as_posix()}"
        asset_count += 1
    assert asset_count >= 60, f"品牌资源数量不足: {asset_count}"

    print("=== trim summary: 品牌改名与换标 ===", flush=True)
    print(f"  水杉输入法 → ccboard；{asset_count} 个图标资源 + 绘图 logo 全部替换", flush=True)
    print("  CFBundleIdentifier / PRODUCT_NAME / 类名等技术标识保持不变", flush=True)
    print("TRIM_OK", flush=True)


def main() -> None:
    root = source_root()
    print(f"trim root: {root}", flush=True)
    replace_once(root, PREF, OFFERED_COMMENT_OLD, "", "R0 删掉方案总开关的旧版本注释")
    replace_once(root, PREF, OFFERED_OLD, OFFERED_NEW, "R1 方案总开关收敛为全拼+手写")
    overlay(root, LANGUAGE, "InputLanguage.swift", "R2 语言行只留全拼/手写")
    replace_once(root, WELCOME, STALE_COMMENT_CHOICES, "", "R3 删掉引导页多版本注释")
    replace_once(root, WELCOME, CHOICES_OLD, CHOICES_NEW, "R4 引导页方案卡只留全拼/手写")
    replace_once(root, WELCOME, STALE_COMMENT_BODY, "", "R5 删掉引导页文案的旧版本注释")
    replace_once(root, WELCOME, BODY_OLD, BODY_NEW, "R6 引导页文案去掉 9 键/双拼/五笔")
    overlay(root, LANGUAGE_TESTS, "InputLanguageTests.swift", "R7 语言行测试改为裁剪版断言")
    replace_once(root, VOICE_PRESETS, VOICE_OLD, VOICE_NEW, "R8 语音服务商只留设备端")
    overlay(root, CLOUD_CANDIDATE_PREF, "CloudCandidatePreference.swift", "R9 云候选恒开")
    replace_once(root, CANDIDATE_OPTIONS, CLOUD_DECL_OLD, "", "R10 删掉云候选开关声明")
    replace_once(root, CANDIDATE_OPTIONS, CLOUD_TOGGLE_OLD, CLOUD_TOGGLE_NEW, "R11 删掉云候选开关 UI")
    replace_once(root, KEYBOARD_VC, CLIPBOARD_CLOUD_OLD, CLIPBOARD_CLOUD_NEW, "R12 云剪贴板恒为本地")
    replace_once(root, RUST_PREFS, RUST_CLIPBOARD_OLD, RUST_CLIPBOARD_NEW, "R13 本机剪贴板历史默认开")
    replace_once(root, RUST_PREFS, RUST_GLOSS_OLD, RUST_GLOSS_NEW, "R14 离线英文释义默认显示")
    replace_once(root, ONBOARDING, HELPCODE_GROUP_OLD, HELPCODE_GROUP_NEW, "R15 设置页移除辅助码整组")
    replace_once(root, KEYBOARD_LAYOUT_VIEW, SHIFT_TOGGLE_OLD, "", "R16 移除组字时保留 Shift 开关")
    replace_once(root, KEYBOARD_LAYOUT_PREF, SHIFT_PREF_OLD, SHIFT_PREF_NEW, "R17 辅助码偏好恒关")
    replace_once(root, PLUGIN_DETAIL, PLUGIN_LINK_OLD, "", "R18 移除插件页辅助码入口")
    replace_once(root, RUST_OPTIONS, RUST_HELPCODE_OLD, RUST_HELPCODE_NEW, "R19 引擎辅助码默认关")
    overlay(root, SYS_TRANSLATION, "SystemCandidateTranslationService.swift", "R20 新增 Apple 系统翻译服务")
    replace_once(root, TRANSLATION_PREF, SYS_PROVIDER_CASE_OLD, SYS_PROVIDER_CASE_NEW, "R21 翻译服务枚举加 system")
    replace_once(root, TRANSLATION_PREF, SYS_PROVIDER_TITLE_OLD, SYS_PROVIDER_TITLE_NEW, "R22 服务名加系统翻译")
    replace_once(root, TRANSLATION_PREF, SYS_ROUTE_CASE_OLD, SYS_ROUTE_CASE_NEW, "R23 路由枚举加 system")
    replace_once(root, TRANSLATION_PREF, SYS_ROUTE_PROVIDER_OLD, SYS_ROUTE_PROVIDER_NEW, "R24 路由 provider 分支")
    replace_once(root, TRANSLATION_PREF, SYS_ROUTE_SCOPE_OLD, SYS_ROUTE_SCOPE_NEW, "R25 路由缓存分支")
    replace_once(root, TRANSLATION_PREF, SYS_CLIENT_SWITCH_OLD, SYS_CLIENT_SWITCH_NEW, "R26 客户端 switch 补 system")
    replace_once(root, TRANSLATION_PREF, SYS_ROUTE_IN_OLD, SYS_ROUTE_IN_NEW, "R27 路由恒为系统翻译")
    replace_once(root, GLOSS_CARD, SYS_CARD_SOURCE_OLD, SYS_CARD_SOURCE_NEW, "R28 释义卡来源加 system")
    replace_once(root, GLOSS_CARD, SYS_CARD_INIT_OLD, SYS_CARD_INIT_NEW, "R29 释义卡构造分支")
    replace_once(root, GLOSS_CARD, SYS_CARD_TITLE_OLD, SYS_CARD_TITLE_NEW, "R30 释义卡来源名")
    replace_once(root, TRANSLATION_STORE, SYS_STORE_INIT_OLD, SYS_STORE_INIT_NEW, "R31 默认注入系统翻译服务")
    replace_once(root, KEYBOARD_VC, SYS_PREFERRED_GLOSS_OLD, SYS_PREFERRED_GLOSS_NEW, "R32 系统译文优先")
    replace_once(root, KEYBOARD_VC, SYS_APPLY_ROUTE_OLD, SYS_APPLY_ROUTE_NEW, "R33 键盘注入系统翻译服务")
    replace_once(root, RUST_PREFS, SYS_RUST_DEFAULTS_OLD, SYS_RUST_DEFAULTS_NEW, "R36 候选翻译默认开")
    overlay(root, TRANSLATION_SETTINGS, "TranslationProviderSettingsView.swift", "R34 设置页锁定系统翻译（移除全部在线服务选项与凭据输入）")
    replace_once(root, THEME_FILE, UI_ACCENT_OLD, UI_ACCENT_NEW, "R39 强调色固定品牌绿")
    replace_once(root, THEME_FILE, UI_ON_ACCENT_OLD, UI_ON_ACCENT_NEW, "R39b 强调色前景固定")
    replace_once(root, THEME_FILE, UI_ACCENT_SOFT_OLD, UI_ACCENT_SOFT_NEW, "R40 着色底固定经典值")
    replace_once(root, THEME_FILE, UI_ACCENT_SYS_OLD, UI_ACCENT_SYS_NEW, "R40a 强调色改用 iOS 系统蓝")
    replace_once(root, THEME_FILE, UI_ON_ACCENT_SYS_OLD, UI_ON_ACCENT_SYS_NEW, "R40b 蓝底前景改白色")
    replace_once(root, THEME_FILE, UI_ACCENT_SOFT_SYS_OLD, UI_ACCENT_SOFT_SYS_NEW, "R40c 着色底改系统蓝透明版")
    replace_once(root, THEME_FILE, UI_FOREST_COMMENT_OLD, UI_FOREST_COMMENT_NEW, "R40d 品牌绿注释更新")
    replace_once(root, THEME_FILE, UI_CANVAS_OLD, UI_CANVAS_NEW, "R41 页面背景系统化")
    replace_once(root, THEME_FILE, UI_SURFACE_OLD, UI_SURFACE_NEW, "R42 卡片背景系统化")
    replace_once(root, THEME_FILE, UI_HAIR_OLD, UI_HAIR_NEW, "R43 分隔线系统化")
    replace_once(root, THEME_FILE, UI_SUB_OLD, UI_SUB_NEW, "R44 次要文字系统化")
    replace_once(root, THEME_FILE, UI_RADIUS_OLD, UI_RADIUS_NEW, "R45 卡片圆角 26→10")
    replace_once(root, THEME_FILE, UI_PALETTE_FN_OLD, UI_PALETTE_FN_NEW, "R46 移除未用的季节解析函数")
    replace_once(root, DESIGN_KIT, UI_SUBTEXT_OLD, UI_SUBTEXT_NEW, "R47 副文字语义字体")
    replace_once(root, DESIGN_KIT, UI_ROW_METRICS_OLD, UI_ROW_METRICS_NEW, "R48 行高 44 / 内边距 16")
    replace_once(root, DESIGN_KIT, UI_TOGGLE_ON_OLD, UI_TOGGLE_ON_NEW, "R49 开关行度量")
    replace_once(root, DESIGN_KIT, UI_TOGGLE_OFF_OLD, UI_TOGGLE_OFF_NEW, "R50 禁用开关行度量")
    replace_once(root, DESIGN_KIT, UI_GROUP_TITLE_OLD, UI_GROUP_TITLE_NEW, "R51 分组标题度量与字体")
    replace_once(root, DESIGN_KIT, UI_GROUP_FOOTER_OLD, UI_GROUP_FOOTER_NEW, "R52 分组脚注度量")
    replace_once(root, DESIGN_KIT, UI_GROUP_HEADER_OLD, UI_GROUP_HEADER_NEW, "R53 分区头语义字体")
    replace_once(root, DESIGN_KIT, UI_INFO_TITLE_FONT_OLD, UI_INFO_TITLE_FONT_NEW, "R54 行标题语义字体")
    replace_once(root, DESIGN_KIT, UI_NAV_VALUE_OLD, UI_NAV_VALUE_NEW, "R55 导航行值语义字体")
    replace_once(root, DESIGN_KIT, UI_VALUE_ROW_OLD, UI_VALUE_ROW_NEW, "R56 只读行值语义字体")
    replace_once(root, DESIGN_KIT, UI_SELECT_VALUE_OLD, UI_SELECT_VALUE_NEW, "R57 选择行值语义字体")
    replace_once(root, DESIGN_KIT, UI_INLINE_BTN_OLD, UI_INLINE_BTN_NEW, "R58 行内按钮语义字体")
    replace_once(root, DESIGN_KIT, UI_CHEVRON_OLD, UI_CHEVRON_NEW, "R59 箭头颜色对齐系统")
    replace_once(root, DESIGN_KIT, UI_EXT_LINK_OLD, UI_EXT_LINK_NEW, "R60 外链图标颜色对齐系统")
    replace_once(root, KB_GLOBAL_THEME, KB_NATIVE_OLD, KB_NATIVE_NEW, "R61 经典兜底键盘品牌色改系统蓝")
    replace_once(root, KB_GLOBAL_THEME, KB_SYSTEM_OLD, KB_SYSTEM_NEW, "R62 原生皮肤品牌色与 logo 改系统蓝")
    replace_once(root, KB_GLOBAL_THEME, KB_SEASON_PALETTE_OLD, KB_SEASON_PALETTE_NEW, "R63 季节配色品牌槽位改系统蓝")
    replace_once(root, KB_GLOBAL_THEME, KB_SEASON_MIX_OLD, KB_SEASON_MIX_NEW, "R64 键盘底板混色源改系统蓝")
    replace_once(root, KB_GLOBAL_THEME, KB_PREVIEW_OLD, KB_PREVIEW_NEW, "R65 皮肤选择器预览色改系统蓝")
    replace_once(root, KB_KEYBOARD_THEME, KB_NATIVE_PALETTE_OLD, KB_NATIVE_PALETTE_NEW, "R66 原生兜底配色改系统蓝")
    replace_once(root, KB_KEYBOARD_THEME, KB_DRAWN_OLD, KB_DRAWN_NEW, "R67 drawnPalette 收口所有主题品牌色")
    replace_once(root, KB_KEYBOARD_THEME, KB_ACTION_FG_OLD, KB_ACTION_FG_NEW, "R68 回车键兜底前景改白色")
    replace_once(root, KB_KEYBOARD_THEME, KB_ON_ACCENT_OLD, KB_ON_ACCENT_NEW, "R69 强调色填充兜底前景改白色")
    replace_once(root, KB_CANDIDATE_PALETTE, KB_CANDIDATE_ACCENT_OLD, KB_CANDIDATE_ACCENT_NEW, "R70 候选条首选字色跟随键盘品牌色")
    overlay(root, LOGO_SHAPE, "MSIMELogoShape.swift", "R73 绘图 logo 换成 ccboard 双 C 标志")
    rebrand(root)
    install_brand_assets(root)
    verify(root)


if __name__ == "__main__":
    main()

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
    assert "case .off, .account, .system:" in tsettings
    assert "case offline, account, tencent, niutrans, custom, ai, system" in gcard
    assert "candidate_translations: true," in rust
    assert 'TranslationSession(' in tsettings and 'response.targetText' in tsettings
    assert "import Translation" in tsettings

    print("=== trim summary: Apple 系统翻译 ===", flush=True)
    print("  TranslationSession 设备端翻译，原文译文不出设备、零联网", flush=True)
    print("  前提：系统「设置 → 翻译」已下载简体中文与目标语言", flush=True)
    print("  离线表保留为语言包未装时的兜底；在线服务不再被选中", flush=True)
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
    replace_once(root, TRANSLATION_SETTINGS, SYS_SETTINGS_SWITCH_OLD, SYS_SETTINGS_SWITCH_NEW, "R34 设置页补 system 分支")
    replace_once(root, TRANSLATION_SETTINGS, SYS_SETTINGS_INFO_OLD, SYS_SETTINGS_INFO_NEW, "R35 设置页说明改为系统翻译")
    replace_once(root, TRANSLATION_SETTINGS, SYS_SETTINGS_IMPORT_OLD, SYS_SETTINGS_IMPORT_NEW, "R35b 设置页 import Translation")
    replace_once(root, RUST_PREFS, SYS_RUST_DEFAULTS_OLD, SYS_RUST_DEFAULTS_NEW, "R36 候选翻译默认开")
    replace_once(root, TRANSLATION_SETTINGS, SYS_TEST_OLD, SYS_TEST_NEW, "R37 测试按钮改走系统翻译")
    verify(root)


if __name__ == "__main__":
    main()

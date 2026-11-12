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
KEYBOARD_VC = f"{IOS}/KeyboardExtension/Sources/keyboard/KeyboardViewController.swift"
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
    verify(root)


if __name__ == "__main__":
    main()

import Foundation

/// 「输入」页「语言与方案」卡片中的一行，以及它能选择的触屏方案。
///
/// 定制版只保留两行：全拼、手写。英文没有自己的触屏方案（中/英键始终都在），
/// 所以也不把它当作一种语言。
enum InputLanguage: String, CaseIterable, Identifiable {
  case quanpin, handwriting

  var id: String { rawValue }

  /// 保留旧版全拼行的无障碍标识，已安装的 UI 测试和外部自动化仍能找到同一行。
  var accessibilityKey: String { self == .quanpin ? "mandarin" : rawValue }

  var name: String {
    switch self {
    case .quanpin: "全拼"
    case .handwriting: "手写"
    }
  }

  /// 该语言 30pt 图块上的字形。
  var tile: String {
    switch self {
    case .quanpin: "拼"
    case .handwriting: "写"
    }
  }

  /// 全拼的 26 键、9 键、14 键、18 键都是全拼自己的布局，顺序与 Android
  /// `TypingPage.Language.QUANPIN` 相同，全部保留。
  var schemes: [ChineseInputScheme] {
    switch self {
    case .quanpin: [.quanpin, .fourteenKey, .eighteenKey, .nineKey]
    case .handwriting: [.handwriting]
    }
  }

  /// 每一行都可以移除，前提是键盘还剩至少一个可运行的方案。
  var isRemovable: Bool { true }

  static func of(_ scheme: ChineseInputScheme) -> InputLanguage {
    allCases.first { $0.schemes.contains(scheme) } ?? .quanpin
  }

  /// 不再随包携带粤拼、注音、笔画词库，也不发布语言词库资源包。
  static var installedDictionarySchemes: Set<ChineseInputScheme> { [] }
}

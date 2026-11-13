import Foundation
import Translation

/// 候选释义改走 Apple 系统翻译（Translation.framework）。
///
/// 所有翻译都在这台设备上完成：按 Apple 文档，TranslationSession 的翻译全部在设备端，
/// Apple 最多收集 bundle ID 与源/目标语言的性能统计，不包含原文或译文。
/// 前提：用户已在「设置 → 翻译 → 已下载的语言」装好简体中文与目标语言；
/// 语言对没装时 isReady 为 false，这里安静返回空结果，让候选栏回退到随包离线释义。
///
/// 注意：TranslationSession 类本身是 iOS 18+，但 `init(installedSource:target:)` 与
/// `isReady` 在 SDK 里标注为 iOS 26+（文档页只写了类的可用性）。本机 iOS 27 可用。
@available(iOS 26.0, *)
struct SystemCandidateTranslationService: CandidateTranslationService {
  func translate(words: [String], target: String) async throws -> [String] {
    guard !words.isEmpty else { return [] }
    let source = Locale.Language(identifier: "zh-Hans")
    let destination = Locale.Language(identifier: Self.localeIdentifier(for: target))
    // 这个初始化器不 throws：语言对没装时由下面的 isReady 判断。
    let session = TranslationSession(installedSource: source, target: destination)
    let ready = await session.isReady
    guard ready else { return words.map { _ in "" } }
    let requests = words.enumerated().map { index, word in
      TranslationSession.Request(sourceText: word, clientIdentifier: String(index))
    }
    do {
      let responses = try await session.translations(from: requests)
      var byIndex: [Int: String] = [:]
      for response in responses {
        if let key = response.clientIdentifier, let index = Int(key) {
          byIndex[index] = response.targetText
        }
      }
      return words.indices.map { byIndex[$0] ?? "" }
    } catch {
      return words.map { _ in "" }
    }
  }

  /// 共享偏好里的语言代码（EN / JA / FR …）换成系统翻译要的区域标识。
  private static func localeIdentifier(for code: String) -> String {
    switch code.lowercased() {
    case "en": "en-US"
    case "ja": "ja-JP"
    case "ko": "ko-KR"
    case "fr": "fr-FR"
    case "de": "de-DE"
    case "es": "es-ES"
    case "ru": "ru-RU"
    case "zh", "zh-hans": "zh-Hans"
    default: code
    }
  }
}

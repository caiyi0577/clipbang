import SwiftUI
import Translation

/// 「翻译服务」：定制版锁定为 Apple 系统翻译——全部在这台设备上完成，
/// 原文和译文都不离开手机，不经过任何服务器，也不需要任何凭据。
///
/// 不再提供在线服务选项（小牛 / 腾讯 / DeepL / 自定义 / 水杉账号 / AI 辅助），
/// 也不再有凭据输入和「测试连接」探针；这里只剩使用说明、语言包下载指引和设备端测试。
struct TranslationProviderSettingsView: View {
  @State private var status: String?
  @State private var testing = false
  @State private var operation: Task<Void, Never>?
  @State private var testGeneration = OperationGeneration()

  private var languagePackHint: String {
    "候选词的英文释义由 iOS 系统翻译在这台设备上生成，原文和译文都不离开手机，不经过任何服务器，也不需要 API Key。\n\n使用前提：在 iPhone「设置 → 翻译 → 已下载的语言」里下载 简体中文 与 English。"
  }

  var body: some View {
    Form {
      Section {
        Text(languagePackHint).font(.footnote).foregroundStyle(.secondary)
      } header: {
        Text("系统翻译（设备端）")
      }
      .designRow()

      Section {
        Button(testing ? "正在测试…" : "测试翻译「你好」") { test() }
          .disabled(testing)
          .accessibilityIdentifier("translationProviderTest")
        if let status {
          Text(status).font(.footnote).foregroundStyle(.secondary)
        }
      } footer: {
        Text("打开系统翻译设置：iPhone「设置 → 翻译 → 已下载的语言」。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      .designRow()
    }
    .designPage()
    .navigationTitle("翻译服务")
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear {
      ViewRequestTask.cancel(generation: $testGeneration, task: $operation)
      testing = false
    }
  }

  private func test() {
    if #available(iOS 26.0, *) {
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
            testing = false
            operation = nil
            status = "还没就绪：请在 iPhone「设置 → 翻译 → 已下载的语言」下载 简体中文 与 English"
            return
          }
          let response = try await session.translate("你好")
          guard testGeneration.isCurrent(id) else { return }
          testing = false
          operation = nil
          status = "测试成功：你好 → \(response.targetText)"
        } catch {
          guard testGeneration.isCurrent(id) else { return }
          testing = false
          operation = nil
          status = "测试失败：请在 iPhone「设置 → 翻译 → 已下载的语言」下载 简体中文 与 English"
        }
      }
      return
    }
    status = "此功能需要 iOS 26 或更高版本。"
  }
}

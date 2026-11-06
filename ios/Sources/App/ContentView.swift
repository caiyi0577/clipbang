import SwiftUI

struct ContentView: View {
    @State private var sampleText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    header

                    stepCard(
                        number: "1",
                        title: "添加键盘",
                        detail: "设置 › 通用 › 键盘 › 键盘 › 添加新键盘 › 剪贴炸"
                    )

                    stepCard(
                        number: "2",
                        title: "开启完全访问",
                        detail: "点进「剪贴炸」这一项，打开「允许完全访问」。不开这个开关，键盘读不到剪贴板。"
                    )

                    stepCard(
                        number: "3",
                        title: "允许粘贴",
                        detail: "设置 › 应用 › 剪贴炸 › 从其他 App 粘贴 › 允许。开了这一步之后读剪贴板不再弹窗。"
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("试一试")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $sampleText)
                            .frame(height: 120)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topLeading) {
                                if sampleText.isEmpty {
                                    Text("点这里唤起键盘")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("剪贴炸")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("骨架版本 0.1.0")
                .font(.largeTitle.weight(.bold))
            Text("当前只验证编译和安装，剪贴板监听尚未接入。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func stepCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

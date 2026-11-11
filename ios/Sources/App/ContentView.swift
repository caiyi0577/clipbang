import SwiftUI

struct ContentView: View {
    @State private var logs: [String] = []
    @State private var pasteboardPreview = "未读取"
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let probe = MonitorProbe.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {

                storeCard

                statusCard

                HStack(spacing: 10) {
                    Button {
                        pasteboardPreview = probe.readPasteboard()
                        refresh()
                    } label: {
                        Text("读当前剪贴板")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        probe.clearLogs()
                        refresh()
                    } label: {
                        Text("清空日志")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Text("剪贴板内容：\(pasteboardPreview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                instructions

                logList
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ccbroad · 状态")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                probe.start()
                refresh()
            }
            .onReceive(tick) { _ in refresh() }
        }
    }

    /// 正式版最关心的一屏：到底有没有把复制的内容存进共享区。
    private var storeCard: some View {
        let items = ClipStore.shared.all()
        let available = ClipStore.shared.groupAvailable
        let latest = items.first.map { String($0.text.prefix(40)) } ?? "无"

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("记录库")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    ClipStore.shared.clear()
                    refresh()
                } label: {
                    Text("清空记录")
                        .font(.caption2)
                }
            }
            row("已入库", "\(items.count) 条", ok: !items.isEmpty)
            row("共享区", available ? "可用" : "不可用", ok: available)
            Text("最近一条：\(latest)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("私有类", probe.classFound ? "找到" : "未找到", ok: probe.classFound)
            row("监听方法", probe.selectorResponded ? "可调用" : "不可用", ok: probe.selectorResponded)
            row("激活调用", probe.activationCalled ? "已执行" : "未执行", ok: probe.activationCalled)
            row("后台保活", probe.audioRunning ? "音频运行中" : "未运行", ok: probe.audioRunning)
            if let error = probe.lastError {
                Text("错误：\(error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ok ? .green : .orange)
            Spacer()
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("怎么测")
                .font(.caption.weight(.semibold))
            Text("1. 设置 → 通用 → 键盘 → 添加「ccbroad」，并打开「完全访问」\n2. 默认中文拼音：敲字母出候选，点候选上屏；空格/换行上屏首候选\n3. 支持全拼 nihao、简拼 nh、连打（选带 › 的候选后剩余拼音继续出词）\n4. 点「中」切英文直输；顶部「键盘 / 记录库」切换，点条目直接插入\n5. 键盘可见时复制的文字会自动逐条收进记录库，不用切回本 App")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var logList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("事件日志（\(logs.count)）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(logs.reversed(), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxHeight: .infinity)
    }

    private func refresh() {
        logs = probe.logs()
    }
}

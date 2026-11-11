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
            .navigationTitle("剪贴炸 · 采集状态")
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
            Text("1. 复制一段文字，直接切到键盘「剪贴炸」——键盘会自己采集当前剪贴板\n2. 列表里点一条即可插入；想再采一次点键盘上的「刷新」\n3. App 在前台时也会补采记录；后台受 iOS 粘贴隐私限制读不到文字，属正常现象\n4. 日志里「通道」一项是后台读取能力的探测结果")
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

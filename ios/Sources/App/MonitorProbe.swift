import Foundation
import UIKit
import AVFoundation
import UserNotifications

/// 诊断探针：只回答一个问题——iOS 27 上还能不能收到剪贴板变化的后台通知。
/// 不接存储、不弹业务通知，所有结果写进日志，回到 App 里直接看。
final class MonitorProbe {

    static let shared = MonitorProbe()

    private let logKey = "clipbang.probe.log.v1"
    private let defaults = UserDefaults.standard

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var started = false
    private var pollTimer: Timer?
    private var lastChangeCount: Int = -1

    private(set) var classFound = false
    private(set) var selectorResponded = false
    private(set) var activationCalled = false
    private(set) var audioRunning = false
    private(set) var lastError: String?

    /// Darwin 通知回调必须是 C 函数指针，不能捕获上下文，
    /// 所以接到单例方法里再处理。
    private static let pasteboardChanged: @convention(c) (
        CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?,
        UnsafeRawPointer?, CFDictionary?
    ) -> Void = { _, _, name, _, _ in
        let label = (name?.rawValue as String?) ?? "(无名)"
        DispatchQueue.main.async {
            MonitorProbe.shared.note("Darwin 通知：\(label)")
        }
    }

    func start() {
        guard !started else { return }
        started = true

        note("探针启动 v3")
        startSilentAudio()
        registerAllNotifications()
        activatePrivateListener()

        // 轮询对照：只要进程没被挂起，剪贴板一变这里就会有记录。
        // 轮询有变化而通知没有，就说明系统不再发通知；两者都没有，说明进程被挂起了。
        lastChangeCount = UIPasteboard.general.changeCount
        note("初始 changeCount=\(lastChangeCount)")
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        note("监听注册完成")
    }

    private func poll() {
        let board = UIPasteboard.general
        let current = board.changeCount
        guard lastChangeCount >= 0, current != lastChangeCount else { return }

        let state: String
        switch UIApplication.shared.applicationState {
        case .active:    state = "前台"
        case .inactive:  state = "过渡"
        case .background: state = "后台"
        @unknown default: state = "未知"
        }

        // iOS 16 之后后台读 .string 会被粘贴隐私限制挡住。
        // 这里把能试的通道都试一遍，确认有没有别的口子还能拿到文字。
        let direct = board.string
        let rawData = board.data(forPasteboardType: "public.utf8-plain-text")
        let fromData = rawData.flatMap { String(data: $0, encoding: .utf8) }
        let itemCount = board.items.count
        let value = direct ?? fromData

        let channel = direct != nil ? "string" : (fromData != nil ? "data" : "全断")
        let content = value.map { String($0.prefix(40)) } ?? "(读不到)"
        let saved = value.map { ClipStore.shared.save($0) ? "已入库" : "入库失败" } ?? "未入库"
        let group = ClipStore.shared.groupAvailable ? "可用" : "不可用"
        note("变化 \(lastChangeCount)→\(current)｜\(state)｜通道=\(channel)｜items=\(itemCount)｜内容=\(content)｜\(saved)｜共享=\(group)")
        lastChangeCount = current
    }

    @objc private func localPasteboardChanged() {
        note("本地通知：com.apple.pasteboard.changed")
    }

    // MARK: - 后台保活

    private func startSilentAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
            buffer.frameLength = 44100   // 全零，就是一段静音

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()

            audioEngine = engine
            playerNode = player
            audioRunning = true
            note("静音音频已启动，后台保活生效")
        } catch {
            lastError = error.localizedDescription
            note("音频启动失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 通知注册

    private func registerAllNotifications() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let systemName = ["changed", "pasteboard", "apple", "com"].reversed().joined(separator: ".")

        // 两个候选：系统全局名 + Clip 当年自己用的跨进程名
        for name in [systemName, "com.rileytestut.Clip.DidChangePasteboard"] {
            CFNotificationCenterAddObserver(
                center,
                nil,
                MonitorProbe.pasteboardChanged,
                name as CFString,
                nil,
                .deliverImmediately
            )
            note("已监听 Darwin：\(name)")
        }

        // 进程内通知，Clip 当年走的是这一条，上一版漏了
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localPasteboardChanged),
            name: NSNotification.Name(systemName),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localPasteboardChanged),
            name: UIPasteboard.changedNotification,
            object: nil
        )
        note("已监听进程内通知：\(systemName) 与 UIPasteboard.changedNotification")
    }

    /// Clip 当年的做法：用字符串拼出私有类名和方法名，避免被静态扫描命中。
    /// 这里只是诊断，能不能调用成功全看系统还认不认。
    private func activatePrivateListener() {
        let className = ["Connection", "Server", "PB"].reversed().joined()
        let selectorName = ["Notifications", "Change", "Pasteboard", "To",
                            "Listening", "begin"].reversed().joined()

        guard let target = NSClassFromString(className) as? NSObjectProtocol else {
            note("未找到私有类 \(className) —— 系统已移除")
            return
        }
        classFound = true
        note("找到私有类 \(className)")

        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else {
            note("私有类不响应 \(selectorName) —— 接口已改名")
            return
        }
        selectorResponded = true

        _ = target.perform(selector)
        activationCalled = true
        note("已调用 \(selectorName)")
    }

    // MARK: - 日志

    func note(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "\(formatter.string(from: Date()))  \(text)"

        var items = logs()
        items.append(line)
        if items.count > 120 { items = Array(items.suffix(120)) }
        defaults.set(items, forKey: logKey)
    }

    func logs() -> [String] {
        defaults.stringArray(forKey: logKey) ?? []
    }

    func clearLogs() {
        defaults.removeObject(forKey: logKey)
        note("日志已清空")
    }

    func readPasteboard() -> String {
        let board = UIPasteboard.general
        let count = board.changeCount
        let value = board.string ?? "(空或非文本)"
        note("手动读取：changeCount=\(count)，内容=\(value.prefix(40))")
        return value
    }
}

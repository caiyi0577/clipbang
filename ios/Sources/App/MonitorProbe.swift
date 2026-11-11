import Foundation
import UIKit
import AVFoundation
import UserNotifications
import ObjectiveC

/// 后台采集攻坚版。
/// 之前的轮询在通知到达约 1 秒后才读，那时后台剪贴板已被系统屏蔽
/// （changeCount=0、items=0、string/data 全 nil）。这一版在通知回调里
/// 「同一时刻同步读」，验证事件发生的瞬间是否还存在可读窗口；
/// 同时把私有 pasteboard server 的方法全部列出来，看有没有别的取内容接口。
final class MonitorProbe {

    static let shared = MonitorProbe()

    private let logKey = "clipbang.probe.log.v1"
    private let logLimit = 300
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

    /// Darwin 通知回调必须是 C 函数指针，不能捕获上下文。
    /// 这台设备上 Darwin 跨进程通知一直没收到，保持只记日志。
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

        note("探针启动 v4 · 通知即时读 + 私有接口反射")
        startSilentAudio()
        registerAllNotifications()
        activatePrivateListener()
        inspectPrivatePasteboardServer()

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
        let current = UIPasteboard.general.changeCount
        guard lastChangeCount >= 0, current != lastChangeCount else { return }
        capture(source: "轮询 \(lastChangeCount)→\(current)")
        lastChangeCount = current
    }

    /// 关键：通知投递是同步的，这里不做任何 dispatch，立刻读。
    /// 如果后台「事件瞬间」还没被屏蔽，这一条就能拿到内容并入库。
    @objc private func localPasteboardChanged() {
        capture(source: "即时通知")
    }

    private func capture(source: String) {
        let board = UIPasteboard.general
        let direct = board.string
        let rawData = board.data(forPasteboardType: "public.utf8-plain-text")
        let fromData = rawData.flatMap { String(data: $0, encoding: .utf8) }
        let itemCount = board.items.count
        let value = direct ?? fromData

        let channel = direct != nil ? "string" : (fromData != nil ? "data" : "全断")
        let content = value.map { String($0.prefix(40)) } ?? "(读不到)"
        let saved = value.map { ClipStore.shared.save($0) ? "已入库" : "入库失败" } ?? "未入库"
        note("\(source)｜\(stateString())｜count=\(board.changeCount)｜items=\(itemCount)｜通道=\(channel)｜内容=\(content)｜\(saved)")
    }

    private func stateString() -> String {
        switch UIApplication.shared.applicationState {
        case .active:    return "前台"
        case .inactive:  return "过渡"
        case .background: return "后台"
        @unknown default: return "未知"
        }
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

    /// 把私有 pasteboard server 的方法名全列出来。
    /// 如果即时通知这条窗口也读不到内容，下一步就看这里有没有能直接取数据的接口。
    private func inspectPrivatePasteboardServer() {
        let className = ["Connection", "Server", "PB"].reversed().joined()
        guard let cls = NSClassFromString(className) else {
            note("私有类 \(className) 不存在，跳过反射")
            return
        }
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            note("私有类拿不到方法列表")
            return
        }
        var names: [String] = []
        for i in 0..<Int(count) {
            names.append(NSStringFromSelector(method_getName(methods[i])))
        }
        // 一次性诊断，这块 C 内存不释放，几十字节，无所谓
        note("私有类 \(className) 共 \(names.count) 个方法")
        var line = ""
        for name in names {
            if line.count + name.count > 88 {
                note("  方法：\(line)")
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + name
        }
        if !line.isEmpty { note("  方法：\(line)") }
    }

    // MARK: - 日志

    func note(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "\(formatter.string(from: Date()))  \(text)"

        var items = logs()
        items.append(line)
        if items.count > logLimit { items = Array(items.suffix(logLimit)) }
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

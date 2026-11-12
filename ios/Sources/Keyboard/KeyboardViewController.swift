import UIKit

/// ccbroad 键盘：拼音打字键盘 + 剪贴板记录库，双模式切换。
///
/// 关键：键盘是「有交互上下文」的进程，只要键盘可见，系统就允许它读剪贴板内容。
/// 所以活跃期用 Timer 轮询，键盘可见时连续复制的文字会自动逐条入库，
/// 不用切回主 App、不用手动点刷新。键盘一收起就停，不耗电、不常驻。
final class KeyboardViewController: UIInputViewController {

    private let panelHeight: CGFloat = 320
    private let modeSwitch = UISegmentedControl(items: ["键盘", "记录库"])
    private let statusLabel = UILabel()
    private let contentView = UIView()
    private let typingView = TypingKeyboardView()
    private let clipsView = ClipsPanelView()

    private var pollTimer: Timer?
    private var lastCount: Int = -1
    private var lastText: String?
    private var ticks = 0
    private var captures = 0
    private var note = "待采集"

    override func viewDidLoad() {
        super.viewDidLoad()
        typingView.controller = self
        clipsView.controller = self
        buildUI()
        modeSwitch.selectedSegmentIndex = 0
        applyMode()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lastText = nil
        lastCount = UIPasteboard.general.changeCount
        startPolling()
        captureTick()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
        PinyinEngine.shared.clear()
    }

    // MARK: - 供面板与键帽调用

    func insertClip(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func switchToNextKeyboard() {
        advanceToNextInputMode()
    }

    // MARK: - 剪贴板轮询

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.captureTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc func captureTick() {
        let board = UIPasteboard.general
        let count = board.changeCount
        let text = board.string
        lastCount = count
        ticks += 1

        if let text = text, !text.isEmpty {
            if text != lastText {
                lastText = text
                let preview = text.replacingOccurrences(of: "\n", with: " ").prefix(10)
                note = ClipStore.shared.save(text)
                    ? "刚采：\(preview)"
                    : "入库失败"
                captures += 1
                refreshClips()
            }
        } else {
            note = "读不到剪贴板 · 检查完全访问"
        }
        updateStatus()
    }

    private func refreshClips() {
        clipsView.setItems(Array(ClipStore.shared.all().prefix(40)))
    }

    private func updateStatus() {
        let total = ClipStore.shared.all().count
        let group = ClipStore.shared.groupAvailable ? "共享可用" : "共享不可用"
        // 词库信息放最前面：状态行只有一行、窄屏会截断，诊断信息不能被挤掉。
        statusLabel.text = "词库\(PinyinEngine.shared.diagnostic) · \(total)条 · \(group) · 轮询\(ticks)/采\(captures) · \(note)"
    }

    // MARK: - UI

    private func buildUI() {
        view.backgroundColor = .secondarySystemBackground

        let height = view.heightAnchor.constraint(equalToConstant: panelHeight)
        height.priority = .defaultHigh
        height.isActive = true

        modeSwitch.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeSwitch.selectedSegmentTintColor = .systemBlue
        modeSwitch.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let pasteButton = toolButton("粘贴", action: #selector(pasteTapped))
        let captureButton = toolButton("采集", action: #selector(captureTapped))
        let nextButton = toolButton("切换", action: #selector(nextTapped))
        let dismissButton = toolButton("收起", action: #selector(dismissTapped))

        let toolbar = UIStackView(arrangedSubviews: [
            modeSwitch, pasteButton, captureButton, nextButton, dismissButton,
        ])
        toolbar.axis = .horizontal
        toolbar.spacing = 5
        toolbar.alignment = .center

        statusLabel.font = .systemFont(ofSize: 9)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingTail

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(typingView)
        contentView.addSubview(clipsView)
        for panel in [typingView, clipsView] {
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: contentView.topAnchor),
                panel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                panel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        let root = UIStackView(arrangedSubviews: [toolbar, statusLabel, contentView])
        root.axis = .vertical
        root.spacing = 4
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.heightAnchor.constraint(equalToConstant: 15),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        updateStatus()
        refreshClips()
    }

    private func toolButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 5
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func applyMode() {
        let typing = modeSwitch.selectedSegmentIndex == 0
        typingView.isHidden = !typing
        clipsView.isHidden = typing
        if !typing { refreshClips() }
    }

    @objc private func modeChanged() { applyMode() }
    @objc private func captureTapped() { captureTick() }
    @objc private func nextTapped() { switchToNextKeyboard() }
    @objc private func dismissTapped() { dismissKeyboard() }

    /// 用户手势上下文，一定能读到剪贴板内容，顺便入库。
    @objc private func pasteTapped() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            note = "剪贴板为空"
            updateStatus()
            return
        }
        textDocumentProxy.insertText(text)
        _ = ClipStore.shared.save(text)
        note = "刚粘贴：\(text.prefix(8))"
        refreshClips()
        updateStatus()
    }
}

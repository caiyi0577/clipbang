import UIKit

/// ccbroad 键盘容器：顶部一条主流输入法式的工具条，下面挂三个面板
/// （拼音键盘 / 剪贴板记录库 / 设置）。
///
/// 键盘是「有交互上下文」的进程，只要键盘可见，系统就允许它读剪贴板内容。
/// 所以活跃期用 Timer 轮询，键盘可见时连续复制的文字会自动逐条入库，
/// 不用切回主 App、不用手动点刷新。键盘一收起就停，不耗电、不常驻。
final class KeyboardViewController: UIInputViewController {

    private enum Panel {
        case keyboard
        case clips
        case settings
    }

    private let toolbar = UIStackView()
    private let contentView = UIView()
    private let typingView = TypingKeyboardView()
    private let clipsView = ClipsPanelView()
    private let settingsView = KeyboardSettingsView()

    private var heightConstraint: NSLayoutConstraint?
    private var contentMinHeight: NSLayoutConstraint?
    private var activePanel: Panel = .keyboard

    private var pollTimer: Timer?
    private var lastCount: Int = -1
    private var lastText: String?
    private var ticks = 0
    private var captures = 0
    private var note = "待采集"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        typingView.controller = self
        clipsView.controller = self
        buildUI()
        applyTheme()
        applyPanel()
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
        lastCount = board.changeCount
        ticks += 1
        guard let text = board.string, !text.isEmpty else {
            note = "读不到剪贴板 · 检查完全访问"
            return
        }
        if text != lastText {
            lastText = text
            note = ClipStore.shared.save(text) ? "刚采：\(text.prefix(10))" : "入库失败"
            captures += 1
            refreshClips()
        }
    }

    private func refreshClips() {
        clipsView.setItems(Array(ClipStore.shared.all().prefix(40)))
    }

    // MARK: - 设置生效

    private func applyTheme() {
        switch KeyboardPrefs.shared.theme {
        case "light": view.overrideUserInterfaceStyle = .light
        case "dark": view.overrideUserInterfaceStyle = .dark
        default: view.overrideUserInterfaceStyle = .unspecified
        }
    }

    private func applySettings() {
        let total = currentHeight()
        heightConstraint?.constant = total
        // required 下限也要跟着档位走，不能只改 999 那条：
        // 万一系统封装高度赢，键区仍然必须撑到目标高度。
        contentMinHeight?.constant = max(180, total - chromeHeight)
        applyTheme()
        // 模糊音 / 候选字号改了之后，旧的候选排序不能沿用，清掉缓冲重新来。
        PinyinEngine.shared.clear()
        typingView.applySettings()
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    // MARK: - UI

    /// 容器上下各留 6 + 工具条 30 + root spacing 4 = 键区之外的固定占用。
    private var chromeHeight: CGFloat { 46 }

    private func currentHeight() -> CGFloat {
        CGFloat(KeyboardPrefs.shared.keyboardHeight)
    }

    private func buildUI() {
        // UIInputViewController 在 viewDidLoad 阶段系统给的 view 高度是 0。
        // 单靠一条低优先级的 heightAnchor，「高度 = 0」时所有内部约束都能满足，
        // 系统封装高度约束就会赢，键盘被压成一条线、完全出不来。
        // v11 靠 contentView 的 required 下限撑住，v12 重构时漏掉了这条。
        // 这里同时用 999 的目标高度 + required 下限，双保险。
        let total = currentHeight()
        let height = view.heightAnchor.constraint(equalToConstant: total)
        // 低于系统的 required 封装约束避免硬冲突，又远高于普通布局约束。
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        let logo = UIButton(type: .system)
        logo.setTitle("ccbroad", for: .normal)
        logo.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        logo.setTitleColor(.systemBlue, for: .normal)
        logo.addTarget(self, action: #selector(keyboardTapped), for: .touchUpInside)

        let buttons = [
            toolButton("设置", action: #selector(settingsTapped)),
            toolButton("剪贴", action: #selector(clipsTapped)),
            toolButton("粘贴", action: #selector(pasteTapped)),
            toolButton("表情", action: #selector(emojiTapped)),
            toolButton("更多", action: #selector(moreTapped)),
            toolButton("收起", action: #selector(dismissTapped)),
        ]
        toolbar.axis = .horizontal
        toolbar.distribution = .fillEqually
        toolbar.alignment = .center
        toolbar.spacing = 4
        toolbar.addArrangedSubview(logo)
        for button in buttons { toolbar.addArrangedSubview(button) }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        // required（默认优先级）：键区至少要有这么高，键盘才不会塌成一条线。
        let minContent = contentView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: max(180, total - chromeHeight)
        )
        minContent.isActive = true
        contentMinHeight = minContent
        contentView.addSubview(typingView)
        contentView.addSubview(clipsView)
        contentView.addSubview(settingsView)
        for panel in [typingView, clipsView, settingsView] {
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: contentView.topAnchor),
                panel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                panel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        settingsView.onChange = { [weak self] in self?.applySettings() }
        settingsView.onClose = { [weak self] in self?.setPanel(.keyboard) }

        let root = UIStackView(arrangedSubviews: [toolbar, contentView])
        root.axis = .vertical
        root.spacing = 4
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 30),
        ])

        refreshClips()
    }

    private func toolButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12)
        button.setTitleColor(.label, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func setPanel(_ panel: Panel) {
        activePanel = panel
        applyPanel()
    }

    private func applyPanel() {
        typingView.isHidden = activePanel != .keyboard
        clipsView.isHidden = activePanel != .clips
        settingsView.isHidden = activePanel != .settings
        if activePanel == .clips { refreshClips() }
        if activePanel == .settings { settingsView.refreshInfo() }
    }

    @objc private func keyboardTapped() { setPanel(.keyboard) }
    @objc private func settingsTapped() { setPanel(.settings) }
    @objc private func clipsTapped() { setPanel(.clips) }
    @objc private func dismissTapped() { dismissKeyboard() }

    @objc private func emojiTapped() {
        setPanel(.keyboard)
        typingView.showEmoji()
    }

    @objc private func moreTapped() {
        setPanel(.keyboard)
        typingView.showMoreCandidates()
    }

    /// 用户手势上下文，一定能读到剪贴板内容，顺便入库。
    @objc private func pasteTapped() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        _ = ClipStore.shared.save(text)
        refreshClips()
    }
}

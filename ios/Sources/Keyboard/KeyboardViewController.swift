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
    private var correctionApplied = false

    private var pollTimer: Timer?
    private var lastCount: Int = -1
    private var lastText: String?
    private var ticks = 0
    private var captures = 0
    private var note = "待采集"

    /// 工具条 30 + root spacing 4 + 上下各 6 = 键区之外的固定占用。
    private var chromeHeight: CGFloat { 46 }

    /// 只用来防「高度 = 0」时整块塌陷，绝不跟着档位抬高。
    private static let minContentHeight: CGFloat = 180

    override func viewDidLoad() {
        super.viewDidLoad()
        // iOS 11+ 官方自适应键盘高度：让系统按内部约束求高度，而不是拿
        // 一条固定高度的封装约束压住键盘。若运行时 view 不是 UIInputView，
        // 下面 999 的目标高度约束继续兜底。
        (view as? UIInputView)?.allowsSelfSizing = true
        view.backgroundColor = .secondarySystemBackground
        typingView.controller = self
        clipsView.controller = self
        buildUI()
        applyTheme()
        applyPanel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let target = currentHeight()
        let actual = view.bounds.height
        // 极端兜底：若系统把键盘压到连四行键都放不下，最后把目标高度
        // 约束提为 required 试一次；只做一次，避免递归布局。
        if actual > 0, actual < Self.minContentHeight + chromeHeight, !correctionApplied {
            correctionApplied = true
            heightConstraint?.constant = max(260, target)
            heightConstraint?.priority = .required
            view.setNeedsLayout()
        }
        // 真机可读的布局诊断，放在设置页「关于」里，不用连日志也能定位高度问题。
        settingsView.diagnostics = String(
            format: "视 %.0f / 容 %.0f / 键 %.0f / 目标 %.0f",
            actual, contentView.bounds.height, typingView.bounds.height, target
        )
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
        heightConstraint?.constant = currentHeight()
        // 下限固定 180，只防塌陷，不随档位抬高（原因见 buildUI 注释）。
        contentMinHeight?.constant = Self.minContentHeight
        applyTheme()
        // 模糊音 / 候选字号改了之后，旧的候选排序不能沿用，清掉缓冲重新来。
        PinyinEngine.shared.clear()
        typingView.applySettings()
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    // MARK: - UI

    private func currentHeight() -> CGFloat {
        CGFloat(KeyboardPrefs.shared.keyboardHeight)
    }

    private func buildUI() {
        // 高度策略（v12.2）：
        // 1. UIInputView.allowsSelfSizing：让系统按内部约束求高度；
        // 2. view.heightAnchor = 目标高度，优先级 999。系统不再压高度时它赢，
        //    系统仍有 required 封装约束时自动让位，不制造无解约束；
        // 3. contentView 只保留 >=180 的宽松下限，防止 viewDidLoad 阶段
        //    高度为 0 时整块塌陷。
        // v12.1 把下限抬到「目标 - 46」是错的：系统实际给的键盘高度小于
        // 目标值时，两条 required 约束互相冲突，Auto Layout 会打破 root
        // 底边约束，键区从顶部溢出被裁，真机上只剩工具条 + 一排键。
        let total = currentHeight()
        let height = view.heightAnchor.constraint(equalToConstant: total)
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
        // 宽松下限：只保证键区不会塌成一条线。
        let minContent = contentView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Self.minContentHeight
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

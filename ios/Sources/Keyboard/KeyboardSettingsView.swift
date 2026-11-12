import UIKit

/// 键盘内设置页。对应主流输入法里那个「设置 / 更多设置」面板：
/// 模糊音、候选字号、键盘高度、按键音与振动、键帽副标、外观、用户词库。
/// 纯 UIKit，改完直接写进 App Group，键盘和主 App 同时生效。
final class KeyboardSettingsView: UIView {

    var onChange: (() -> Void)?
    var onClose: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var userWordValue: UILabel?
    private var clearButton: UIButton?
    private var clearArmed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemBackground
        buildShell()
        buildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshInfo() {
        userWordValue?.text = "\(KeyboardPrefs.shared.userWordCount) 条"
    }

    // MARK: - 骨架

    private func buildShell() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .none

        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }

    private func buildRows() {
        let prefs = KeyboardPrefs.shared

        addHeader("输入设置")
        for rule in KeyboardPrefs.fuzzyRules {
            let sw = UISwitch()
            sw.isOn = prefs.fuzzyEnabled(rule.key)
            sw.accessibilityIdentifier = "fuzzy." + rule.key
            sw.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
            addRow("模糊音  " + rule.title, sw)
        }
        addNote("开启后，平翘舌、前后鼻音不分时也能召回正确的词，模糊候选排在精确候选之后。")

        addHeader("键盘与手感")
        let hintSwitch = switchFor("hints", prefs.keyHints)
        addRow("键帽上滑副标", hintSwitch)
        let clickSwitch = switchFor("click", prefs.keyClick)
        addRow("按键音", clickSwitch)
        let hapticSwitch = switchFor("haptic", prefs.haptic)
        addRow("按键振动", hapticSwitch)

        addHeader("候选字号")
        let sizeSegment = segment(["标准", "大", "超大"], prefs.candidateSize, "size")
        addRow("字号", sizeSegment)
        addNote("候选栏与「更多候选」宫格同时生效。")

        addHeader("键盘高度")
        let heightIndex = KeyboardPrefs.heights.firstIndex(of: prefs.keyboardHeight) ?? 1
        let heightSegment = segment(["矮", "标准", "高"], heightIndex, "height")
        addRow("高度", heightSegment)

        addHeader("外观")
        let themeIndex: Int
        switch prefs.theme {
        case "light": themeIndex = 1
        case "dark": themeIndex = 2
        default: themeIndex = 0
        }
        let themeSegment = segment(["跟随系统", "浅色", "深色"], themeIndex, "theme")
        addRow("主题", themeSegment)

        addHeader("词库")
        addInfo("内置拼音词库", PinyinEngine.shared.diagnostic)
        let (infoView, valueLabel) = infoRow("用户调频词条")
        stack.addArrangedSubview(infoView)
        userWordValue = valueLabel
        refreshInfo()

        let clear = UIButton(type: .system)
        clear.setTitle("清空用户调频词库", for: .normal)
        clear.titleLabel?.font = .systemFont(ofSize: 14)
        clear.setTitleColor(.systemRed, for: .normal)
        clear.contentHorizontalAlignment = .left
        clear.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton = clear
        let clearRow = UIView()
        clearRow.translatesAutoresizingMaskIntoConstraints = false
        clearRow.addSubview(clear)
        clear.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clear.leadingAnchor.constraint(equalTo: clearRow.leadingAnchor, constant: 12),
            clear.trailingAnchor.constraint(equalTo: clearRow.trailingAnchor, constant: -12),
            clear.topAnchor.constraint(equalTo: clearRow.topAnchor),
            clear.bottomAnchor.constraint(equalTo: clearRow.bottomAnchor),
            clearRow.heightAnchor.constraint(equalToConstant: 40),
        ])
        stack.addArrangedSubview(clearRow)

        addHeader("关于")
        addInfo("版本", "0.2.1 (build 13)")
        addNote("词库 710,935 条全拼 / 简拼索引，来源 jieba、pinyin-data、pypinyin，均为 MIT。\n纯 Swift / UIKit 实现，键盘扩展不引入任何第三方 framework。\n剪贴板记录库在键盘可见时自动采集，需要「完全访问」。")
        addNote("双拼、滑行输入、语音与手写暂未内置：它们需要独立的输入码层与系统权限，本版优先把拼音主链路做扎实。")

        let close = UIButton(type: .system)
        close.setTitle("返回键盘", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let closeRow = UIView()
        closeRow.translatesAutoresizingMaskIntoConstraints = false
        closeRow.addSubview(close)
        close.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            close.centerXAnchor.constraint(equalTo: closeRow.centerXAnchor),
            close.centerYAnchor.constraint(equalTo: closeRow.centerYAnchor),
            closeRow.heightAnchor.constraint(equalToConstant: 46),
        ])
        stack.addArrangedSubview(closeRow)
    }

    // MARK: - 行构造

    private func switchFor(_ key: String, _ value: Bool) -> UISwitch {
        let sw = UISwitch()
        sw.isOn = value
        sw.accessibilityIdentifier = key
        sw.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        return sw
    }

    private func segment(_ items: [String], _ selected: Int, _ key: String) -> UISegmentedControl {
        let seg = UISegmentedControl(items: items)
        seg.selectedSegmentIndex = selected
        seg.accessibilityIdentifier = key
        seg.selectedSegmentTintColor = .systemBlue
        seg.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        return seg
    }

    private func addRow(_ title: String, _ control: UIView) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 38),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -8),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        stack.addArrangedSubview(container)
    }

    private func infoRow(_ title: String) -> (UIView, UILabel) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        let value = UILabel()
        value.font = .systemFont(ofSize: 13)
        value.textColor = .secondaryLabel
        value.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(value)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            value.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            value.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return (container, value)
    }

    private func addInfo(_ title: String, _ value: String) {
        let (view, label) = infoRow(title)
        label.text = value
        stack.addArrangedSubview(view)
    }

    private func addHeader(_ title: String) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        stack.addArrangedSubview(container)
    }

    private func addNote(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        stack.addArrangedSubview(container)
    }

    // MARK: - 事件

    @objc private func switchChanged(_ sender: UISwitch) {
        let key = sender.accessibilityIdentifier ?? ""
        let prefs = KeyboardPrefs.shared
        if key.hasPrefix("fuzzy.") {
            prefs.setFuzzy(String(key.dropFirst("fuzzy.".count)), sender.isOn)
        } else if key == "hints" {
            prefs.keyHints = sender.isOn
        } else if key == "click" {
            prefs.keyClick = sender.isOn
        } else if key == "haptic" {
            prefs.haptic = sender.isOn
        }
        onChange?()
    }

    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        let key = sender.accessibilityIdentifier ?? ""
        let index = sender.selectedSegmentIndex
        let prefs = KeyboardPrefs.shared
        if key == "size" {
            prefs.candidateSize = index
        } else if key == "height" {
            if index >= 0, index < KeyboardPrefs.heights.count {
                prefs.keyboardHeight = KeyboardPrefs.heights[index]
            }
        } else if key == "theme" {
            prefs.theme = ["system", "light", "dark"][max(0, min(index, 2))]
        }
        onChange?()
    }

    @objc private func clearTapped() {
        if !clearArmed {
            clearArmed = true
            clearButton?.setTitle("再点一次确认清空", for: .normal)
            return
        }
        KeyboardPrefs.shared.clearUserDict()
        clearArmed = false
        clearButton?.setTitle("清空用户调频词库", for: .normal)
        refreshInfo()
        onChange?()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}

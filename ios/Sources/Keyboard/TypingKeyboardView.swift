import UIKit

/// 拼音键盘 UI：候选栏 + 系统式 QWERTY / 数字符号页。
///
/// 布局按 iOS 系统键盘的键宽比例来排：
///   第 1 行  10 个字母等宽
///   第 2 行  9 个字母，左右各留半个键宽
///   第 3 行  ⇧(1.5) + 7 个字母 + ⌫(1.5)
///   第 4 行  123 / 中英 / 🌐 / 空格(4.4) / 换行
/// 键宽用权重算 frame，不用 UIStackView.fillEqually。上一版就是 fillEqually
/// 把功能键和字母键拉成同一宽度、又把空格挤成 1/5 屏宽，看起来才那么诡异。
/// 全程纯 UIKit、零第三方依赖，键盘扩展不需要任何额外 framework。
final class TypingKeyboardView: UIView {

    weak var controller: KeyboardViewController?

    private enum Page {
        case letters
        case numbers
    }

    private enum KeyKind {
        case character(String)
        case punctuation(String)
        case shift
        case delete
        case page
        case language
        case next
        case space
        case enter
    }

    private struct KeySpec {
        let title: String
        let kind: KeyKind?          // nil = 透明占位，用于第二行左右半键留白
        let weight: CGFloat
        let function: Bool
        let size: CGFloat
    }

    private final class KeyButton: UIButton {
        var kind: KeyKind?
        var baseColor: UIColor = .clear
        var pressedColor: UIColor = .clear
        override var isHighlighted: Bool {
            didSet { backgroundColor = isHighlighted ? pressedColor : baseColor }
        }
    }

    /// 一行键：按权重分配 frame，避免 UIStackView 把功能键和字母键拉平。
    private final class KeyRow: UIView {
        var weights: [CGFloat] = []
        var items: [UIView] = []
        private let gap: CGFloat = 6
        private let side: CGFloat = 3

        override func layoutSubviews() {
            super.layoutSubviews()
            guard items.count == weights.count, !items.isEmpty else { return }
            let totalWeight = weights.reduce(0, +)
            guard totalWeight > 0 else { return }
            let usable = bounds.width - side * 2 - gap * CGFloat(items.count - 1)
            var x = side
            for (index, item) in items.enumerated() {
                let width = usable * weights[index] / totalWeight
                item.frame = CGRect(x: x, y: 0, width: width, height: bounds.height).integral
                // 预置 shadowPath，避开 40 个键帽同时离屏渲染。
                if let button = item as? KeyButton {
                    button.layer.shadowPath = UIBezierPath(
                        roundedRect: button.bounds, cornerRadius: 5
                    ).cgPath
                }
                x += width + gap
            }
        }
    }

    private let candidateBar = UIView()
    private let composingLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let candidateScroll = UIScrollView()
    private let candidateStack = UIStackView()
    private let keysStack = UIStackView()

    private let engine = PinyinEngine.shared
    private var page: Page = .letters
    private var shifted = false
    private var chineseMode = true

    private static let letterRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    private static let numberTop = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let chinesePunctuation = ["。", "？", "！", "、", "：", "；", "（", "）", "…", "「"]
    private static let latinPunctuation = [",", ".", "?", "!", "'", "+", "="]

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        rebuild()
        refreshCandidates()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 外观

    /// 浅色：字母键白、功能键系统灰；深色：两级深灰。随系统外观自动切换。
    private static func keyBase(_ function: Bool) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return function ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.32, alpha: 1)
            }
            return function
                ? UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
                : .white
        }
    }

    private static func keyPressed(_ function: Bool) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .dark { return UIColor(white: 0.50, alpha: 1) }
            return function ? .white : UIColor(white: 0.88, alpha: 1)
        }
    }

    // MARK: - 布局

    private func buildUI() {
        backgroundColor = .clear

        composingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        composingLabel.textColor = .systemBlue
        composingLabel.lineBreakMode = .byTruncatingHead
        composingLabel.translatesAutoresizingMaskIntoConstraints = false

        clearButton.setTitle("×", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 20)
        clearButton.setTitleColor(.secondaryLabel, for: .normal)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.alwaysBounceHorizontal = true
        candidateScroll.translatesAutoresizingMaskIntoConstraints = false

        candidateStack.axis = .horizontal
        candidateStack.alignment = .fill
        candidateStack.spacing = 0
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScroll.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor),
        ])

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let hairline = UIView()
        hairline.backgroundColor = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false

        candidateBar.addSubview(composingLabel)
        candidateBar.addSubview(divider)
        candidateBar.addSubview(candidateScroll)
        candidateBar.addSubview(clearButton)
        candidateBar.addSubview(hairline)
        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            composingLabel.leadingAnchor.constraint(equalTo: candidateBar.leadingAnchor, constant: 6),
            composingLabel.centerYAnchor.constraint(equalTo: candidateBar.centerYAnchor),
            composingLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 96),

            divider.leadingAnchor.constraint(equalTo: composingLabel.trailingAnchor, constant: 6),
            divider.centerYAnchor.constraint(equalTo: candidateBar.centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 22),

            clearButton.trailingAnchor.constraint(equalTo: candidateBar.trailingAnchor, constant: -2),
            clearButton.centerYAnchor.constraint(equalTo: candidateBar.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 26),
            clearButton.heightAnchor.constraint(equalToConstant: 34),

            candidateScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 4),
            candidateScroll.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -2),
            candidateScroll.topAnchor.constraint(equalTo: candidateBar.topAnchor),
            candidateScroll.bottomAnchor.constraint(equalTo: candidateBar.bottomAnchor),

            hairline.leadingAnchor.constraint(equalTo: candidateBar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: candidateBar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        keysStack.axis = .vertical
        keysStack.distribution = .fillEqually
        keysStack.spacing = 8
        keysStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(candidateBar)
        addSubview(keysStack)
        NSLayoutConstraint.activate([
            candidateBar.topAnchor.constraint(equalTo: topAnchor),
            candidateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 42),

            keysStack.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 6),
            keysStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            keysStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            keysStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - 候选栏

    private func refreshCandidates() {
        for sub in candidateStack.arrangedSubviews {
            candidateStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        let list = engine.candidates
        if list.isEmpty {
            let hint = UILabel()
            hint.font = .systemFont(ofSize: 13)
            hint.textColor = .tertiaryLabel
            hint.text = chineseMode
                ? (engine.isEmpty ? "拼音输入 · 词库 \(engine.diagnostic)" : "暂无候选")
                : "英文直输"
            hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
            candidateStack.addArrangedSubview(hint)
        } else {
            for (index, item) in list.enumerated() {
                let button = UIButton(type: .system)
                button.setTitle(item.word + (item.needsContinuation ? " ›" : ""), for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 17)
                button.setTitleColor(.label, for: .normal)
                button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
                button.tag = index
                button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
                candidateStack.addArrangedSubview(button)

                if index < list.count - 1 {
                    let sep = UIView()
                    sep.backgroundColor = .separator
                    sep.translatesAutoresizingMaskIntoConstraints = false
                    sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                    candidateStack.addArrangedSubview(sep)
                }
            }
        }
        composingLabel.text = chineseMode ? engine.displayText : "EN"
        candidateScroll.setContentOffset(.zero, animated: false)
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard let word = engine.commit(at: sender.tag) else { return }
        controller?.textDocumentProxy.insertText(word)
        refreshCandidates()
    }

    @objc private func clearTapped() {
        engine.clear()
        refreshCandidates()
    }

    // MARK: - 键区

    private func rebuild() {
        for sub in keysStack.arrangedSubviews {
            keysStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        for specs in rowSpecs() {
            let row = KeyRow()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.weights = specs.map { $0.weight }
            row.items = specs.map { makeItem($0) }
            for item in row.items { row.addSubview(item) }
            keysStack.addArrangedSubview(row)
        }
    }

    private func rowSpecs() -> [[KeySpec]] {
        var result: [[KeySpec]] = []

        if page == .letters {
            // 第 1 行：10 个字母，等宽。
            result.append(Self.letterRows[0].map {
                KeySpec(title: shifted ? $0.uppercased() : $0,
                        kind: .character($0), weight: 1, function: false, size: 22)
            })

            // 第 2 行：左右各半键留白 + 9 个字母，键宽与第 1 行一致。
            var second: [KeySpec] = [KeySpec(title: "", kind: nil, weight: 0.5, function: false, size: 0)]
            second.append(contentsOf: Self.letterRows[1].map {
                KeySpec(title: shifted ? $0.uppercased() : $0,
                        kind: .character($0), weight: 1, function: false, size: 22)
            })
            second.append(KeySpec(title: "", kind: nil, weight: 0.5, function: false, size: 0))
            result.append(second)

            // 第 3 行：⇧ + 7 字母 + ⌫，功能键各 1.5 键宽，总权重仍是 10。
            var third: [KeySpec] = [KeySpec(title: "⇧", kind: .shift, weight: 1.5, function: true, size: 20)]
            third.append(contentsOf: Self.letterRows[2].map {
                KeySpec(title: shifted ? $0.uppercased() : $0,
                        kind: .character($0), weight: 1, function: false, size: 22)
            })
            third.append(KeySpec(title: "⌫", kind: .delete, weight: 1.5, function: true, size: 20))
            result.append(third)
        } else {
            result.append(Self.numberTop.map {
                KeySpec(title: $0, kind: .character($0), weight: 1, function: false, size: 22)
            })
            result.append(Self.chinesePunctuation.map {
                KeySpec(title: $0, kind: .punctuation($0), weight: 1, function: false, size: 20)
            })
            var third: [KeySpec] = [KeySpec(title: "，", kind: .punctuation("，"), weight: 1.5, function: true, size: 20)]
            third.append(contentsOf: Self.latinPunctuation.map {
                KeySpec(title: $0, kind: .punctuation($0), weight: 1, function: false, size: 20)
            })
            third.append(KeySpec(title: "⌫", kind: .delete, weight: 1.5, function: true, size: 20))
            result.append(third)
        }

        // 第 4 行：空格占 4.4 键宽，不再被平均分成 1/5。
        result.append([
            KeySpec(title: page == .letters ? "123" : "ABC", kind: .page, weight: 1.4, function: true, size: 15),
            KeySpec(title: chineseMode ? "中" : "英", kind: .language, weight: 1, function: true, size: 15),
            KeySpec(title: "🌐", kind: .next, weight: 1, function: true, size: 19),
            KeySpec(title: "空格", kind: .space, weight: 4.4, function: false, size: 15),
            KeySpec(title: "换行", kind: .enter, weight: 2.2, function: true, size: 15),
        ])
        return result
    }

    private func makeItem(_ spec: KeySpec) -> UIView {
        guard let kind = spec.kind else {
            let spacer = UIView()
            spacer.autoresizingMask = []
            spacer.isUserInteractionEnabled = false
            return spacer
        }

        let button = KeyButton(type: .custom)
        button.autoresizingMask = []
        button.kind = kind
        button.setTitle(spec.title, for: .normal)
        button.setTitleColor(isSpace(kind) ? .secondaryLabel : .label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: spec.size)
        button.baseColor = Self.keyBase(spec.function)
        button.pressedColor = Self.keyPressed(spec.function)
        button.backgroundColor = button.baseColor
        button.layer.cornerRadius = 5
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0
        button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        return button
    }

    private func isSpace(_ kind: KeyKind) -> Bool {
        if case .space = kind { return true }
        return false
    }

    private func commitFirst() {
        if let word = engine.commit(at: 0) {
            controller?.textDocumentProxy.insertText(word)
        } else {
            let raw = engine.composing
            engine.clear()
            controller?.textDocumentProxy.insertText(raw)
        }
        refreshCandidates()
    }

    private func flushComposing() {
        if !engine.isEmpty {
            engine.clear()
            refreshCandidates()
        }
    }

    // MARK: - 按键

    @objc private func tapped(_ sender: KeyButton) {
        guard let kind = sender.kind, let proxy = controller?.textDocumentProxy else { return }
        switch kind {
        case .character(let value):
            if chineseMode && page == .letters {
                engine.append(value.lowercased())
                refreshCandidates()
            } else {
                flushComposing()
                proxy.insertText((page == .letters && shifted) ? value.uppercased() : value)
                if shifted {
                    shifted = false
                    rebuild()
                }
            }
        case .punctuation(let value):
            flushComposing()
            proxy.insertText(value)
        case .delete:
            if !engine.isEmpty {
                engine.delete()
                refreshCandidates()
            } else {
                proxy.deleteBackward()
            }
        case .space:
            if !engine.isEmpty {
                commitFirst()
            } else {
                proxy.insertText(" ")
            }
        case .enter:
            if !engine.isEmpty {
                commitFirst()
            } else {
                proxy.insertText("\n")
            }
        case .shift:
            shifted.toggle()
            rebuild()
        case .language:
            chineseMode.toggle()
            shifted = false
            engine.clear()
            rebuild()
            refreshCandidates()
        case .page:
            page = (page == .letters) ? .numbers : .letters
            shifted = false
            flushComposing()
            rebuild()
            refreshCandidates()
        case .next:
            flushComposing()
            controller?.switchToNextKeyboard()
        }
    }
}

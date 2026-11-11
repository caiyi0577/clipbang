import UIKit

/// 拼音键盘：候选栏 + 拼音缓冲 + QWERTY / 数字符号页。
/// 中文模式敲字母走 PinyinEngine，英文模式直接上屏；全程纯 UIKit、零第三方依赖。
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
        case paste
        case next
        case space
        case enter
    }

    private final class KeyButton: UIButton {
        var kind: KeyKind?
    }

    private let candidateBar = UIScrollView()
    private let candidateStack = UIStackView()
    private let composingLabel = UILabel()
    private let langButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
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

    private static let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "¥", "&", "\"", "."],
        [",", "?", "!", "'", "+", "=", "%"],
    ]

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

    // MARK: - 布局

    private func buildUI() {
        candidateBar.showsHorizontalScrollIndicator = false
        candidateBar.backgroundColor = .systemBackground
        candidateBar.layer.cornerRadius = 6
        candidateBar.translatesAutoresizingMaskIntoConstraints = false

        candidateStack.axis = .horizontal
        candidateStack.alignment = .center
        candidateStack.spacing = 4
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateBar.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.leadingAnchor, constant: 4),
            candidateStack.trailingAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.trailingAnchor, constant: -4),
            candidateStack.topAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateBar.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateBar.frameLayoutGuide.heightAnchor),
        ])

        composingLabel.font = .systemFont(ofSize: 12)
        composingLabel.textColor = .secondaryLabel
        composingLabel.lineBreakMode = .byTruncatingTail

        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 12)
        clearButton.widthAnchor.constraint(equalToConstant: 38).isActive = true
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        langButton.setTitle("中", for: .normal)
        langButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        langButton.backgroundColor = .systemBlue
        langButton.setTitleColor(.white, for: .normal)
        langButton.layer.cornerRadius = 5
        langButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        langButton.addTarget(self, action: #selector(langTapped), for: .touchUpInside)

        let composingBar = UIStackView(arrangedSubviews: [composingLabel, clearButton, langButton])
        composingBar.axis = .horizontal
        composingBar.spacing = 6
        composingBar.alignment = .center
        composingBar.translatesAutoresizingMaskIntoConstraints = false

        keysStack.axis = .vertical
        keysStack.distribution = .fillEqually
        keysStack.spacing = 7
        keysStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(candidateBar)
        addSubview(composingBar)
        addSubview(keysStack)
        NSLayoutConstraint.activate([
            candidateBar.topAnchor.constraint(equalTo: topAnchor),
            candidateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 40),

            composingBar.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 4),
            composingBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            composingBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            composingBar.heightAnchor.constraint(equalToConstant: 24),

            keysStack.topAnchor.constraint(equalTo: composingBar.bottomAnchor, constant: 4),
            keysStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            keysStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
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
                ? (engine.isEmpty ? "敲字母开始拼音输入 · 词库 \(engine.diagnostic)" : "暂无候选，继续输入或清空")
                : "英文直输模式"
            candidateStack.addArrangedSubview(hint)
        } else {
            for (index, item) in list.enumerated() {
                let button = UIButton(type: .system)
                button.setTitle(item.word + (item.needsContinuation ? " ›" : ""), for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 17)
                button.setTitleColor(.label, for: .normal)
                button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
                button.tag = index
                button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
                candidateStack.addArrangedSubview(button)
            }
        }
        composingLabel.text = chineseMode ? engine.displayText : "英文直输 · 点「中」回拼音"
        candidateBar.setContentOffset(.zero, animated: false)
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

    @objc private func langTapped() {
        chineseMode.toggle()
        engine.clear()
        langButton.setTitle(chineseMode ? "中" : "英", for: .normal)
        rebuild()
        refreshCandidates()
    }

    // MARK: - 键区

    private func rebuild() {
        for sub in keysStack.arrangedSubviews {
            keysStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        let rows = page == .letters ? Self.letterRows : Self.numberRows

        for (index, keys) in rows.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 5

            if index == 2 && page == .letters {
                if chineseMode {
                    row.addArrangedSubview(makeButton(title: "，", kind: .punctuation("，")))
                } else {
                    let shift = makeButton(title: shifted ? "大写" : "小写", kind: .shift)
                    shift.backgroundColor = shifted ? UIColor.systemBlue : UIColor.systemBackground
                    row.addArrangedSubview(shift)
                }
            }

            for key in keys {
                let title = (page == .letters && shifted) ? key.uppercased() : key
                row.addArrangedSubview(makeButton(title: title, kind: .character(key)))
            }

            if index == 2 {
                row.addArrangedSubview(makeButton(title: "删除", kind: .delete))
            }
            keysStack.addArrangedSubview(row)
        }

        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.distribution = .fillEqually
        bottom.spacing = 5
        bottom.addArrangedSubview(makeButton(title: page == .letters ? "123" : "ABC", kind: .page))
        bottom.addArrangedSubview(makeButton(title: "粘贴", kind: .paste))
        bottom.addArrangedSubview(makeButton(title: "切换", kind: .next))
        bottom.addArrangedSubview(makeButton(title: "空格", kind: .space))
        bottom.addArrangedSubview(makeButton(title: "换行", kind: .enter))
        keysStack.addArrangedSubview(bottom)
    }

    private func makeButton(title: String, kind: KeyKind) -> KeyButton {
        let button = KeyButton(type: .custom)
        button.kind = kind
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: title.count > 2 ? 12 : 16)
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 5
        button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        return button
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

    @objc private func tapped(_ sender: KeyButton) {
        guard let kind = sender.kind, let proxy = controller?.textDocumentProxy else { return }
        switch kind {
        case .character(let value):
            if chineseMode && page == .letters {
                engine.append(value)
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
        case .page:
            page = (page == .letters) ? .numbers : .letters
            shifted = false
            flushComposing()
            rebuild()
        case .paste:
            flushComposing()
            // 用户手势上下文，一定能读到剪贴板内容，顺便入库。
            if let text = UIPasteboard.general.string, !text.isEmpty {
                proxy.insertText(text)
                _ = ClipStore.shared.save(text)
            }
        case .next:
            flushComposing()
            controller?.switchToNextKeyboard()
        }
    }
}

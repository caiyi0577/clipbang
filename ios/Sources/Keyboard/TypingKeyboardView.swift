import UIKit

/// 纯 UIKit 手搓的打字键盘：字母页 + 数字/符号页、一次性 shift、删除、空格、换行、粘贴。
/// 不引任何第三方依赖，键盘扩展只有 50~70MB 内存预算。
final class TypingKeyboardView: UIView {

    weak var controller: KeyboardViewController?

    private enum Page {
        case letters
        case numbers
    }

    private enum KeyKind {
        case character(String)
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

    private let root = UIStackView()
    private var page: Page = .letters
    private var shifted = false

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

        root.axis = .vertical
        root.distribution = .fillEqually
        root.spacing = 7
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuild() {
        for sub in root.arrangedSubviews {
            root.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        let rows = page == .letters ? Self.letterRows : Self.numberRows

        for (index, keys) in rows.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 5

            if index == 2 && page == .letters {
                let shift = makeButton(title: shifted ? "大写" : "小写", kind: .shift)
                shift.backgroundColor = shifted ? UIColor.systemBlue : UIColor.systemBackground
                row.addArrangedSubview(shift)
            }

            for key in keys {
                let title = (page == .letters && shifted) ? key.uppercased() : key
                row.addArrangedSubview(makeButton(title: title, kind: .character(key)))
            }

            if index == 2 {
                row.addArrangedSubview(makeButton(title: "删除", kind: .delete))
            }
            root.addArrangedSubview(row)
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
        root.addArrangedSubview(bottom)
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

    @objc private func tapped(_ sender: KeyButton) {
        guard let kind = sender.kind, let proxy = controller?.textDocumentProxy else { return }
        switch kind {
        case .character(let value):
            proxy.insertText((page == .letters && shifted) ? value.uppercased() : value)
            if shifted {
                shifted = false
                rebuild()
            }
        case .delete:
            proxy.deleteBackward()
        case .space:
            proxy.insertText(" ")
        case .enter:
            proxy.insertText("\n")
        case .shift:
            shifted.toggle()
            rebuild()
        case .page:
            page = (page == .letters) ? .numbers : .letters
            shifted = false
            rebuild()
        case .paste:
            // 用户手势上下文，一定能读到剪贴板内容，顺便入库。
            if let text = UIPasteboard.general.string, !text.isEmpty {
                proxy.insertText(text)
                _ = ClipStore.shared.save(text)
            }
        case .next:
            controller?.switchToNextKeyboard()
        }
    }
}

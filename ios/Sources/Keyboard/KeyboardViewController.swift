import UIKit

/// 骨架版键盘。这一步只验证扩展能被签名、能出现在键盘列表、能弹出。
/// 采集和炸开逻辑等链路确认之后再往里填。
final class KeyboardViewController: UIInputViewController {

    private let panelHeight: CGFloat = 280

    override func viewDidLoad() {
        super.viewDidLoad()
        buildPanel()
    }

    private func buildPanel() {
        view.backgroundColor = UIColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1)

        let heightLock = view.heightAnchor.constraint(equalToConstant: panelHeight)
        heightLock.priority = .defaultHigh
        heightLock.isActive = true

        let title = UILabel()
        title.text = "剪贴炸"
        title.font = .systemFont(ofSize: 16, weight: .medium)
        title.textColor = UIColor(white: 0.2, alpha: 1)

        let subtitle = UILabel()
        subtitle.text = "骨架已跑通，接下来接剪贴板"
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = UIColor(white: 0.55, alpha: 1)

        let head = UIStackView(arrangedSubviews: [title, subtitle])
        head.axis = .vertical
        head.spacing = 4

        let sample = UILabel()
        sample.text = "长按这里试试系统键盘的样子"
        sample.font = .systemFont(ofSize: 15)
        sample.textColor = UIColor(white: 0.35, alpha: 1)
        sample.numberOfLines = 0
        sample.textAlignment = .center

        let box = UIView()
        box.backgroundColor = .white
        box.layer.cornerRadius = 10
        box.layer.borderWidth = 0.8
        box.layer.borderColor = UIColor(white: 0.89, alpha: 1).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(sample)
        sample.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sample.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            sample.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            sample.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor, constant: 12),
            sample.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
        ])

        let globe = UIButton(type: .system)
        globe.setTitle("切换键盘", for: .normal)
        globe.titleLabel?.font = .systemFont(ofSize: 14)
        globe.addTarget(self, action: #selector(handleNextKeyboard), for: .touchUpInside)

        let dismiss = UIButton(type: .system)
        dismiss.setTitle("收起", for: .normal)
        dismiss.titleLabel?.font = .systemFont(ofSize: 14)
        dismiss.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [globe, dismiss])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 12

        let root = UIStackView(arrangedSubviews: [head, box, buttons])
        root.axis = .vertical
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            box.heightAnchor.constraint(equalToConstant: 110),
            buttons.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func handleNextKeyboard() {
        advanceToNextInputMode()
    }

    @objc private func handleDismiss() {
        dismissKeyboard()
    }
}

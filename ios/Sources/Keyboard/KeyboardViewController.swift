import UIKit

/// 键盘负责采集：iOS 16 之后主 App 在后台读不到剪贴板文字，
/// 但键盘是用户主动唤起的、开了完全访问就能读。所以每次键盘出现
/// 都把当前剪贴板写进共享库，历史随使用逐步积累。
/// 主 App 前台轮询仍然保留，用来补上在 App 里操作时的那部分记录。
final class KeyboardViewController: UIInputViewController {

    private let panelHeight: CGFloat = 280
    private var items: [ClipItem] = []
    private var captureNote = "键盘尚未采集"

    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildPanel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureCurrent()
        reload()
    }

    private func captureCurrent() {
        let board = UIPasteboard.general
        guard let text = board.string, !text.isEmpty else {
            captureNote = "键盘读不到剪贴板 · 检查完全访问"
            return
        }
        let preview = text
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(12)
        captureNote = ClipStore.shared.save(text)
            ? "键盘已采集：\(preview)"
            : "键盘入库失败"
    }

    private func reload() {
        items = Array(ClipStore.shared.all().prefix(15))
        let group = ClipStore.shared.groupAvailable ? "共享可用" : "共享不可用"
        let count = items.isEmpty ? "还没有记录" : "共 \(items.count) 条"
        statusLabel.text = "\(count) · \(group) · \(captureNote)"
        tableView.reloadData()
    }

    private func buildPanel() {
        view.backgroundColor = UIColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1)

        let heightLock = view.heightAnchor.constraint(equalToConstant: panelHeight)
        heightLock.priority = .defaultHigh
        heightLock.isActive = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = UIColor(white: 0.42, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.rowHeight = 44
        tableView.tableFooterView = UIView()

        let globe = UIButton(type: .system)
        globe.setTitle("切换键盘", for: .normal)
        globe.titleLabel?.font = .systemFont(ofSize: 14)
        globe.addTarget(self, action: #selector(handleNextKeyboard), for: .touchUpInside)

        let refresh = UIButton(type: .system)
        refresh.setTitle("刷新", for: .normal)
        refresh.titleLabel?.font = .systemFont(ofSize: 14)
        refresh.addTarget(self, action: #selector(handleRefresh), for: .touchUpInside)

        let dismiss = UIButton(type: .system)
        dismiss.setTitle("收起", for: .normal)
        dismiss.titleLabel?.font = .systemFont(ofSize: 14)
        dismiss.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [globe, refresh, dismiss])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually

        let root = UIStackView(arrangedSubviews: [statusLabel, tableView, buttons])
        root.axis = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            statusLabel.heightAnchor.constraint(equalToConstant: 32),
            buttons.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    @objc private func handleNextKeyboard() { advanceToNextInputMode() }
    @objc private func handleDismiss() { dismissKeyboard() }
    @objc private func handleRefresh() { captureCurrent(); reload() }

    private func relative(_ timestamp: Double) -> String {
        let seconds = Date().timeIntervalSince1970 - timestamp
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }
}

extension KeyboardViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "clip")
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "clip")
        }
        guard let cell else { return UITableViewCell() }
        let item = items[indexPath.row]

        cell.textLabel?.text = item.text.replacingOccurrences(of: "\n", with: " ")
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.textLabel?.textColor = UIColor(white: 0.16, alpha: 1)
        cell.detailTextLabel?.text = relative(item.createdAt)
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)
        cell.backgroundColor = .white
        cell.selectionStyle = .gray
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        textDocumentProxy.insertText(items[indexPath.row].text)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

import UIKit

/// 键盘第一版：读出主 App 采集到的记录，点一条就插进当前输入框。
/// 炸开选词等交互留到采集链路确认之后再做。
final class KeyboardViewController: UIInputViewController {

    private let panelHeight: CGFloat = 280
    private var items: [ClipItem] = []

    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildPanel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        items = Array(ClipStore.shared.all().prefix(15))
        let group = ClipStore.shared.groupAvailable ? "共享可用" : "共享不可用"
        statusLabel.text = items.isEmpty
            ? "还没有记录 · \(group) · 复制点东西试试"
            : "共 \(items.count) 条 · \(group) · 点一条插入"
        tableView.reloadData()
    }

    private func buildPanel() {
        view.backgroundColor = UIColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1)

        let heightLock = view.heightAnchor.constraint(equalToConstant: panelHeight)
        heightLock.priority = .defaultHigh
        heightLock.isActive = true

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = UIColor(white: 0.42, alpha: 1)
        statusLabel.textAlignment = .center

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
            statusLabel.heightAnchor.constraint(equalToConstant: 20),
            buttons.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    @objc private func handleNextKeyboard() { advanceToNextInputMode() }
    @objc private func handleDismiss() { dismissKeyboard() }
    @objc private func handleRefresh() { reload() }

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

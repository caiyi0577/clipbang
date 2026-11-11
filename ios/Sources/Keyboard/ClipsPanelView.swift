import UIKit

/// 剪贴板记录库面板：点一条直接插入宿主输入框。
final class ClipsPanelView: UIView, UITableViewDataSource, UITableViewDelegate {

    weak var controller: KeyboardViewController?

    private let table = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var items: [ClipItem] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        table.dataSource = self
        table.delegate = self
        table.rowHeight = 50
        table.backgroundColor = .clear
        table.tableFooterView = UIView()
        table.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = "还没有记录。复制文字后，键盘会自动收进来。"
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 2
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(table)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: topAnchor),
            table.leadingAnchor.constraint(equalTo: leadingAnchor),
            table.trailingAnchor.constraint(equalTo: trailingAnchor),
            table.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItems(_ newItems: [ClipItem]) {
        items = newItems
        emptyLabel.isHidden = !items.isEmpty
        table.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "clip")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "clip")
        let item = items[indexPath.row]
        cell.textLabel?.text = item.text.replacingOccurrences(of: "\n", with: " ")
        cell.textLabel?.font = .systemFont(ofSize: 14)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = relative(item.createdAt)
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.backgroundColor = .secondarySystemBackground
        cell.selectionStyle = .gray
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        controller?.insertClip(items[indexPath.row].text)
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func relative(_ timestamp: Double) -> String {
        let seconds = Date().timeIntervalSince1970 - timestamp
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }
}

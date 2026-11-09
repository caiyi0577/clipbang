import Foundation

struct ClipItem: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var createdAt: Double
}

/// 主 App 和键盘扩展共用的存储。
/// App Group 的 ID 必须与签名描述文件里 application-groups 列出的一个一致。
final class ClipStore {

    static let shared = ClipStore()

    static let groupId = "group.48bf5183109e5584.1"
    private let key = "clips.v1"
    private let limit = 99

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: ClipStore.groupId) ?? .standard
    }

    /// App Group 是否真的可用。不可用时会退回各自进程的本地存储，
    /// 键盘就读不到主 App 采集的内容。
    var groupAvailable: Bool {
        UserDefaults(suiteName: ClipStore.groupId) != nil
    }

    func all() -> [ClipItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([ClipItem].self, from: data) else {
            return []
        }
        return items
    }

    func save(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        var items = all()
        // 同一条内容不重复入库，只把它提到最前
        items.removeAll { $0.text == text }
        items.insert(
            ClipItem(id: UUID().uuidString, text: text, createdAt: Date().timeIntervalSince1970),
            at: 0
        )
        if items.count > limit { items = Array(items.prefix(limit)) }

        guard let data = try? JSONEncoder().encode(items) else { return false }
        defaults.set(data, forKey: key)
        defaults.synchronize()
        return true
    }

    func clear() {
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }
}

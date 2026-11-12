import UIKit

/// 键盘设置 + 用户调频词库。存在 App Group 里，主 App 和键盘扩展都能读。
/// 主流输入法的设置项在这里落一份最小可用实现：模糊音、键帽副标、按键音、
/// 候选字号、键盘高度、外观，以及选词次数带来的排序加权。
final class KeyboardPrefs {

    static let shared = KeyboardPrefs()

    private let defaults: UserDefaults
    private let prefix = "kb.v2."

    private init() {
        defaults = UserDefaults(suiteName: ClipStore.groupId) ?? .standard
    }

    // MARK: - 读写原语

    private func flag(_ key: String, fallback: Bool) -> Bool {
        guard let v = defaults.object(forKey: prefix + key) as? Bool else { return fallback }
        return v
    }

    private func setFlag(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: prefix + key)
        defaults.synchronize()
    }

    private func text(_ key: String, fallback: String) -> String {
        defaults.string(forKey: prefix + key) ?? fallback
    }

    private func setText(_ value: String, _ key: String) {
        defaults.set(value, forKey: prefix + key)
        defaults.synchronize()
    }

    private func number(_ key: String, fallback: Int) -> Int {
        guard let v = defaults.object(forKey: prefix + key) as? Int else { return fallback }
        return v
    }

    private func setNumber(_ value: Int, _ key: String) {
        defaults.set(value, forKey: prefix + key)
        defaults.synchronize()
    }

    // MARK: - 模糊音

    struct FuzzyRule {
        let key: String
        let title: String
        let from: String
        let to: String
        let initial: Bool   // true：声母，在音节开头替换；false：韵母，在串尾替换
    }

    /// 与主流输入法设置页里那排开关一一对应。变体是双向生成的：
    /// 平翘舌不分的人打 zongguo 要能出「中国」，打 zhongguo 也要能出「宗国」。
    static let fuzzyRules: [FuzzyRule] = [
        FuzzyRule(key: "zh_z", title: "zh ↔ z", from: "z", to: "zh", initial: true),
        FuzzyRule(key: "ch_c", title: "ch ↔ c", from: "c", to: "ch", initial: true),
        FuzzyRule(key: "sh_s", title: "sh ↔ s", from: "s", to: "sh", initial: true),
        FuzzyRule(key: "n_l", title: "n ↔ l", from: "n", to: "l", initial: true),
        FuzzyRule(key: "r_l", title: "r ↔ l", from: "r", to: "l", initial: true),
        FuzzyRule(key: "f_h", title: "f ↔ h", from: "f", to: "h", initial: true),
        FuzzyRule(key: "in_ing", title: "in ↔ ing", from: "in", to: "ing", initial: false),
        FuzzyRule(key: "en_eng", title: "en ↔ eng", from: "en", to: "eng", initial: false),
        FuzzyRule(key: "an_ang", title: "an ↔ ang", from: "an", to: "ang", initial: false),
    ]

    func fuzzyEnabled(_ key: String) -> Bool { flag("fuzzy." + key, fallback: false) }
    func setFuzzy(_ key: String, _ value: Bool) { setFlag(value, "fuzzy." + key) }

    var fuzzyAny: Bool {
        for rule in KeyboardPrefs.fuzzyRules where fuzzyEnabled(rule.key) { return true }
        return false
    }

    // MARK: - 键盘外观与手感

    var keyHints: Bool {
        get { flag("hints", fallback: true) }
        set { setFlag(newValue, "hints") }
    }

    var keyClick: Bool {
        get { flag("click", fallback: true) }
        set { setFlag(newValue, "click") }
    }

    var haptic: Bool {
        get { flag("haptic", fallback: false) }
        set { setFlag(newValue, "haptic") }
    }

    /// 候选字字号：0=标准 1=大 2=超大
    var candidateSize: Int {
        get { number("candSize", fallback: 0) }
        set { setNumber(newValue, "candSize") }
    }

    var candidateFont: CGFloat {
        switch candidateSize {
        case 1: return 19
        case 2: return 21
        default: return 17
        }
    }

    /// 键盘总高度（pt），三档。工具条 34 + 候选栏 40 + 四行键 + 间距。
    var keyboardHeight: Int {
        get { number("height", fallback: 288) }
        set { setNumber(newValue, "height") }
    }

    static let heights = [266, 288, 320]

    /// system / light / dark
    var theme: String {
        get { text("theme", fallback: "system") }
        set { setText(newValue, "theme") }
    }

    // MARK: - 用户调频

    private func freqKey(_ pinyin: String, _ word: String) -> String {
        pinyin + "\t" + word
    }

    private var freq: [String: Int] {
        (defaults.object(forKey: prefix + "freq") as? [String: Int]) ?? [:]
    }

    /// 选过几次就加权多少：每次 +800，最多累计 16 次。
    /// 上限够高才能压过词频 + 音节贴合度，让常用词真的浮上来；
    /// 又不会一次误选就把词永久顶死。
    func bonus(pinyin: String, word: String) -> Int {
        guard let n = freq[freqKey(pinyin, word)] else { return 0 }
        return min(n, 16) * 800
    }

    func note(pinyin: String, word: String) {
        guard !pinyin.isEmpty, !word.isEmpty else { return }
        var table = freq
        let key = freqKey(pinyin, word)
        table[key] = min((table[key] ?? 0) + 1, 999)
        defaults.set(table, forKey: prefix + "freq")
        defaults.synchronize()
    }

    var userWordCount: Int { freq.count }

    func clearUserDict() {
        defaults.removeObject(forKey: prefix + "freq")
        defaults.synchronize()
    }
}

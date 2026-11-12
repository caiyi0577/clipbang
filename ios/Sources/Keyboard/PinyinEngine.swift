import Foundation

/// 一个候选：word 是上屏文字，remaining 是选词后仍留在输入缓冲里的拼音。
/// 例如一口气敲 "nihaoma"，选「你好」时 remaining = "ma"，接着继续出候选。
/// key 是该词对应的拼音串，给用户调频做键（连打时是首词的拼音，不是整串）。
struct PinyinCandidate {
    let word: String
    let score: Int
    let remaining: String
    let key: String

    var needsContinuation: Bool { !remaining.isEmpty }
}

/// 纯 Swift 拼音引擎：不依赖任何第三方 SDK、不链接 librime。
/// 词库是构建期生成的二进制索引（71 万条），运行时 mmap + 二分。
///
/// 主流输入法的四件事这里都做了：
///   - 整词优先 + 连打续拼
///   - 模糊音（平翘舌 / 前后鼻音 / n l f h）变体召回
///   - 用户调频：选过的词按次数加权，存在 App Group
///   - 联想：上屏后用词库补全长词，再补内置搭配与通用虚词
final class PinyinEngine {

    static let shared = PinyinEngine()

    private let full: PinyinDictionary?
    private let hot: PinyinDictionary?

    private(set) var composing = ""
    private(set) var candidates: [PinyinCandidate] = []
    private(set) var suggestions: [String] = []

    var isEmpty: Bool { composing.isEmpty }
    var firstWord: String? { candidates.first?.word }

    var diagnostic: String {
        guard let f = full else { return "词库缺失" }
        return "\(f.entryCount)条"
    }

    private init() {
        full = PinyinDictionary(resource: "pinyin_full")
        hot = PinyinDictionary(resource: "pinyin_hot")
    }

    // MARK: - 输入缓冲

    func append(_ letter: String) {
        let lower = letter.lowercased()
        guard lower.count == 1, let ch = lower.first, ch >= "a", ch <= "z" else { return }
        guard composing.count < 24 else { return }
        suggestions = []
        composing += lower
        refresh()
    }

    func delete() {
        guard !composing.isEmpty else { return }
        composing.removeLast()
        refresh()
    }

    func clear() {
        composing = ""
        candidates = []
        suggestions = []
    }

    /// 上屏第 index 个候选，返回要插入的文字。
    @discardableResult
    func commit(at index: Int) -> String? {
        guard index >= 0, index < candidates.count else { return nil }
        let picked = candidates[index]
        KeyboardPrefs.shared.note(pinyin: picked.key, word: picked.word)
        composing = picked.remaining
        refresh()
        if composing.isEmpty { updateSuggestions(picked.word, pinyin: picked.key) }
        return picked.word
    }

    /// 上屏一条联想词。
    func commitSuggestion(_ word: String) {
        composing = ""
        refresh()
        updateSuggestions(word, pinyin: "")
    }

    /// 显示用的拼音串：按音节加空格，例如 "nihao" -> "ni hao"。
    var displayText: String {
        guard !composing.isEmpty else { return "" }
        let chars = Array(composing)
        var parts: [String] = []
        var start = 0
        for boundary in syllableBoundaries(composing) where boundary > start {
            let seg = String(Array(chars[start..<boundary]))
            if !seg.isEmpty {
                parts.append(seg)
                start = boundary
            }
        }
        if start < chars.count {
            parts.append(String(Array(chars[start..<chars.count])))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 候选生成

    private func refresh() {
        guard !composing.isEmpty else {
            candidates = []
            return
        }

        let prefs = KeyboardPrefs.shared

        // 整串候选永远排在连打候选前面，否则「你›hao」会压过「你好」。
        var seen = Set<String>()
        var primary: [PinyinCandidate] = []

        // 1) 高频表：全局词频 top 4 万，保证单字母/两字母输入也有好词。
        for hit in hot?.lookup(prefix: composing, limit: 40, scanLimit: 40000) ?? [] {
            guard seen.insert(hit.word).inserted else { continue }
            primary.append(PinyinCandidate(
                word: hit.word,
                score: hit.score + 5000 + closeness(hit.key, composing)
                    + prefs.bonus(pinyin: hit.key, word: hit.word),
                remaining: "",
                key: hit.key
            ))
        }

        // 2) 全量表：长尾词、成语、专名都在这里。
        for hit in full?.lookup(prefix: composing, limit: 180, scanLimit: 16000) ?? [] {
            guard seen.insert(hit.word).inserted else { continue }
            primary.append(PinyinCandidate(
                word: hit.word,
                score: hit.score + closeness(hit.key, composing)
                    + prefs.bonus(pinyin: hit.key, word: hit.word),
                remaining: "",
                key: hit.key
            ))
        }

        // 3) 模糊音：把整串按规则展开成若干「标准写法」变体，各自查一次词库。
        //    变体召回统一降权，精确候选不受影响；精确没词时它就能救回来。
        if prefs.fuzzyAny {
            for variant in fuzzyVariants(composing) {
                for hit in hot?.lookup(prefix: variant, limit: 8, scanLimit: 1500) ?? [] {
                    guard seen.insert(hit.word).inserted else { continue }
                    primary.append(PinyinCandidate(
                        word: hit.word,
                        score: hit.score + 5000 + closeness(hit.key, variant) - 3200
                            + prefs.bonus(pinyin: hit.key, word: hit.word),
                        remaining: "",
                        key: hit.key
                    ))
                }
                for hit in full?.lookup(prefix: variant, limit: 10, scanLimit: 1500) ?? [] {
                    guard seen.insert(hit.word).inserted else { continue }
                    primary.append(PinyinCandidate(
                        word: hit.word,
                        score: hit.score + closeness(hit.key, variant) - 3200
                            + prefs.bonus(pinyin: hit.key, word: hit.word),
                        remaining: "",
                        key: hit.key
                    ))
                }
            }
        }
        primary.sort { $0.score > $1.score }

        // 4) 连打候选：整串候选不足时才补，且优先切出最长的首个词。
        var continuations: [PinyinCandidate] = []
        if primary.count < 16 {
            let chars = Array(composing)
            var continuationSeen = Set<String>()
            var added = 0
            for boundary in syllableBoundaries(composing).reversed()
                where boundary > 0 && boundary < chars.count {
                let head = String(Array(chars[0..<boundary]))
                let rest = String(Array(chars[boundary..<chars.count]))
                // 首词至少两个音节，且不做单字连打（否则「大›jia」盖住「大家」）。
                guard head.count >= 4, rest.count >= 2 else { continue }

                var exact: [(String, Int)] = []
                for hit in hot?.lookup(prefix: head, limit: 12, scanLimit: 40000) ?? [] where hit.key == head {
                    exact.append((hit.word, hit.score))
                }
                for hit in full?.lookup(prefix: head, limit: 20, scanLimit: 8000) ?? [] where hit.key == head {
                    exact.append((hit.word, hit.score))
                }
                for (word, score) in exact {
                    guard word.count >= 2,
                          !seen.contains(word),
                          continuationSeen.insert(word).inserted else { continue }
                    continuations.append(PinyinCandidate(
                        word: word, score: score, remaining: rest, key: head
                    ))
                    added += 1
                    if added >= 6 { break }
                }
                if added >= 6 { break }
            }
        }

        continuations.sort { $0.score > $1.score }
        let merged = primary + continuations
        // 候选栏横滑只显示前几个，剩下的留给「更多候选」宫格。
        candidates = merged.count > 80 ? Array(merged.prefix(80)) : merged
    }

    /// 拼音正好敲完的音节优先于还在往后延伸的长词：
    /// 敲 "ni" 时「你」(key=ni) 应该压过「年」(key=nian)。
    private func closeness(_ key: String, _ base: String) -> Int {
        if key == base { return 9000 }
        let delta = max(0, key.count - base.count)
        return max(0, 4200 - delta * 700)
    }

    /// 生成模糊音变体：声母在音节起始处换，韵母在每个音节边界换，合计最多 12 个。
    /// 例如开 zh↔z 后打 "zongguo" 会得到 "zhongguo"；开 en↔eng 后打
    /// "cenjing" 会在边界把 "cen" 换成 "ceng"，得到 "cengjing" 召回「曾经」。
    /// 两类规则各有配额，避免声母变体把韵母变体全挤掉。
    private func fuzzyVariants(_ s: String) -> [String] {
        let rules = KeyboardPrefs.fuzzyRules.filter { KeyboardPrefs.shared.fuzzyEnabled($0.key) }
        guard !rules.isEmpty, !s.isEmpty else { return [] }

        var out: [String] = []
        var seen: Set<String> = [s]
        let chars = Array(s)
        let starts: [Int] = [0] + syllableBoundaries(s).filter { $0 < chars.count }

        func add(_ candidate: String) -> Bool {
            guard candidate != s, !candidate.isEmpty,
                  seen.insert(candidate).inserted, out.count < 12 else { return false }
            out.append(candidate)
            return true
        }

        var initialAdded = 0
        for rule in rules where rule.initial {
            for p in starts where initialAdded < 8 {
                let head = String(Array(chars[0..<p]))
                let tail = String(Array(chars[p..<chars.count]))
                var candidate: String?
                if tail.hasPrefix(rule.to) {
                    candidate = head + rule.from + String(tail.dropFirst(rule.to.count))
                } else if tail.hasPrefix(rule.from) {
                    candidate = head + rule.to + String(tail.dropFirst(rule.from.count))
                }
                if let value = candidate, add(value) { initialAdded += 1 }
            }
        }

        var finalAdded = 0
        for rule in rules where !rule.initial {
            for p in starts + [chars.count] where finalAdded < 6 {
                let head = String(Array(chars[0..<p]))
                let tail = String(Array(chars[p..<chars.count]))
                var candidate: String?
                if head.hasSuffix(rule.to) {
                    candidate = String(head.dropLast(rule.to.count)) + rule.from + tail
                } else if head.hasSuffix(rule.from) {
                    candidate = String(head.dropLast(rule.from.count)) + rule.to + tail
                }
                if let value = candidate, add(value) { finalAdded += 1 }
            }
        }
        return out
    }

    /// 用音节表做 DP，返回所有可以断开的位置。420 个音节，纯内存计算。
    private func syllableBoundaries(_ s: String) -> [Int] {
        let chars = Array(s)
        guard !chars.isEmpty else { return [] }
        var reachable = Array(repeating: false, count: chars.count + 1)
        reachable[0] = true
        for i in 0..<chars.count where reachable[i] {
            for len in 1...6 where i + len <= chars.count {
                let seg = String(Array(chars[i..<(i + len)]))
                if PinyinSyllables.all.contains(seg) {
                    reachable[i + len] = true
                }
            }
        }
        var out: [Int] = []
        for i in 1...chars.count where reachable[i] {
            out.append(i)
        }
        return out
    }

    // MARK: - 联想

    /// 上屏一个词之后，先用词库补全「以这个词开头的更长的词」，再补搭配表和通用虚词。
    /// 主流输入法选完词候选栏不空着，就是这一层在起作用。
    private func updateSuggestions(_ word: String, pinyin: String) {
        var list: [String] = []

        if !pinyin.isEmpty {
            for hit in hot?.lookup(prefix: pinyin, limit: 40, scanLimit: 4000) ?? [] {
                if hit.word.count > word.count, hit.word.hasPrefix(word), !list.contains(hit.word) {
                    list.append(hit.word)
                }
                if list.count >= 12 { break }
            }
            if list.count < 12 {
                for hit in full?.lookup(prefix: pinyin, limit: 60, scanLimit: 6000) ?? [] {
                    if hit.word.count > word.count, hit.word.hasPrefix(word), !list.contains(hit.word) {
                        list.append(hit.word)
                    }
                    if list.count >= 12 { break }
                }
            }
        }

        for item in PinyinEngine.associations[word] ?? [] {
            if !list.contains(item) { list.append(item) }
        }
        for item in PinyinEngine.genericFollow {
            if !list.contains(item) { list.append(item) }
        }
        suggestions = Array(list.prefix(20))
    }

    /// 高频词的人工搭配表：词库里没有「你好→吗」这种跨词关系，得补一层。
    private static let associations: [String: [String]] = [
        "你好": ["吗", "呀", "！", "世界", "请问", "在吗", "麻烦了"],
        "谢谢": ["！", "你", "大家", "啦", "非常感谢"],
        "好的": ["，", "。", "没问题", "收到", "我知道了"],
        "今天": ["早上", "下午", "晚上", "天气", "怎么样", "几点"],
        "明天": ["见", "早上", "下午", "再说", "几点"],
        "现在": ["在", "几点", "可以", "开始", "方便吗"],
        "什么": ["意思", "时候", "地方", "问题", "都行"],
        "怎么": ["办", "样", "了", "回事", "才能"],
        "我们": ["一起", "可以", "的", "都", "先"],
        "你们": ["好", "的", "一起", "怎么样"],
        "因为": ["所以", "这个", "我", "没有"],
        "所以": ["说", "我", "就", "可以"],
        "可以": ["吗", "的", "了", "一起", "试试"],
        "没有": ["问题", "关系", "办法", "了"],
        "问题": ["是", "不大", "解决了", "吗"],
        "工作": ["了", "的", "顺利", "忙"],
        "时间": ["了", "不多", "安排", "几点"],
        "中国": ["人", "的", "在", "和"],
        "请": ["问", "稍等", "帮忙", "看一下"],
        "麻烦": ["你了", "帮我", "看一下"],
        "知道": ["了", "吗", "的"],
        "觉得": ["怎么样", "可以", "不太"],
        "喜欢": ["的", "吗", "这个"],
        "一下": ["，", "就好", "吧"],
        "这个": ["是", "可以", "不太", "问题"],
        "那个": ["是", "人", "地方"],
        "在": ["哪里", "吗", "一起", "家"],
        "是": ["吗", "不是", "的", "这样"],
        "我": ["们", "的", "在", "想", "觉得"],
        "你": ["好", "们", "的", "在", "说"],
        "他": ["们", "的", "说", "在"],
        "好": ["的", "了", "吧", "呀", "看"],
        "不": ["是", "知道", "用", "太", "会"],
        "很": ["好", "不错", "喜欢", "感谢"],
        "马上": ["到", "就", "来"],
        "收到": ["，", "谢谢", "马上处理"],
    ]

    private static let genericFollow = [
        "，", "。", "！", "？", "的", "了", "吗", "吧", "啊", "呢",
        "我", "你", "在", "是", "有", "就", "、", "…",
    ]
}

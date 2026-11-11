import Foundation

/// 一个候选：word 是上屏文字，remaining 是选词后仍留在输入缓冲里的拼音。
/// 例如一口气敲 "nihaoma"，选「你好」时 remaining = "ma"，接着继续出候选。
struct PinyinCandidate {
    let word: String
    let score: Int
    let remaining: String

    var needsContinuation: Bool { !remaining.isEmpty }
}

/// 纯 Swift 拼音引擎：不依赖任何第三方 SDK、不链接 librime。
/// 词库是构建期生成的二进制索引（71 万条），运行时 mmap + 二分。
final class PinyinEngine {

    static let shared = PinyinEngine()

    private let full: PinyinDictionary?
    private let hot: PinyinDictionary?

    private(set) var composing = ""
    private(set) var candidates: [PinyinCandidate] = []

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
    }

    /// 上屏第 index 个候选，返回要插入的文字。
    @discardableResult
    func commit(at index: Int) -> String? {
        guard index >= 0, index < candidates.count else { return nil }
        let picked = candidates[index]
        composing = picked.remaining
        refresh()
        return picked.word
    }

    /// 显示用的拼音串：按音节加空格，例如 "nihao" -> "ni hao"。
    var displayText: String {
        guard !composing.isEmpty else { return "拼音输入就绪 · 词库 \(diagnostic)" }
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

        // 整串候选永远排在连打候选前面，否则「你›hao」会压过「你好」。
        var primarySeen = Set<String>()
        var primary: [PinyinCandidate] = []

        // 1) 高频表：全局词频 top 4 万，保证单字母/两字母输入也有好词。
        for hit in hot?.lookup(prefix: composing, limit: 40, scanLimit: 40000) ?? [] {
            guard primarySeen.insert(hit.word).inserted else { continue }
            primary.append(PinyinCandidate(
                word: hit.word,
                score: hit.score + 5000 + closenessBonus(hit.key),
                remaining: ""
            ))
        }

        // 2) 全量表：长尾词、成语、专名都在这里。
        for hit in full?.lookup(prefix: composing, limit: 160, scanLimit: 16000) ?? [] {
            guard primarySeen.insert(hit.word).inserted else { continue }
            primary.append(PinyinCandidate(
                word: hit.word,
                score: hit.score + closenessBonus(hit.key),
                remaining: ""
            ))
        }
        primary.sort { $0.score > $1.score }

        // 3) 连打候选：整串候选不足时才补，且优先切出最长的首个词。
        var continuations: [PinyinCandidate] = []
        if primary.count < 12 {
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
                          !primarySeen.contains(word),
                          continuationSeen.insert(word).inserted else { continue }
                    continuations.append(PinyinCandidate(word: word, score: score, remaining: rest))
                    added += 1
                    if added >= 6 { break }
                }
                if added >= 6 { break }
            }
        }

        continuations.sort { $0.score > $1.score }
        let merged = primary + continuations
        candidates = merged.count > 32 ? Array(merged.prefix(32)) : merged
    }

    /// 拼音正好敲完的音节优先于还在往后延伸的长词：
    /// 敲 "ni" 时「你」(key=ni) 应该压过「年」(key=nian)。
    private func closenessBonus(_ key: String) -> Int {
        if key == composing { return 9000 }
        let delta = max(0, key.count - composing.count)
        return max(0, 4200 - delta * 700)
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
}

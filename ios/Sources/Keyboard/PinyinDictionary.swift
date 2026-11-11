import Foundation

/// PYD1 二进制词库的只读查询器。
///
/// 文件由 `ios/Tools/build_pinyin_dict.py` 生成，格式：
///   header 16B : magic "PYD1" | count:u32le | version:u32le | reserved:u32le
///   offsets    : count * u32le，每条记录相对文件头的字节偏移
///   records    : keyLen:u8 | key(ASCII) | wordLen:u8 | word(UTF-8) | score:u16le
/// 记录按 key 字节序升序、同 key 按词频降序。
///
/// 用 `Data(..., .mappedIfSafe)` 做内存映射：几十万词条不会一次性占满
/// 键盘扩展那点内存预算，二分定位后只解码命中的几十条记录。
final class PinyinDictionary {

    struct Hit {
        let key: String
        let word: String
        let score: Int
    }

    private let data: Data
    private let count: Int

    /// 词库是否成功加载；主界面状态行会显示它。
    static var diagnostic = "未加载"

    init?(resource name: String) {
        // 键盘扩展里 Bundle.main 一般就是 .appex，但不同系统版本有过差异，
        // 两个都试一遍，避免资源明明在包里却读不到。
        let bundles = [Bundle.main, Bundle(for: PinyinDictionary.self)]
        var found: Data?
        for bundle in bundles {
            guard let url = bundle.url(forResource: name, withExtension: "bin"),
                  let d = try? Data(contentsOf: url, options: .mappedIfSafe),
                  d.count >= 16,
                  String(bytes: d[0..<4], encoding: .ascii) == "PYD1" else { continue }
            found = d
            break
        }
        guard let d = found else { return nil }
        let n = Int(PinyinDictionary.readU32(d, 4))
        guard n > 0, d.count >= 16 + 4 * n else { return nil }
        data = d
        count = n
    }

    var entryCount: Int { count }

    @inline(__always)
    private static func readU32(_ d: Data, _ at: Int) -> UInt32 {
        UInt32(d[at])
            | (UInt32(d[at + 1]) << 8)
            | (UInt32(d[at + 2]) << 16)
            | (UInt32(d[at + 3]) << 24)
    }

    @inline(__always)
    private static func readU32(_ b: UnsafePointer<UInt8>, _ at: Int) -> UInt32 {
        UInt32(b[at])
            | (UInt32(b[at + 1]) << 8)
            | (UInt32(b[at + 2]) << 16)
            | (UInt32(b[at + 3]) << 24)
    }

    /// 比较第 index 条记录的 key 是否字典序小于 prefix。
    @inline(__always)
    private func keyIsLess(_ b: UnsafePointer<UInt8>, index: Int, than prefix: [UInt8]) -> Bool {
        let off = Int(PinyinDictionary.readU32(b, 16 + index * 4))
        let keyLen = Int(b[off])
        let n = min(keyLen, prefix.count)
        for j in 0..<n {
            let lhs = b[off + 1 + j]
            let rhs = prefix[j]
            if lhs != rhs { return lhs < rhs }
        }
        return keyLen < prefix.count
    }

    /// 查出 key 以 prefix 开头的词条，按词频降序返回前 limit 条。
    /// scanLimit 防止单字母输入时把几十万条全部解码。
    func lookup(prefix: String, limit: Int, scanLimit: Int) -> [Hit] {
        let p = Array(prefix.utf8)
        guard !p.isEmpty, limit > 0 else { return [] }
        var hits: [Hit] = []

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let b = base.assumingMemoryBound(to: UInt8.self)

            var lo = 0
            var hi = count
            while lo < hi {
                let mid = (lo + hi) / 2
                if keyIsLess(b, index: mid, than: p) {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }

            var i = lo
            var scanned = 0
            while i < count, scanned < scanLimit {
                let off = Int(PinyinDictionary.readU32(b, 16 + i * 4))
                guard off + 2 <= data.count else { break }
                let keyLen = Int(b[off])
                if keyLen < p.count { break }
                let keyStart = off + 1
                var matched = true
                for j in 0..<p.count where b[keyStart + j] != p[j] {
                    matched = false
                    break
                }
                if !matched { break }

                let wordLen = Int(b[keyStart + keyLen])
                let wordStart = keyStart + keyLen + 1
                let scoreStart = wordStart + wordLen
                guard scoreStart + 2 <= data.count else { break }
                let score = Int(UInt16(b[scoreStart]) | (UInt16(b[scoreStart + 1]) << 8))
                let wordData = Data(bytes: UnsafeRawPointer(b.advanced(by: wordStart)), count: wordLen)
                let keyData = Data(bytes: UnsafeRawPointer(b.advanced(by: keyStart)), count: keyLen)
                if let word = String(data: wordData, encoding: .utf8), !word.isEmpty,
                   let key = String(data: keyData, encoding: .ascii) {
                    hits.append(Hit(key: key, word: word, score: score))
                }
                i += 1
                scanned += 1
            }
        }

        hits.sort { $0.score > $1.score }
        if hits.count > limit { hits.removeSubrange(limit..<hits.count) }
        return hits
    }
}

package com.clipbang.core

/**
 * 平台分词器。只负责把一段连续的中日韩文本切成词，不处理标点、空白、数字、链接。
 *
 * 两端各自实现：
 *   安卓 —— AndroidWordSegmenter，接本地词典
 *   iOS  —— AppleWordSegmenter，接系统分词
 *
 * 返回的区间必须覆盖传入文本的全部字符，不允许留空。
 */
interface WordSegmenter {
    fun split(text: String): List<Span>
}

/**
 * 分词规则层。移植契约第三节。
 *
 * 先按规则硬切，切不开的中文段落才交给平台分词器。
 * 这一层是共享逻辑，两端行为必须完全一致。
 */
class Segmenter(private val dictionary: WordSegmenter) {

    fun segment(raw: String): List<Token> {
        if (raw.isEmpty()) return emptyList()

        val out = ArrayList<Token>(raw.length / 2 + 8)
        var i = 0

        while (i < raw.length) {
            if (out.size >= MAX_TOKENS) {
                // 到一个安全边界再截断，避免把块切断
                out.add(Token(raw.substring(i), i, raw.length, TokenKind.OTHER, true))
                break
            }

            val hard = matchHardRule(raw, i)
            if (hard != null) {
                out.addAll(splitOversize(hard))
                i = hard.end
                continue
            }

            val c = raw[i]
            if (isCjk(c)) {
                val runEnd = scanCjkRun(raw, i)
                emitCjkRun(raw, i, runEnd, out)
                i = runEnd
                continue
            }

            // 单个无法归类的字符，保证不丢字
            out.add(Token(raw.substring(i, i + 1), i, i + 1, TokenKind.OTHER, true))
            i++
        }

        return absorbSpaces(out)
    }

    /**
     * 普通空格并到前一个词块里，避免炸开时出现只有几像素宽的空白块。
     * 标点保持独立成块，用户可以单独点选。换行符保留，它是硬边界。
     */
    private fun absorbSpaces(tokens: List<Token>): List<Token> {
        if (tokens.isEmpty()) return tokens
        val out = ArrayList<Token>(tokens.size)

        for (t in tokens) {
            val absorbable = t.kind == TokenKind.SPACE && !t.text.contains('\n')

            if (absorbable && out.isNotEmpty()) {
                val prev = out.removeAt(out.lastIndex)
                out.add(
                    prev.copy(
                        text = prev.text + t.text,
                        end = t.end
                    )
                )
            } else {
                out.add(t)
            }
        }
        return out
    }

    // ---------- 中文段落 ----------

    private fun emitCjkRun(raw: String, from: Int, to: Int, out: MutableList<Token>) {
        val run = raw.substring(from, to)
        val spans = runCatching { dictionary.split(run) }.getOrNull()

        if (spans.isNullOrEmpty()) {
            // 分词器失效时退化为逐字成块，宁可碎不可丢
            for (k in from until to) {
                out.add(Token(raw.substring(k, k + 1), k, k + 1, TokenKind.WORD, true))
            }
            return
        }

        var cursor = from
        for (s in spans) {
            val st = from + s.start
            val en = from + s.end
            if (st < cursor || en > to) continue
            if (st > cursor) {
                // 分词器漏掉的缺口，补成单字块
                for (k in cursor until st) {
                    out.add(Token(raw.substring(k, k + 1), k, k + 1, TokenKind.WORD, true))
                }
            }
            out.add(Token(raw.substring(st, en), st, en, TokenKind.WORD, true))
            cursor = en
        }
        if (cursor < to) {
            for (k in cursor until to) {
                out.add(Token(raw.substring(k, k + 1), k, k + 1, TokenKind.WORD, true))
            }
        }
    }

    private fun scanCjkRun(raw: String, from: Int): Int {
        var i = from
        while (i < raw.length && isCjk(raw[i])) i++
        return i
    }

    // ---------- 硬规则 ----------

    private fun matchHardRule(raw: String, at: Int): Token? {
        val rest = raw.length - at
        val c = raw[at]

        // 1 换行
        if (c == '\n' || c == '\r') {
            val len = if (c == '\r' && at + 1 < raw.length && raw[at + 1] == '\n') 2 else 1
            return Token(raw.substring(at, at + len), at, at + len, TokenKind.SPACE, false)
        }

        // 2 链接
        if (rest >= 4) {
            URL_REGEX.matchAt(raw, at)?.let {
                return Token(it.value, at, at + it.value.length, TokenKind.URL, true)
            }
        }

        // 3 邮箱
        EMAIL_REGEX.matchAt(raw, at)?.let {
            return Token(it.value, at, at + it.value.length, TokenKind.WORD, true)
        }

        // 4 长数字串（六位以上，允许内部连字符）
        LONG_NUMBER_REGEX.matchAt(raw, at)?.let {
            return Token(it.value, at, at + it.value.length, TokenKind.NUMBER, true)
        }

        // 5 数字加单位
        if (c.isDigit()) {
            val m = NUMBER_UNIT_REGEX.matchAt(raw, at)
            if (m != null) {
                return Token(m.value, at, at + m.value.length, TokenKind.NUMBER, true)
            }
        }

        // 6 拉丁词
        if (isLatinLetter(c)) {
            val m = LATIN_REGEX.matchAt(raw, at)
            if (m != null) {
                return Token(m.value, at, at + m.value.length, TokenKind.WORD, true)
            }
        }

        // 7 表情与代理对
        if (c.isHighSurrogate() && at + 1 < raw.length && raw[at + 1].isLowSurrogate()) {
            return Token(raw.substring(at, at + 2), at, at + 2, TokenKind.EMOJI, true)
        }
        if (isEmojiSymbol(c)) {
            return Token(raw.substring(at, at + 1), at, at + 1, TokenKind.EMOJI, true)
        }

        // 8 半角标点
        if (isAsciiPunct(c)) {
            return Token(raw.substring(at, at + 1), at, at + 1, TokenKind.PUNCT, true)
        }

        // 9 全角标点
        if (isCjkPunct(c)) {
            return Token(raw.substring(at, at + 1), at, at + 1, TokenKind.PUNCT, true)
        }

        // 10 空白
        if (c.isWhitespace()) {
            var e = at
            while (e < raw.length && raw[e].isWhitespace() && raw[e] != '\n' && raw[e] != '\r') e++
            return Token(raw.substring(at, e), at, e, TokenKind.SPACE, false)
        }

        return null
    }

    /** 超长块在最近的标点处二次切分，移植契约第三节 */
    private fun splitOversize(t: Token): List<Token> {
        if (t.text.length <= MAX_TOKEN_LENGTH) return listOf(t)

        val pieces = ArrayList<Token>(2)
        var s = 0
        val text = t.text
        while (s < text.length) {
            var e = minOf(s + MAX_TOKEN_LENGTH, text.length)
            if (e < text.length) {
                // 往回找一个标点，让切点落在语义边界上
                var k = e
                while (k > s + 1 && !isCjkPunct(text[k - 1]) && !text[k - 1].isWhitespace()) k--
                if (k > s + 1) e = k
            }
            pieces.add(
                Token(text.substring(s, e), t.start + s, t.start + e, t.kind, t.selectable)
            )
            s = e
        }
        return pieces
    }

    companion object {
        const val MAX_TOKENS = 500
        const val MAX_TOKEN_LENGTH = 200

        private val URL_REGEX = Regex(
            "(?i)(https?://|ftp://|www\\.)[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]+"
        )
        private val EMAIL_REGEX = Regex("[\\w.+-]+@[\\w-]+(\\.[\\w-]+)+")
        private val LONG_NUMBER_REGEX = Regex("\\d[\\d\\-]{5,}")
        private val NUMBER_UNIT_REGEX = Regex(
            "\\d+(\\.\\d+)?(%|km|kg|cm|mm|ms|GB|MB|KB|TB|m|s|g|元|块|年|月|日|号|个|次|条|位|秒|分|小时|万|亿)?"
        )
        private val LATIN_REGEX = Regex("[A-Za-z][A-Za-z'\\-]*")

        fun isCjk(c: Char): Boolean =
            (c in '\u4E00'..'\u9FFF') ||
                (c in '\u3400'..'\u4DBF') ||
                (c in '\u3040'..'\u30FF') ||   // 日文假名
                (c in '\uAC00'..'\uD7AF')      // 韩文

        fun isLatinLetter(c: Char): Boolean =
            (c in 'a'..'z') || (c in 'A'..'Z')

        fun isCjkPunct(c: Char): Boolean =
            c in "，。！？；：、“”‘’（）《》【】〈〉…—～·「」『』"

        /** 半角标点。单独成块且不可选，避免时间戳、括号被切碎后又散在句子中间 */
        fun isAsciiPunct(c: Char): Boolean =
            c in ",.:;!?()[]{}<>/\\|\"'`~-_=+*&^%$#@"

        fun isEmojiSymbol(c: Char): Boolean =
            (c in '\u2600'..'\u27BF') ||
                (c in '\u2B00'..'\u2BFF') ||
                (c in '\uFE0F'..'\uFE0F')
    }
}

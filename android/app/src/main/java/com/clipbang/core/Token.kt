package com.clipbang.core

/**
 * 词块。移植契约第二节。
 *
 * 共享层类型：不许出现任何平台类型，iOS 侧按同样字段实现一遍。
 */
data class Token(
    val text: String,
    val start: Int,
    val end: Int,
    val kind: TokenKind,
    val selectable: Boolean
) {
    init {
        require(end - start == text.length) {
            "区间长度与文本不符: [$start,$end) 长度 ${end - start}，文本长度 ${text.length}"
        }
        require(start >= 0 && end >= start) { "非法区间: [$start,$end)" }
    }
}

enum class TokenKind {
    /** 中文词、英文单词，可选 */
    WORD,

    /** 数字、数字加单位，可选 */
    NUMBER,

    /** 链接，可选 */
    URL,

    /** 表情，可选 */
    EMOJI,

    /** 标点，不可选 */
    PUNCT,

    /** 空白与换行，不可选 */
    SPACE,

    /** 无法归类的单字，可选，保证不丢字 */
    OTHER
}

/**
 * 一段文本里的连续区间，左闭右开。
 */
data class Span(val start: Int, val end: Int) {
    init {
        require(start >= 0 && end > start) { "非法跨度: [$start,$end)" }
    }

    val length: Int get() = end - start
}

/**
 * 剪贴记录。移植契约第二节。
 */
data class ClipRecord(
    val id: String,
    val text: String,
    val kind: ClipKind,
    val createdAt: Long,
    val pinned: Boolean = false,
    val sourceApp: String? = null,
    val tokenCount: Int = 0
)

enum class ClipKind {
    TEXT, LINK, NUMBER, EMAIL, COLOR, CODE
}

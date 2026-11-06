package com.clipbang.core

/**
 * 词块拼接。移植契约第五节。
 *
 * 把用户选中的块按原文顺序拼回一段文字，规则两端必须一致：
 *   - 相邻的块直接拼
 *   - 中间只隔着不可选的块（标点、空白）时，把这些块一起带上
 *   - 中间隔着没选中的可选块时，丢掉中间内容；两边都是拉丁字符才补一个空格
 */
object TokenJoiner {

    fun join(tokens: List<Token>, selected: Set<Int>): String {
        if (selected.isEmpty()) return ""
        val indices = selected.filter { it in tokens.indices }.sorted()
        if (indices.isEmpty()) return ""

        val sb = StringBuilder()
        indices.forEachIndexed { order, cur ->
            if (order == 0) {
                sb.append(tokens[cur].text)
                return@forEachIndexed
            }

            val prev = indices[order - 1]
            if (cur == prev + 1) {
                sb.append(tokens[cur].text)
                return@forEachIndexed
            }

            val between = (prev + 1 until cur).map { tokens[it] }
            if (between.isNotEmpty() && between.all { !it.selectable }) {
                between.forEach { sb.append(it.text) }
            } else if (needSpace(tokens[prev].text, tokens[cur].text)) {
                sb.append(' ')
            }
            sb.append(tokens[cur].text)
        }
        return sb.toString()
    }

    /** 只有两边都是拉丁字母或数字时才补空格，中文之间不补 */
    private fun needSpace(left: String, right: String): Boolean {
        if (left.isEmpty() || right.isEmpty()) return false
        val a = left.last()
        val b = right.first()
        return a.code < 128 && a.isLetterOrDigit() && b.code < 128 && b.isLetterOrDigit()
    }
}

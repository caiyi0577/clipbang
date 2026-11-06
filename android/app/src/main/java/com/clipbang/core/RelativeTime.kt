package com.clipbang.core

/**
 * 相对时间文案。共享逻辑，两端输出必须一致。
 */
object RelativeTime {

    fun format(now: Long, createdAt: Long): String {
        val diff = now - createdAt
        if (diff < 0) return "刚刚"

        val minute = 60_000L
        val hour = 60 * minute
        val day = 24 * hour

        return when {
            diff < minute -> "刚刚"
            diff < hour -> "${diff / minute} 分钟前"
            diff < day -> "${diff / hour} 小时前"
            diff < 30 * day -> "${diff / day} 天前"
            else -> "${diff / (30 * day)} 个月前"
        }
    }
}

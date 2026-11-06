package com.clipbang.ime

import com.clipbang.core.Segmenter
import com.clipbang.core.Span
import com.clipbang.core.WordSegmenter

/**
 * 安卓侧分词实现。平台实现层，iOS 侧对应 AppleWordSegmenter。
 *
 * 当前是过渡方案：正向最大匹配，词典是内置的小词表。
 * 后续换成接本地分词引擎时，只改这个文件，Segmenter 一行不用动。
 */
class AndroidWordSegmenter : WordSegmenter {

    override fun split(text: String): List<Span> {
        if (text.isEmpty()) return emptyList()
        if (text.length < 2) return listOf(Span(0, text.length))

        val out = ArrayList<Span>(text.length / 2 + 2)
        var i = 0
        while (i < text.length) {
            val matched = longestMatch(text, i)
            out.add(Span(i, i + matched))
            i += matched
        }
        return out
    }

    /** 从 at 开始的最长词长，找不到就吃两字（比逐字可读性好） */
    private fun longestMatch(text: String, at: Int): Int {
        val remaining = text.length - at
        var len = minOf(MAX_WORD_LENGTH, remaining)
        while (len >= 2) {
            if (DICT.contains(text.substring(at, at + len))) return len
            len--
        }
        return minOf(2, remaining)
    }

    companion object {
        private const val MAX_WORD_LENGTH = 4

        /**
         * 高频词种子表。不是完整词典，只是让第一版切出来的结果能看。
         * 正式版换成带词频的词典文件。
         */
        private val DICT: Set<String> = setOf(
            "明天", "今天", "昨天", "后天", "上午", "下午", "中午", "晚上", "早上",
            "时候", "时间", "地点", "地铁", "车站", "路口", "电话", "地址", "号码",
            "我们", "你们", "他们", "自己", "大家", "别人",
            "这个", "那个", "哪个", "什么", "怎么", "为什么", "因为", "所以", "但是",
            "可以", "不能", "需要", "应该", "已经", "还是", "或者", "然后", "如果",
            "确认", "收到", "谢谢", "麻烦", "请问", "帮忙", "安排", "处理", "检查",
            "迟到", "别迟到", "号口", "地铁站", "出口", "入口", "几号", "几点",
            "文件", "文档", "版本", "需求", "项目", "会议", "纪要", "方案", "设计",
            "周五", "周一", "周二", "周三", "周四", "周六", "周日", "周末",
            "之前", "之后", "以前", "以后", "现在", "刚才", "马上", "立刻",
            "给你", "给我", "发我", "看看", "再说", "好的", "行吧", "没问题",
            "客户", "同事", "领导", "团队", "开发", "测试", "上线", "迭代",
            "地铁站", "出口", "入口", "附近", "对面", "旁边",
            "目标", "结果", "原因", "问题", "办法", "东西", "事情"
        )
    }
}

/**
 * 分词器工厂。切换实现只改这里。
 */
object SegmenterFactory {
    val shared: Segmenter by lazy { Segmenter(AndroidWordSegmenter()) }
}

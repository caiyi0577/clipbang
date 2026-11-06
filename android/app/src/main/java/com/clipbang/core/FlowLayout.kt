package com.clipbang.core

/**
 * 词块排布。移植契约第四节。
 *
 * 这一层只做坐标计算：拿到每个块已经量好的宽高，算出坐标。
 * 不测量文字，不读字体，不碰绘制。iOS 侧按同样签名实现一遍即可。
 */
data class BlockSize(val width: Float, val height: Float)

data class PlacedBlock(
    val index: Int,
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float
)

data class FlowResult(
    val blocks: List<PlacedBlock>,
    val totalHeight: Float
)

object FlowLayoutEngine {

    /**
     * @param sizes        每个块的宽高，由平台层测量后传入
     * @param containerWidth 容器可用宽度
     * @param itemSpacing  块之间的水平间距
     * @param lineSpacing  行间距
     * @param hardBreaks   这些索引的块必须另起一行（来自换行符）
     */
    fun layout(
        sizes: List<BlockSize>,
        containerWidth: Float,
        itemSpacing: Float,
        lineSpacing: Float,
        hardBreaks: Set<Int> = emptySet()
    ): FlowResult {
        if (sizes.isEmpty()) return FlowResult(emptyList(), 0f)
        require(containerWidth > 0f) { "容器宽度必须为正" }

        val placed = ArrayList<PlacedBlock>(sizes.size)
        var x = 0f
        var y = 0f
        var lineHeight = 0f

        for (i in sizes.indices) {
            val size = sizes[i]
            val atLineStart = x == 0f

            val needNewLine =
                !atLineStart && (hardBreaks.contains(i) || x + size.width > containerWidth)

            if (needNewLine) {
                x = 0f
                y += lineHeight + lineSpacing
                lineHeight = 0f
            }

            placed.add(PlacedBlock(i, x, y, size.width, size.height))
            x += size.width + itemSpacing
            lineHeight = maxOf(lineHeight, size.height)
        }

        return FlowResult(placed, y + lineHeight)
    }
}

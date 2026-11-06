package com.clipbang.ime

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clipbang.core.BlockSize
import com.clipbang.core.FlowLayoutEngine
import com.clipbang.core.Token
import com.clipbang.core.TokenJoiner
import com.clipbang.core.TokenKind
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * 炸开视图。把一条记录拆成词块铺开，点选后拼起来插入。
 *
 * 布局算法走共享层的 FlowLayoutEngine，这里只负责测量和放置。
 */

private val ChipText = Color(0xFF333333)
private val ChipPunct = Color(0xFF9D9D9D)
private val ChipFace = Color(0xFFFFFFFF)
private val ChipEdge = Color(0xFFE2E2E2)
private val ChipSelectedEdge = Color(0xFF3F68E2)
private val BarBg = Color(0xFFF5F5F5)
private val ChipCorner = 6.dp

@Composable
fun BlastView(
    text: String,
    selected: Set<Int>,
    onToggle: (Int) -> Unit,
    onExit: () -> Unit,
    onInsertSelected: (String) -> Unit
) {
    val tokens = remember(text) { SegmenterFactory.shared.segment(text) }
    val scrollState = rememberScrollState()

    // 整体炸开的进度：所有词块共用一个时间轴，各自按索引取自己的那一段
    var entered by remember(text) { mutableStateOf(false) }
    LaunchedEffect(text) { entered = true }
    val blastProgress by animateFloatAsState(
        targetValue = if (entered) 1f else 0f,
        animationSpec = tween(durationMillis = 320, easing = FastOutSlowInEasing),
        label = "blastProgress"
    )

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .weight(1f)
                .verticalScroll(scrollState)
                .padding(horizontal = 10.dp, vertical = 8.dp)
        ) {
            TokenFlow(
                tokens = tokens,
                selected = selected,
                progress = blastProgress,
                onToggle = onToggle
            )
        }


        if (selected.isNotEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(46.dp)
                    .background(BarBg),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .height(34.dp)
                        // 规范里的主按钮：上浅下深蓝渐变 + 0.8 描边 + 向下 4dp 短投影
                        .shadow(
                            elevation = 4.dp,
                            shape = RoundedCornerShape(6.dp),
                            clip = false,
                            spotColor = Color(0x333F68E2)
                        )
                        .background(
                            brush = Brush.verticalGradient(
                                listOf(Color(0xFF5F8AEC), Color(0xFF5883EB))
                            ),
                            shape = RoundedCornerShape(6.dp)
                        )
                        .border(0.8.dp, Color(0xFF3F68E2), RoundedCornerShape(6.dp))
                        .clickable { onInsertSelected(TokenJoiner.join(tokens, selected)) }
                        .padding(horizontal = 18.dp),
                    contentAlignment = Alignment.Center
                ) {
                    BasicText(
                        text = "插入 ${selected.size} 块",
                        style = TextStyle(fontSize = 14.sp, color = Color.White)
                    )
                }
            }
        }
    }
}

@Composable
private fun TokenFlow(
    tokens: List<Token>,
    selected: Set<Int>,
    progress: Float,
    onToggle: (Int) -> Unit
) {
    val density = LocalDensity.current
    val itemSpacing = with(density) { 6.dp.toPx() }
    val lineSpacing = with(density) { 12.dp.toPx() }

    Layout(
        content = {
            tokens.forEachIndexed { index, token ->
                TokenChip(
                    token = token,
                    index = index,
                    total = tokens.size,
                    selected = index in selected,
                    progress = progress,
                    onClick = { onToggle(index) }
                )
            }
        }
    ) { measurables, constraints ->
        val placeables = measurables.map { it.measure(Constraints()) }
        val sizes = placeables.map { BlockSize(it.width.toFloat(), it.height.toFloat()) }

        val hardBreaks = tokens.mapIndexedNotNull { index, token ->
            if (token.kind == TokenKind.SPACE && token.text.contains('\n')) index else null
        }.toSet()

        val result = FlowLayoutEngine.layout(
            sizes = sizes,
            containerWidth = constraints.maxWidth.toFloat(),
            itemSpacing = itemSpacing,
            lineSpacing = lineSpacing,
            hardBreaks = hardBreaks
        )

        layout(constraints.maxWidth, result.totalHeight.roundToInt()) {
            val count = result.blocks.size.coerceAtLeast(1)
            val rise = 9.dp.toPx()

            result.blocks.forEach { placed ->
                // 每块错开一点，最多占用 35% 的时间轴
                val delay = (placed.index.toFloat() / count) * 0.35f
                val p = ((progress - delay) / 0.65f).coerceIn(0f, 1f)
                val eased = easeOutCubic(p)

                // 只是从下方一点点浮上来，不做位移夸张
                val y = placed.y + rise * (1f - eased)
                placeables[placed.index].place(placed.x.roundToInt(), y.roundToInt())
            }
        }
    }
}

/**
 * 收尾很慢的缓出，动作一开始就有反应，后段轻轻停住。
 */
private fun easeOutCubic(t: Float): Float {
    val u = 1f - t
    return 1f - u * u * u
}

@Composable
private fun TokenChip(
    token: Token,
    index: Int,
    total: Int,
    selected: Boolean,
    progress: Float,
    onClick: () -> Unit
) {
    if (token.kind == TokenKind.SPACE) {
        Spacer(Modifier.width(6.dp).height(24.dp))
        return
    }

    // 和 Layout 里的位移共用同一条时间轴
    val delay = (index.toFloat() / total.coerceAtLeast(1)) * 0.35f
    val appear = ((progress - delay) / 0.65f).coerceIn(0f, 1f)

    val background: Brush = if (selected) {
        Brush.verticalGradient(listOf(Color(0xFF5F8AEC), Color(0xFF5883EB)))
    } else {
        Brush.verticalGradient(listOf(Color(0xFFFFFFFF), Color(0xFFFBFBFB)))
    }
    val borderColor = if (selected) ChipSelectedEdge else ChipEdge
    val textColor = if (selected) Color.White else ChipText

    Box(
        modifier = Modifier
            .graphicsLayer {
                alpha = (appear / 0.45f).coerceIn(0f, 1f)
                val s = 0.985f + 0.015f * appear
                scaleX = s
                scaleY = s
            }
            .background(background, RoundedCornerShape(ChipCorner))
            .border(0.8.dp, borderColor, RoundedCornerShape(ChipCorner))
            .clickable(enabled = token.selectable, onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 6.dp)
    ) {
        BasicText(
            text = token.text,
            style = TextStyle(
                fontSize = 17.sp,
                color = textColor,
                fontWeight = FontWeight.Medium
            )
        )
    }
}

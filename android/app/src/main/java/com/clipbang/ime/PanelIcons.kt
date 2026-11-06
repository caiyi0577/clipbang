package com.clipbang.ime

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

/**
 * 面板图标。全部用路径画，不引图标库。
 * 线条细、端点圆，跟锤子那套线性图标的调子一致。
 */

private val IconSize = 24.dp
private val IconStroke = 1.8.dp

/** 返回箭头：一条横线加左向箭头 */
@Composable
fun ArrowBackIcon(modifier: Modifier = Modifier, tint: Color = Color(0xFF333333)) {
    Canvas(modifier.size(IconSize)) {
        val w = size.width
        val h = size.height
        val sw = IconStroke.toPx()

        drawLine(tint, Offset(w * 0.16f, h * 0.5f), Offset(w * 0.84f, h * 0.5f), sw, StrokeCap.Round)
        drawLine(tint, Offset(w * 0.16f, h * 0.5f), Offset(w * 0.42f, h * 0.24f), sw, StrokeCap.Round)
        drawLine(tint, Offset(w * 0.16f, h * 0.5f), Offset(w * 0.42f, h * 0.76f), sw, StrokeCap.Round)
    }
}

/** 退格键：左侧带尖角的键帽轮廓，中间一个叉 */
@Composable
fun BackspaceIcon(modifier: Modifier = Modifier, tint: Color = Color(0xFF333333)) {
    Canvas(modifier.size(IconSize)) {
        val w = size.width
        val h = size.height
        val sw = IconStroke.toPx()

        val body = Path().apply {
            moveTo(w * 0.05f, h * 0.5f)
            lineTo(w * 0.30f, h * 0.21f)
            lineTo(w * 0.95f, h * 0.21f)
            lineTo(w * 0.95f, h * 0.79f)
            lineTo(w * 0.30f, h * 0.79f)
            close()
        }
        drawPath(
            path = body,
            color = tint,
            style = Stroke(width = sw, cap = StrokeCap.Round, join = StrokeJoin.Round)
        )

        drawLine(tint, Offset(w * 0.50f, h * 0.39f), Offset(w * 0.72f, h * 0.61f), sw, StrokeCap.Round)
        drawLine(tint, Offset(w * 0.72f, h * 0.39f), Offset(w * 0.50f, h * 0.61f), sw, StrokeCap.Round)
    }
}

/** 垃圾桶：盖子、桶身、两条竖线 */
@Composable
fun TrashIcon(modifier: Modifier = Modifier, tint: Color = Color(0xFF333333)) {
    Canvas(modifier.size(IconSize)) {
        val w = size.width
        val h = size.height
        val sw = IconStroke.toPx()

        drawLine(
            tint,
            Offset(w * 0.38f, h * 0.24f),
            Offset(w * 0.62f, h * 0.24f),
            sw,
            StrokeCap.Round
        )
        drawLine(
            tint,
            Offset(w * 0.22f, h * 0.34f),
            Offset(w * 0.78f, h * 0.34f),
            sw,
            StrokeCap.Round
        )

        val body = Path().apply {
            moveTo(w * 0.31f, h * 0.34f)
            lineTo(w * 0.35f, h * 0.80f)
            lineTo(w * 0.65f, h * 0.80f)
            lineTo(w * 0.69f, h * 0.34f)
        }
        drawPath(
            path = body,
            color = tint,
            style = Stroke(width = sw, cap = StrokeCap.Round, join = StrokeJoin.Round)
        )

        drawLine(
            tint,
            Offset(w * 0.44f, h * 0.47f),
            Offset(w * 0.45f, h * 0.69f),
            sw * 0.85f,
            StrokeCap.Round
        )
        drawLine(
            tint,
            Offset(w * 0.56f, h * 0.47f),
            Offset(w * 0.55f, h * 0.69f),
            sw * 0.85f,
            StrokeCap.Round
        )
    }
}

package com.clipbang.ime

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clipbang.core.RelativeTime
import com.clipbang.data.ClipItem
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * 面板界面。平台实现层（渲染）。iOS 侧用 SwiftUI 重写，视觉参数取自移植契约第七节。
 */

internal val TitleTop = Color(0xFFFFFFFF)
internal val TitleBottom = Color(0xFFFCFCFC)
internal val TitleEdge = Color(0xFFDFDFDF)
internal val PageBg = Color(0xFFF5F5F5)
internal val CardBg = Color(0xFFFFFFFF)
internal val Hairline = Color(0xFFE2E2E2)
internal val TextMain = Color(0xFF333333)
internal val TextTitle = Color(0xFF636363)
internal val TextSub = Color(0xFF7F7F7F)
internal val TextHint = Color(0xFF9D9D9D)
internal val AccentBlue = Color(0xFF5B87EB)
internal val BlueEdge = Color(0xFF3F68E2)
internal val DeleteRed = Color(0xFFCD3F3A)
internal val DeleteRedDeep = Color(0xFFA32D2D)

/** 卡片和按钮圆角，规范值 10 */
private val CardCorner = 10.dp

/** 面板总高度。两端都从这份常量取值，不放布局里算。 */
private val PanelHeight = 280.dp

@Composable
fun ClipBangPanel(
    mode: PanelMode,
    records: List<ClipItem>,
    onModeChange: (PanelMode) -> Unit,
    onInsert: (String) -> Unit,
    onDelete: () -> Unit,
    onDeleteItem: (String) -> Unit,
    onRefresh: () -> Unit
) {
    var blastText by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<Set<Int>>(emptySet()) }

    val inBlast = blastText != null

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(PanelHeight)
            .background(PageBg)
            // 真机页面底是 #f4f4f4 / #f2f2f2 交替、周期约 3.6dp 的竖条纹，
            // 差异小到几乎看不出来，但整片会有一层织物感
            .drawBehind {
                val stripe = 2.dp.toPx()
                var x = 0f
                var index = 0
                while (x < size.width) {
                    if (index and 1 == 0) {
                        drawRect(
                            color = Color(0xFFF2F2F2),
                            topLeft = Offset(x, 0f),
                            size = Size(stripe, size.height)
                        )
                    }
                    x += stripe
                    index++
                }
            }
    ) {
        PanelBar(
            leftIcon = if (inBlast) BarIcon.BACK else null,
            leftText = if (!inBlast) {
                if (records.isEmpty()) "剪贴板" else "剪贴板 ${records.size} 条"
            } else "",
            onLeft = if (inBlast) {
                {
                    blastText = null
                    selected = emptySet()
                }
            } else null,
            centerText = "",
            rightIcon = BarIcon.BACKSPACE,
            onRight = onDelete,
            rightText = ""
        )

        Crossfade(
            targetState = blastText,
            animationSpec = tween(durationMillis = 170),
            label = "panelMode"
        ) { target ->
            when {
                target != null -> BlastView(
                    text = target,
                    selected = selected,
                    onToggle = { index ->
                        selected = if (index in selected) selected - index else selected + index
                    },
                    onExit = {
                        blastText = null
                        selected = emptySet()
                    },
                    onInsertSelected = { joined ->
                        onInsert(joined)
                    }
                )

                mode == PanelMode.CLIPBOARD -> ClipboardList(
                    records = records,
                    onInsert = onInsert,
                    onRefresh = onRefresh,
                    onDeleteItem = onDeleteItem,
                    onLongPress = { text ->
                        blastText = text
                        selected = emptySet()
                    }
                )

                else -> PlaceholderKeyboard(onInsert = onInsert)
            }
        }
    }
}

@Composable
private fun PanelBar(
    leftIcon: BarIcon? = null,
    leftText: String = "",
    onLeft: (() -> Unit)? = null,
    centerText: String = "",
    rightIcon: BarIcon? = null,
    onRight: (() -> Unit)? = null,
    rightText: String = ""
) {
    val interaction = remember { MutableInteractionSource() }
    val leftPressed by interaction.collectIsPressedAsState()

    // 规范：顶栏图标按住时变深并弹性放大，松手弹回
    val leftScale by animateFloatAsState(
        targetValue = if (leftPressed) 1.3f else 1f,
        animationSpec = spring(dampingRatio = 0.35f, stiffness = 1100f),
        label = "leftIconScale"
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .background(
                Brush.verticalGradient(
                    0f to Color(0xFFFFFFFF),
                    0.5f to TitleTop,
                    1f to TitleBottom
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        if (leftIcon != null) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .graphicsLayer {
                        scaleX = leftScale
                        scaleY = leftScale
                    }
                    .clickable(
                        interactionSource = interaction,
                        indication = null
                    ) { onLeft?.invoke() }
                    .padding(horizontal = 13.dp, vertical = 12.dp)
            ) {
                when (leftIcon) {
                    BarIcon.BACK -> ArrowBackIcon(
                        tint = if (leftPressed) Color(0xFF9D9D9D) else TextMain
                    )
                    BarIcon.BACKSPACE -> BackspaceIcon(
                        tint = if (leftPressed) Color(0xFF9D9D9D) else TextMain
                    )
                }
            }
        } else if (leftText.isNotEmpty()) {
            BasicText(
                text = leftText,
                style = TextStyle(
                    fontSize = 16.sp,
                    color = TextMain,
                    fontWeight = FontWeight.Medium
                ),
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(horizontal = 12.dp, vertical = 12.dp)
            )
        }

        if (centerText.isNotEmpty()) {
            BasicText(
                text = centerText,
                style = TextStyle(
                    fontSize = 16.sp,
                    color = TextMain,
                    fontWeight = FontWeight.Medium
                )
            )
        }

        if (rightIcon != null) {
            var pressed by remember { mutableStateOf(false) }
            val rightScale by animateFloatAsState(
                targetValue = if (pressed) 1.3f else 1f,
                animationSpec = spring(dampingRatio = 0.35f, stiffness = 1100f),
                label = "rightIconScale"
            )

            // 按住不放时连发：先立刻响应一次，停 420ms 后进入每 55ms 一次
            LaunchedEffect(pressed) {
                if (pressed) {
                    onRight?.invoke()
                    delay(420)
                    while (true) {
                        onRight?.invoke()
                        delay(55)
                    }
                }
            }

            Box(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .graphicsLayer {
                        scaleX = rightScale
                        scaleY = rightScale
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onPress = {
                                pressed = true
                                tryAwaitRelease()
                                pressed = false
                            }
                        )
                    }
                    .padding(horizontal = 13.dp, vertical = 12.dp)
            ) {
                when (rightIcon) {
                    BarIcon.BACK -> ArrowBackIcon(
                        tint = if (pressed) Color(0xFF9D9D9D) else TextMain
                    )
                    BarIcon.BACKSPACE -> BackspaceIcon(
                        tint = if (pressed) Color(0xFF9D9D9D) else TextMain
                    )
                }
            }
        } else if (rightText.isNotEmpty()) {
            BasicText(
                text = rightText,
                style = TextStyle(fontSize = 12.sp, color = TextSub),
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(horizontal = 13.dp, vertical = 7.dp)
            )
        }
    }

    // 规范里 App Bar 下方不是实线，是一道约 14dp 的渐隐阴影
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(14.dp)
            .background(
                Brush.verticalGradient(
                    listOf(Color(0x12000000), Color(0x00000000))
                )
            )
    )
}

private enum class BarIcon { BACK, BACKSPACE }

@Composable
private fun ClipboardList(
    records: List<ClipItem>,
    onInsert: (String) -> Unit,
    onRefresh: () -> Unit,
    onDeleteItem: (String) -> Unit,
    onLongPress: (String) -> Unit
) {
    if (records.isEmpty()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clickable { onRefresh() },
            contentAlignment = Alignment.Center
        ) {
            BasicText(
                text = "复制点什么，点这里刷新",
                style = TextStyle(fontSize = 14.sp, color = TextSub)
            )
        }
        return
    }

    val now = System.currentTimeMillis()

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp),
        contentPadding = PaddingValues(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        items(records, key = { it.id }) { item ->
            val visibleState = remember(item.id) { MutableTransitionState(true) }

            // 收起动画播完才真正删库，避免卡片瞬间消失
            LaunchedEffect(visibleState.isIdle, visibleState.currentState) {
                if (visibleState.isIdle && !visibleState.currentState) {
                    onDeleteItem(item.id)
                }
            }

            AnimatedVisibility(
                visibleState = visibleState,
                enter = expandVertically(animationSpec = tween(220)) + fadeIn(tween(180)),
                exit = shrinkVertically(animationSpec = tween(220)) + fadeOut(tween(140))
            ) {
                ClipCard(
                    item = item,
                    now = now,
                    onClick = { onInsert(item.text) },
                    onLongClick = { onLongPress(item.text) },
                    onDelete = { visibleState.targetState = false }
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ClipCard(
    item: ClipItem,
    now: Long,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onDelete: () -> Unit
) {
    var offsetX by remember(item.id) { mutableStateOf(0f) }
    var confirming by remember(item.id) { mutableStateOf(false) }

    val density = LocalDensity.current
    val maxOffset = with(density) { 76.dp.toPx() }
    val threshold = with(density) { 34.dp.toPx() }

    val dragState = rememberDraggableState { delta ->
        offsetX = (offsetX + delta).coerceIn(-maxOffset, maxOffset)
    }

    // 规范：列表行按下整行变蓝，文字变白，是瞬时的换色，不是涟漪
    val cardInteraction = remember { MutableInteractionSource() }
    val cardPressed by cardInteraction.collectIsPressedAsState()

    // 删除：整条记录放大、上飘、模糊、淡出，像一缕烟散掉
    var exploding by remember(item.id) { mutableStateOf(false) }
    val explode by animateFloatAsState(
        targetValue = if (exploding) 1f else 0f,
        animationSpec = tween(durationMillis = 340, easing = FastOutSlowInEasing),
        label = "cardExplode"
    )

    LaunchedEffect(exploding) {
        if (exploding) {
            delay(340)
            onDelete()
        }
    }

    Box(modifier = Modifier.fillMaxWidth()) {
        if (offsetX > 0.5f) {
            Box(Modifier.matchParentSize()) {
                DeleteAction(
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .padding(start = 16.dp)
                        .size(48.dp),
                    confirming = confirming,
                    onClick = { if (confirming) exploding = true else confirming = true }
                )
            }
        }

        if (offsetX < -0.5f) {
            Box(Modifier.matchParentSize()) {
                DeleteAction(
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .padding(end = 16.dp)
                        .size(48.dp),
                    confirming = confirming,
                    onClick = { if (confirming) exploding = true else confirming = true }
                )
            }
        }

        Column(
            modifier = Modifier
                .offset { IntOffset(offsetX.roundToInt(), 0) }
                .fillMaxWidth()
                .graphicsLayer {
                    val s = 1f + 0.04f * explode
                    scaleX = s
                    scaleY = s
                    alpha = 1f - explode
                    translationY = -6.dp.toPx() * explode
                }
                .blur((9f * explode).dp)
                .draggable(
                    orientation = Orientation.Horizontal,
                    state = dragState,
                    onDragStopped = {
                        offsetX = if (abs(offsetX) > threshold) {
                            if (offsetX > 0) maxOffset else -maxOffset
                        } else {
                            confirming = false
                            0f
                        }
                    }
                )
                .combinedClickable(
                    interactionSource = cardInteraction,
                    indication = null,
                    onClick = onClick,
                    onLongClick = onLongClick
                )
                .shadow(
                    elevation = 8.dp,
                    shape = RoundedCornerShape(CardCorner),
                    clip = false,
                    ambientColor = Color(0x0A000000),
                    spotColor = Color(0x0A000000)
                )
                .background(
                    brush = if (cardPressed) {
                        Brush.verticalGradient(listOf(Color(0xFF5F8AEC), Color(0xFF5883EB)))
                    } else {
                        Brush.verticalGradient(listOf(Color(0xFFFFFFFF), Color(0xFFFCFCFC)))
                    },
                    shape = RoundedCornerShape(CardCorner)
                )
                .border(
                    width = 0.8.dp,
                    color = if (cardPressed) Color(0xFF3F68E2) else Hairline,
                    shape = RoundedCornerShape(CardCorner)
                )
                .padding(horizontal = 12.dp, vertical = 9.dp)
        ) {
            BasicText(
                text = item.text.replace("\n", " "),
                style = TextStyle(
                    fontSize = 16.sp,
                    color = if (cardPressed) Color.White else TextMain
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(6.dp))
            BasicText(
                text = "${item.text.length} 字 · ${RelativeTime.format(now, item.createdAt)}",
                style = TextStyle(
                    fontSize = 12.sp,
                    color = if (cardPressed) Color(0xCCFFFFFF) else TextHint
                )
            )
        }
    }
}

@Composable
private fun DeleteAction(modifier: Modifier, confirming: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .shadow(
                elevation = 4.dp,
                shape = CircleShape,
                clip = false,
                spotColor = Color(0x40CD3F3A)
            )
            .background(
                brush = if (confirming) {
                    Brush.verticalGradient(listOf(Color(0xFFB23A35), Color(0xFFA32D2D)))
                } else {
                    Brush.verticalGradient(listOf(Color(0xFFD6504B), Color(0xFFC83530)))
                },
                shape = CircleShape
            )
            .border(
                width = 0.8.dp,
                color = if (confirming) Color(0xFF8C2620) else Color(0xFFB7241F),
                shape = CircleShape
            )
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        if (confirming) {
            BasicText(
                text = "确认",
                style = TextStyle(fontSize = 12.sp, color = Color.White)
            )
        } else {
            TrashIcon(tint = Color.White)
        }
    }
}

@Composable
private fun PlaceholderKeyboard(onInsert: (String) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        BasicText(
            text = "字母键盘待接入",
            style = TextStyle(fontSize = 14.sp, color = TextSub)
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(3) { i ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(40.dp)
                        .background(CardBg, RoundedCornerShape(2.dp))
                        .border(0.8.dp, Hairline, RoundedCornerShape(2.dp))
                        .clickable { onInsert((i + 1).toString()) },
                    contentAlignment = Alignment.Center
                ) {
                    BasicText(
                        text = "${i + 1}",
                        style = TextStyle(fontSize = 15.sp, color = TextMain)
                    )
                }
            }
        }
    }
}

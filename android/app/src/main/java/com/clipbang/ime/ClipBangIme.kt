package com.clipbang.ime

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.AndroidUiDispatcher
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.clipbang.data.ClipItem
import com.clipbang.data.ClipStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 输入法服务。平台实现层。
 *
 * 职责：提供数据、接收插入请求、把文本写进当前输入框。
 * 界面逻辑在 PanelUi，分词在 core，存储与清理规则在 ClipStore。
 *
 * 关于 Compose：输入法服务不是 Activity，窗口根视图上没有生命周期宿主，
 * Compose 会直接抛 ViewTreeLifecycleOwner not found。所以这里自己建一个
 * 组合器并跑起来，交给 ComposeView 用，绕开窗口查找。
 */
class ClipBangIme : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateController = SavedStateRegistryController.create(this)
    private val recomposer = Recomposer(AndroidUiDispatcher.Main)

    private lateinit var store: ClipStore

    private val items = mutableStateOf<List<ClipItem>>(emptyList())
    private val panelMode = mutableStateOf(PanelMode.CLIPBOARD)

    /** 复制即入库。设成默认输入法后这个回调才稳定收得到。 */
    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        captureClipboard()
    }

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry get() = savedStateController.savedStateRegistry

    override fun onCreate() {
        super.onCreate()
        savedStateController.performRestore(null)
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
        lifecycleScope.launch(AndroidUiDispatcher.Main) { recomposer.runRecomposeAndApplyChanges() }

        store = ClipStore(this)

        clipboardManager()?.addPrimaryClipChangedListener(clipListener)

        lifecycleScope.launch(Dispatchers.IO) {
            store.purgeExpired()
            val fresh = store.list()
            withContext(Dispatchers.Main) { items.value = fresh }
        }

        Log.d(TAG, "service created")
    }

    override fun onCreateInputView(): View {
        tintSystemBars()

        val heightPx = (PANEL_HEIGHT_DP * resources.displayMetrics.density).toInt()

        val composeView = ComposeView(this).apply {
            setViewTreeLifecycleOwner(this@ClipBangIme)
            setViewTreeSavedStateRegistryOwner(this@ClipBangIme)
            setParentCompositionContext(recomposer)
            setContent {
                ClipBangPanel(
                    mode = panelMode.value,
                    records = items.value,
                    onModeChange = { panelMode.value = it },
                    onInsert = { insert(it) },
                    onDelete = { deleteBackward() },
                    onDeleteItem = { id -> deleteItem(id) },
                    onRefresh = { captureClipboard() }
                )
            }
        }

        // 输入法窗口按 WRAP_CONTENT 测量 inputView，Compose 的固定高度撑不开，
        // 外面套一层容器把高度钉死，也保证切换面板时高度不变。
        val container = FrameLayout(this)
        container.addView(
            composeView,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, heightPx)
        )
        container.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, heightPx)
        return container
    }

    override fun onStartInputView(info: android.view.inputmethod.EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        // 面板弹出时补录一次，兜住监听漏掉的场景
        captureClipboard()
    }

    override fun onDestroy() {
        clipboardManager()?.removePrimaryClipChangedListener(clipListener)
        recomposer.cancel()
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        super.onDestroy()
    }

    private fun clipboardManager(): ClipboardManager? =
        getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    /**
     * 把底部导航栏染成面板底色，并去掉系统强制的半透明遮罩、把图标转成深色。
     * 安卓没有"读内容自动取色"的接口，但导航栏颜色本来就能自己指定，
     * 设成同一个底色在视觉上就是连成一片。
     */
    private fun tintSystemBars() {
        val dialogWindow = window?.window ?: return

        dialogWindow.navigationBarColor = PANEL_BG_COLOR

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // 关掉系统为了对比度加的那层半透明黑，否则浅色也会被压暗
            dialogWindow.isNavigationBarContrastEnforced = false
        }

        WindowInsetsControllerCompat(dialogWindow, dialogWindow.decorView)
            .isAppearanceLightNavigationBars = true
    }

    private fun captureClipboard() {
        val text = readClipboard() ?: return
        if (text.isBlank()) return

        lifecycleScope.launch(Dispatchers.IO) {
            store.put(text)
            val fresh = store.list()
            withContext(Dispatchers.Main) { items.value = fresh }
        }
    }

    /**
     * 读系统剪贴板。带敏感标记的内容（密码管理器这类）直接跳过，连内存都不进。
     */
    private fun readClipboard(): String? {
        val cm = clipboardManager() ?: return null
        val clip = cm.primaryClip ?: return null
        if (clip.itemCount == 0) return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val sensitive = clip.description.extras
                ?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) ?: false
            if (sensitive) return null
        }

        return clip.getItemAt(0).coerceToText(this)?.toString()
    }

    private fun insert(text: String) {
        currentInputConnection?.commitText(text, 1)
    }

    /** 退格，一次删一个字，跟系统键盘的删除键一致 */
    private fun deleteBackward() {
        currentInputConnection?.deleteSurroundingText(1, 0)
    }

    /** 删除一条记录 */
    private fun deleteItem(id: String) {
        lifecycleScope.launch(Dispatchers.IO) {
            store.delete(id)
            val fresh = store.list()
            withContext(Dispatchers.Main) { items.value = fresh }
        }
    }

    companion object {
        private const val TAG = "ClipBangIme"

        /** 面板高度，与 PanelUi 里的 PanelHeight 必须一致 */
        const val PANEL_HEIGHT_DP = 280

        /** 面板底色，与 PanelUi 里的 PageBg 必须一致 */
        private const val PANEL_BG_COLOR = 0xFFF5F5F5.toInt()
    }
}

enum class PanelMode {
    CLIPBOARD,
    KEYBOARD
}

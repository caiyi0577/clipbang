package com.clipbang

import android.content.ClipData
import android.content.ClipboardManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 开发调试入口。一个输入框用来唤起输入法，一个按钮用来往剪贴板写测试文本。
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            var text by remember { mutableStateOf("") }

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0xFFF5F5F5))
                    .padding(16.dp)
            ) {
                BasicText(
                    text = "剪贴炸",
                    style = TextStyle(fontSize = 20.sp, color = Color(0xFF333333))
                )
                Spacer(Modifier.height(6.dp))
                BasicText(
                    text = "先写入一条测试文字，再点下面的框唤起键盘",
                    style = TextStyle(fontSize = 12.sp, color = Color(0xFF7F7F7F))
                )
                Spacer(Modifier.height(16.dp))

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .background(
                            brush = androidx.compose.ui.graphics.Brush.verticalGradient(
                                listOf(Color(0xFF5B87EB), Color(0xFF5883EB))
                            ),
                            shape = RoundedCornerShape(3.dp)
                        )
                        .border(0.8.dp, Color(0xFF3F68E2), RoundedCornerShape(3.dp))
                        .clickable { writeTestClip() },
                    contentAlignment = Alignment.Center
                ) {
                    BasicText(
                        text = "写入测试文字到剪贴板",
                        style = TextStyle(fontSize = 14.sp, color = Color.White)
                    )
                }

                Spacer(Modifier.height(14.dp))

                BasicTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(110.dp)
                        .background(Color.White, RoundedCornerShape(3.dp))
                        .border(0.5.dp, Color(0xFFE2E2E2), RoundedCornerShape(3.dp))
                        .padding(12.dp),
                    textStyle = TextStyle(fontSize = 15.sp, color = Color(0xFF333333)),
                    decorationBox = { inner ->
                        if (text.isEmpty()) {
                            BasicText(
                                text = "点这里唤起键盘",
                                style = TextStyle(fontSize = 15.sp, color = Color(0xFFBABABA))
                            )
                        }
                        inner()
                    }
                )
            }
        }
    }

    private fun writeTestClip() {
        val cm = getSystemService(ClipboardManager::class.java) ?: return
        val stamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            .format(java.util.Date())
        cm.setPrimaryClip(
            ClipData.newPlainText("测试", "明天下午三点，张江地铁站 2 号口，别迟到 $stamp")
        )
    }
}

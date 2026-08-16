package com.pagenote.pagenote

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider

/**
 * 桌面小组件（REQ-14）：连续记录天数 + 今日是否已写 + 今日一问,
 * 点击直达编辑页。数据由 Flutter 侧经 MainActivity 写入
 * SharedPreferences("pagenote_widget") 并广播刷新。
 */
class HomeScreenWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs =
            context.getSharedPreferences("pagenote_widget", Context.MODE_PRIVATE)
        val streak = prefs.getInt("streak", 0)
        val written = prefs.getBoolean("writtenToday", false)
        val prompt = prefs.getString("prompt", "") ?: ""
        provideContent {
            WidgetContent(streak = streak, written = written, prompt = prompt)
        }
    }
}

@Composable
private fun WidgetContent(
    streak: Int,
    written: Boolean,
    prompt: String,
) {
    // 纸质暖色,与应用分享卡（REQ-11）风格一致。
    val paper = Color(0xFFF9F3E8)
    val ink = Color(0xFF4A3F35)
    val subInk = Color(0xFF8A7B6C)
    val accent = Color(0xFFE8734A)

    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(paper)
            .cornerRadius(20.dp)
            .clickable(actionRunCallback<OpenEditorAction>())
            .padding(14.dp),
    ) {
        Column(
            modifier = GlanceModifier.fillMaxSize(),
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "📖 拾页",
                    style = TextStyle(
                        color = ColorProvider(accent),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = if (written) "今日已写 ✅" else "今天还没写 ✍️",
                    style = TextStyle(
                        color = ColorProvider(if (written) subInk else accent),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
            }
            Spacer(modifier = GlanceModifier.height(8.dp))
            Text(
                text = if (streak > 0) "连续记录 $streak 天" else "开始你的第一页",
                style = TextStyle(
                    color = ColorProvider(ink),
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Spacer(modifier = GlanceModifier.height(6.dp))
            Text(
                text = "今日一问 · $prompt",
                style = TextStyle(
                    color = ColorProvider(subInk),
                    fontSize = 12.sp,
                ),
                maxLines = 3,
            )
            Spacer(modifier = GlanceModifier.defaultWeight())
            Text(
                text = "点按直接开始写手账",
                style = TextStyle(
                    color = ColorProvider(subInk),
                    fontSize = 10.sp,
                ),
            )
        }
    }
}

/** 点击小组件任意位置:带 open_editor 标记拉起应用直达编辑页（REQ-14）。 */
class OpenEditorAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: androidx.glance.action.ActionParameters,
    ) {
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("open_editor", true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}

class HomeScreenWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HomeScreenWidget()
}

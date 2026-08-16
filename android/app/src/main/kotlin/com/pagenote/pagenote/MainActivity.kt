package com.pagenote.pagenote

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity：local_auth 生物识别需要 Fragment 支持（REQ-08）。
class MainActivity : FlutterFragmentActivity() {

    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pagenote/app"
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // 桌面小组件（REQ-14）：写入展示数据并触发刷新。
                    "widget.update" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any?>()
                        updateWidgetData(args)
                        result.success(true)
                    }
                    // 冷启动：启动 intent 是否来自小组件点击。
                    "widget.consumeLaunchAction" -> {
                        val open = intent?.getBooleanExtra("open_editor", false) ?: false
                        if (open) intent?.removeExtra("open_editor")
                        result.success(open)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 应用已在运行时点击小组件：转发给 Dart 直达编辑页（REQ-14）。
        if (intent.getBooleanExtra("open_editor", false)) {
            intent.removeExtra("open_editor")
            channel?.invokeMethod("widget.openEditor", null)
        }
    }

    private fun updateWidgetData(args: Map<*, *>) {
        val streak = (args["streak"] as? Number)?.toInt() ?: 0
        val written = args["writtenToday"] as? Boolean ?: false
        val prompt = args["prompt"] as? String ?: ""
        getSharedPreferences("pagenote_widget", MODE_PRIVATE)
            .edit()
            .putInt("streak", streak)
            .putBoolean("writtenToday", written)
            .putString("prompt", prompt)
            .apply()
        refreshWidget()
    }

    // 广播 APPWIDGET_UPDATE（带 ids）触发 Glance 重新渲染。
    private fun refreshWidget() {
        val manager = AppWidgetManager.getInstance(this)
        val ids = manager.getAppWidgetIds(
            ComponentName(this, HomeScreenWidgetReceiver::class.java)
        )
        if (ids.isEmpty()) return
        val intent = Intent(this, HomeScreenWidgetReceiver::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        sendBroadcast(intent)
    }
}

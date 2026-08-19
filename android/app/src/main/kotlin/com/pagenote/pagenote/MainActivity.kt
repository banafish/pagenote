package com.pagenote.pagenote

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// 分享包单包体积上限（NFR-06）：超出直接丢弃，不把超大文件带进 Dart 侧解压。
private const val MAX_PACK_BYTES = 20L * 1024 * 1024

// 分享包落地目录：应用私有缓存，每次只保留待消费的那一个包。
private const val PACK_INBOX_DIR = "share_pack_inbox"

// FlutterFragmentActivity：local_auth 生物识别需要 Fragment 支持（REQ-08）。
class MainActivity : FlutterFragmentActivity() {

    private var channel: MethodChannel? = null

    // 待 Dart 侧来取的分享包（REQ-21.11）：{path, name}。
    // 与 open_editor 同一套「暂存 + 主动来取」思路，避开引擎未就绪时丢事件。
    private var pendingPack: Map<String, String>? = null

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
                    // 分享包（REQ-21.11）：取走暂存的 zip，取一次即清空。
                    "sharePack.consumePending" -> {
                        val pack = pendingPack
                        pendingPack = null
                        result.success(pack)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 冷启动：被文件管理器 / 微信 / QQ 以 zip 拉起（REQ-21.11）。
        // 仅首次创建时收，避免旋转重建后重复导入同一个包。
        if (savedInstanceState == null) stashSharePack(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 应用已在运行时点击小组件：转发给 Dart 直达编辑页（REQ-14）。
        if (intent.getBooleanExtra("open_editor", false)) {
            intent.removeExtra("open_editor")
            channel?.invokeMethod("widget.openEditor", null)
        }
        // 热启动收到的分享包同样只暂存；onNewIntent 之后必然走一次 onResume，
        // Dart 侧在回到前台时来取（'pagenote/app' 的回调已被小组件占用，不便再挂一个）。
        stashSharePack(intent)
    }

    // 从 intent 里认领分享包 zip，复制进私有缓存待 Dart 侧取用。
    private fun stashSharePack(intent: Intent?) {
        val uri = claimPackUri(intent) ?: return
        val file = copyToInbox(uri) ?: return
        pendingPack = mapOf(
            "path" to file.absolutePath,
            "name" to displayName(uri)
        )
    }

    // ACTION_VIEW 走 data，ACTION_SEND 走 EXTRA_STREAM；两者的 content:// 与
    // file:// 都由 ContentResolver 统一读取。取到后立刻从 intent 上摘除，
    // 防止后续生命周期回调里被二次认领。
    private fun claimPackUri(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.also { intent.data = null }
            Intent.ACTION_SEND -> extraStream(intent)?.also {
                intent.removeExtra(Intent.EXTRA_STREAM)
            }
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun extraStream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    // 边读边计体积，超上限即放弃（NFR-06）。读失败返回 null，静默忽略这次分享。
    private fun copyToInbox(uri: Uri): File? {
        val dir = File(cacheDir, PACK_INBOX_DIR)
        dir.deleteRecursively()
        dir.mkdirs()
        if (!dir.isDirectory) return null
        val target = File(dir, "pack_${System.currentTimeMillis()}.zip")
        return try {
            contentResolver.openInputStream(uri).use { input ->
                if (input == null) return null
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        total += read
                        if (total > MAX_PACK_BYTES) {
                            target.delete()
                            return null
                        }
                        output.write(buffer, 0, read)
                    }
                }
            }
            target
        } catch (e: Exception) {
            target.delete()
            null
        }
    }

    // 来源文件名仅用于导入页副标题，取不到就退回路径末段。
    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) {
                        val name = cursor.getString(index)
                        if (!name.isNullOrEmpty()) return name
                    }
                }
            } catch (e: Exception) {
                // 部分文件管理器不实现 OpenableColumns：降级用路径末段。
            }
        }
        return uri.lastPathSegment ?: ""
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
